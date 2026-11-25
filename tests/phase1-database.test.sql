-- Run only in the synthetic fixture database. No production data or credentials.
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',true);
do $$
declare
 s uuid:=gen_random_uuid(); a uuid:=gen_random_uuid(); b uuid:=gen_random_uuid(); c uuid:=gen_random_uuid();
 item uuid:=gen_random_uuid(); p1 uuid:=gen_random_uuid(); p2 uuid:=gen_random_uuid();
 h uuid:=gen_random_uuid(); e uuid:=gen_random_uuid(); l1 uuid:=gen_random_uuid(); l2 uuid:=gen_random_uuid();
 lender uuid:=gen_random_uuid(); borrower uuid:=gen_random_uuid(); acct uuid:=gen_random_uuid(); r uuid:=gen_random_uuid(); t uuid:=gen_random_uuid();
begin
 perform public.dhaftar_record_savings_v1(s,'2026-01-01','deposit',100,'test');
 perform public.dhaftar_record_savings_v1(s,'2026-01-01','deposit',100,'test');
 if public.dhaftar_savings_balance_v1()<>100 then raise exception 'Savings retry duplicated'; end if;
 begin
  perform public.dhaftar_record_savings_v1(s,'2026-01-01','deposit',101,'test');
  raise exception 'Mismatch was accepted';
 exception when sqlstate '22023' then null; end;
 begin
  perform public.dhaftar_record_savings_v1(a,'2026-01-02','withdrawal',101,null);
  raise exception 'Overdraft was accepted';
 exception when check_violation then null; end;
 perform public.dhaftar_record_savings_v1(b,'2026-01-02','withdrawal',0.29,null);
 perform public.dhaftar_record_savings_v1(b,'2026-01-02','withdrawal',0.29,null);
 if public.dhaftar_savings_balance_v1()<>99.71 then raise exception 'Savings balance wrong'; end if;
 insert into public.stock_items(id,name,unit) values(item,'Test stock','pcs');
 perform public.dhaftar_record_stock_purchase_v1(p1,item,'2026-01-01',2,50,null);
 perform public.dhaftar_record_stock_purchase_v1(p2,item,'2026-01-02',3,75,null);
 perform public.dhaftar_record_stock_purchase_v1(p2,item,'2026-01-02',3,75,null);
 if (select count(*) from public.stock_purchases where stock_item_id=item)<>2 then raise exception 'Stock duplicated'; end if;
 if (select ended_on from public.stock_purchases where id=p1) is distinct from '2026-01-02'::date then raise exception 'Stock cycle closure failed'; end if;
 perform public.dhaftar_record_household_payment_v1(h,'Test payer','2026-01-01','2026-01-01',100,'test');
 insert into public.dhaftar_bills(bill_type,billing_month,notes) values('__month_close__','2026-01-01','{"closed":true}');
 perform public.dhaftar_record_household_payment_v1(h,'Test payer','2026-01-01','2026-01-01',100,'test');
 if (select count(*) from public.dhaftar_payments where id=h)<>1 then raise exception 'Household duplicated'; end if;
 begin
  perform public.dhaftar_record_household_payment_v1(c,'Test payer','2026-01-01','2026-01-01',1,null);
  raise exception 'Closed month write accepted' using errcode='XX000';
 exception when raise_exception then null; end;
 perform public.dhaftar_record_spending_v1(e,'enjoyment','Test','2026-01-01',25,null,null,null,null);
 perform public.dhaftar_record_spending_v1(e,'enjoyment','Test','2026-01-01',25,null,null,null,null);
 perform public.dhaftar_void_spending_v1(e,'Duplicate correction');
 perform public.dhaftar_void_spending_v1(e,'Another reason');
 if (select count(*) from public.dhaftar_spending_entries where id=e and voided_at is not null and void_reason='Duplicate correction')<>1 then raise exception 'Spending void history failed'; end if;
 insert into public.people(id,name) values(lender,'Test lender'),(borrower,'Test borrower');
 insert into public.accounts(id,account_name,owner_id,account_type,currency,opening_balance) values(acct,'Test custody',lender,'custody','MVR',100);
 insert into public.loans(id,lender_id,borrower_id,principal_amount,currency,loan_date) values(l1,lender,borrower,60,'MVR','2026-01-01'),(l2,lender,borrower,40,'MVR','2026-01-02');
 perform public.dhaftar_record_group_repayment_v1(r,lender,borrower,'MVR','2026-01-03',75,null,null);
 perform public.dhaftar_record_group_repayment_v1(r,lender,borrower,'MVR','2026-01-03',75,null,null);
 if (select sum(amount) from public.loan_payments where loan_id=l1) is distinct from 60::numeric or (select sum(amount) from public.loan_payments where loan_id=l2) is distinct from 15::numeric then raise exception 'Repayment allocation wrong'; end if;
 begin
  perform public.dhaftar_record_group_repayment_v1(gen_random_uuid(),lender,borrower,'MVR','2026-01-04',26,null,null);
  raise exception 'Overpayment accepted';
 exception when check_violation then null; end;
 if (select sum(amount) from public.loan_payments where loan_id in(l1,l2))<>75 then raise exception 'Failed repayment not rolled back'; end if;
 perform public.dhaftar_record_account_transaction_v1(t,acct,'2026-01-01','deposit',20,null,null);
 perform public.dhaftar_record_account_transaction_v1(t,acct,'2026-01-01','deposit',20,null,null);
 if (select count(*) from public.account_transactions where id=t)<>1 then raise exception 'Custody transaction duplicated'; end if;
 raise notice 'PASS: six transaction flows, retries, amount mismatches, rollback, closed month, spending void';
end $$;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000002',true);
do $$ begin
 begin
   perform public.dhaftar_record_savings_v1(gen_random_uuid(),'2026-01-01','deposit',5,null);
   raise exception 'Non-admin access accepted';
 exception when insufficient_privilege then null; end;
 if exists(select 1 from public.dhaftar_transaction_receipts_v1) then raise exception 'Non-admin receipt leak'; end if;
end $$;
reset role;
rollback;
