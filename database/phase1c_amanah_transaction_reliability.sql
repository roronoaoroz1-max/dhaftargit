-- Phase 1C: retry-safe grouped repayments and custody account transactions.
-- Apply after Phase 1A and 1B, in staging before production.
begin;
alter table public.dhaftar_transaction_receipts_v1
  drop constraint dhaftar_transaction_receipts_v1_scope_check,
  add constraint dhaftar_transaction_receipts_v1_scope_check check
    (scope in ('household-payment','spending-entry','loan-repayment','account-transaction'));

-- Protect legacy direct inserts too, using the same loan-row lock as the RPC.
create function public.dhaftar_validate_loan_repayment_v1()
returns trigger language plpgsql security invoker set search_path='' as $$
declare v_loan public.loans%rowtype; v_paid numeric;
begin
  select * into v_loan from public.loans where id=new.loan_id for update;
  if not found or v_loan.status='cancelled' then
    raise exception 'Loan is unavailable or cancelled' using errcode='23514';
  end if;
  select coalesce(sum(amount),0) into v_paid from public.loan_payments where loan_id=new.loan_id;
  if new.amount > v_loan.principal_amount-v_paid then
    raise exception 'Repayment exceeds outstanding loan balance' using errcode='23514';
  end if;
  return new;
end $$;
revoke all on function public.dhaftar_validate_loan_repayment_v1() from public,anon;
grant execute on function public.dhaftar_validate_loan_repayment_v1() to authenticated;
create trigger dhaftar_validate_loan_repayment_v1 before insert on public.loan_payments
for each row execute function public.dhaftar_validate_loan_repayment_v1();

create function public.dhaftar_record_group_repayment_v1(
 p_request_id uuid,p_lender uuid,p_borrower uuid,p_currency text,p_date date,
 p_amount numeric,p_method text,p_notes text
) returns uuid language plpgsql security invoker set search_path='' as $$
declare
 v_user uuid:=auth.uid(); v_payload jsonb; v_existing jsonb;
 v_currency text:=lower(trim(p_currency)); v_left numeric:=p_amount;
 v_allocation numeric; v_loan record;
begin
 if v_user is null or not public.is_admin() then raise exception 'Administrator access required' using errcode='42501'; end if;
 if p_request_id is null or p_lender is null or p_borrower is null or p_lender=p_borrower or v_currency is null or v_currency='' or p_date is null or p_amount is null or p_amount<=0 or p_amount<>round(p_amount,2) or p_amount>=1000000000000 then
   raise exception 'Invalid repayment details' using errcode='22023';
 end if;
 v_payload:=jsonb_build_array(p_lender,p_borrower,v_currency,p_date,p_amount,p_method,p_notes);
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('dhaftar-repayment-request:'||p_request_id::text,0));
 select payload into v_existing from public.dhaftar_transaction_receipts_v1
 where user_id=v_user and scope='loan-repayment' and request_id=p_request_id;
 if found then
   if v_existing<>v_payload then raise exception 'Request ID already used for different details' using errcode='22023'; end if;
   return p_request_id;
 end if;
 -- Lock in deterministic order before reading the latest amounts.
 perform 1 from public.loans where lender_id=p_lender and borrower_id=p_borrower
 and lower(trim(currency))=v_currency order by id for update;
 for v_loan in
   select loan_id,remaining_amount from public.loan_balances
   where lender_id=p_lender and borrower_id=p_borrower and lower(trim(currency))=v_currency
     and calculated_status not in ('cancelled','paid') and remaining_amount>0
   order by coalesce(loan_date,(created_at at time zone 'UTC')::date),created_at,loan_id
 loop
   exit when v_left=0;
   v_allocation:=least(v_left,v_loan.remaining_amount);
   insert into public.loan_payments(user_id,loan_id,payment_date,amount,payment_method,notes)
     values(v_user,v_loan.loan_id,p_date,v_allocation,p_method,p_notes);
   v_left:=v_left-v_allocation;
 end loop;
 if v_left<>0 then raise exception 'Repayment exceeds latest combined outstanding balance. No payment was saved.' using errcode='23514'; end if;
 insert into public.dhaftar_transaction_receipts_v1(user_id,scope,request_id,payload)
   values(v_user,'loan-repayment',p_request_id,v_payload);
 return p_request_id;
end $$;
revoke all on function public.dhaftar_record_group_repayment_v1(uuid,uuid,uuid,text,date,numeric,text,text) from public,anon;
grant execute on function public.dhaftar_record_group_repayment_v1(uuid,uuid,uuid,text,date,numeric,text,text) to authenticated;

create function public.dhaftar_record_account_transaction_v1(
 p_request_id uuid,p_account uuid,p_date date,p_type text,p_amount numeric,p_description text,p_reference text
) returns uuid language plpgsql security invoker set search_path='' as $$
declare v_user uuid:=auth.uid(); v_payload jsonb; v_existing jsonb;
begin
 if v_user is null or not public.is_admin() then raise exception 'Administrator access required' using errcode='42501'; end if;
 if p_request_id is null or p_account is null or p_date is null or p_type is null or p_type not in ('deposit','withdrawal','adjustment_in','adjustment_out') or p_amount is null or p_amount<=0 or p_amount<>round(p_amount,2) or p_amount>=1000000000000 then
   raise exception 'Invalid account transaction details' using errcode='22023';
 end if;
 v_payload:=jsonb_build_array(p_account,p_date,p_type,p_amount,p_description,p_reference);
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('dhaftar-account-request:'||p_request_id::text,0));
 select payload into v_existing from public.dhaftar_transaction_receipts_v1
 where user_id=v_user and scope='account-transaction' and request_id=p_request_id;
 if found then
   if v_existing<>v_payload then raise exception 'Request ID already used for different details' using errcode='22023'; end if;
   return p_request_id;
 end if;
 perform 1 from public.accounts where id=p_account for update;
 if not found then raise exception 'Account not found' using errcode='23503'; end if;
 -- Do not change custody balance rules or introduce new overdraft restrictions.
 insert into public.account_transactions(id,user_id,account_id,transaction_date,transaction_type,amount,description,reference_number)
   values(p_request_id,v_user,p_account,p_date,p_type,p_amount,p_description,p_reference);
 insert into public.dhaftar_transaction_receipts_v1(user_id,scope,request_id,payload)
   values(v_user,'account-transaction',p_request_id,v_payload);
 return p_request_id;
end $$;
revoke all on function public.dhaftar_record_account_transaction_v1(uuid,uuid,date,text,numeric,text,text) from public,anon;
grant execute on function public.dhaftar_record_account_transaction_v1(uuid,uuid,date,text,numeric,text,text) to authenticated;
commit;
