-- Phase 1B: immutable request receipts for household payments and spending.
-- Deploy only after staging verification; additive schema changes preserve all existing records.
begin;

create table public.dhaftar_transaction_receipts_v1 (
  user_id uuid not null references auth.users(id),
  scope text not null check (scope in ('household-payment','spending-entry')),
  request_id uuid not null,
  payload jsonb not null,
  created_at timestamptz not null default now(),
  primary key (user_id,scope,request_id)
);
alter table public.dhaftar_transaction_receipts_v1 enable row level security;
revoke all on public.dhaftar_transaction_receipts_v1 from public,anon,authenticated;
grant select,insert on public.dhaftar_transaction_receipts_v1 to authenticated;
create policy "Admin reads own transaction receipts" on public.dhaftar_transaction_receipts_v1 for select to authenticated
using ((select auth.uid())=user_id and (select public.is_admin()));
create policy "Admin inserts own transaction receipts" on public.dhaftar_transaction_receipts_v1 for insert to authenticated
with check ((select auth.uid())=user_id and (select public.is_admin()));

alter table public.dhaftar_spending_entries
  add column voided_at timestamptz,
  add column voided_by uuid references auth.users(id),
  add column void_reason text,
  add constraint dhaftar_spending_void_consistency_v1 check (
    (voided_at is null and voided_by is null and void_reason is null)
    or (voided_at is not null and voided_by is not null and length(trim(void_reason)) between 1 and 500)
  );

create function public.dhaftar_record_household_payment_v1(
  p_request_id uuid,p_payer text,p_date date,p_month date,p_amount numeric,p_note text
) returns uuid language plpgsql security invoker set search_path='' as $$
declare v_user uuid:=auth.uid(); v_payload jsonb; v_existing jsonb; v_closed text;
begin
  if v_user is null or not public.is_admin() then raise exception 'Administrator access required' using errcode='42501'; end if;
  if p_request_id is null or p_date is null or p_month is null or extract(day from p_month)<>1 or p_payer is null or trim(p_payer)='' or p_amount is null or p_amount<=0 or p_amount<>round(p_amount,2) or p_amount>=1000000000000 then
    raise exception 'Invalid household payment details' using errcode='22023';
  end if;
  v_payload:=jsonb_build_array(p_payer,p_date,p_month,p_amount,p_note);
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('dhaftar-household-request:'||p_request_id::text,0));
  select payload into v_existing from public.dhaftar_transaction_receipts_v1 where user_id=v_user and scope='household-payment' and request_id=p_request_id;
  if found then
    if v_existing<>v_payload then raise exception 'Request ID already used for different details' using errcode='22023'; end if;
    return p_request_id;
  end if;
  select notes into v_closed from public.dhaftar_bills where billing_month=p_month and bill_type='__month_close__';
  if v_closed is not null and v_closed::jsonb->'closed'='true'::jsonb then raise exception 'This month is closed. Unlock it before adding a payment.'; end if;
  insert into public.dhaftar_payments(id,payer_name,payment_date,billing_month,amount,note,created_by)
    values(p_request_id,p_payer,p_date,p_month,p_amount,p_note,v_user);
  insert into public.dhaftar_transaction_receipts_v1(user_id,scope,request_id,payload)
    values(v_user,'household-payment',p_request_id,v_payload);
  return p_request_id;
end $$;
revoke all on function public.dhaftar_record_household_payment_v1(uuid,text,date,date,numeric,text) from public,anon;
grant execute on function public.dhaftar_record_household_payment_v1(uuid,text,date,date,numeric,text) to authenticated;

create function public.dhaftar_record_spending_v1(
  p_request_id uuid,p_type text,p_category text,p_date date,p_amount numeric,p_person text,p_provider text,p_group text,p_notes text
) returns uuid language plpgsql security invoker set search_path='' as $$
declare v_user uuid:=auth.uid(); v_payload jsonb; v_existing jsonb;
begin
  if v_user is null or not public.is_admin() then raise exception 'Administrator access required' using errcode='42501'; end if;
  if p_request_id is null or p_date is null or p_type is null or p_type not in ('enjoyment','medical') or p_category is null or trim(p_category)='' or p_amount is null or p_amount<=0 or p_amount<>round(p_amount,2) or p_amount>=1000000000000 then
    raise exception 'Invalid spending details' using errcode='22023';
  end if;
  v_payload:=jsonb_build_array(p_type,p_category,p_date,p_amount,p_person,p_provider,p_group,p_notes);
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('dhaftar-spending-request:'||p_request_id::text,0));
  select payload into v_existing from public.dhaftar_transaction_receipts_v1 where user_id=v_user and scope='spending-entry' and request_id=p_request_id;
  if found then
    if v_existing<>v_payload then raise exception 'Request ID already used for different details' using errcode='22023'; end if;
    return p_request_id;
  end if;
  insert into public.dhaftar_spending_entries(id,spending_type,category,expense_date,amount,person_name,provider_name,activity_group,notes,created_by)
    values(p_request_id,p_type,p_category,p_date,p_amount,p_person,p_provider,p_group,p_notes,v_user);
  insert into public.dhaftar_transaction_receipts_v1(user_id,scope,request_id,payload)
    values(v_user,'spending-entry',p_request_id,v_payload);
  return p_request_id;
end $$;
revoke all on function public.dhaftar_record_spending_v1(uuid,text,text,date,numeric,text,text,text,text) from public,anon;
grant execute on function public.dhaftar_record_spending_v1(uuid,text,text,date,numeric,text,text,text,text) to authenticated;

create function public.dhaftar_void_spending_v1(p_id uuid,p_reason text)
returns uuid language plpgsql security invoker set search_path='' as $$
declare v_user uuid:=auth.uid(); v_row public.dhaftar_spending_entries%rowtype;
begin
  if v_user is null or not public.is_admin() then raise exception 'Administrator access required' using errcode='42501'; end if;
  if p_id is null or p_reason is null or length(trim(p_reason)) not between 1 and 500 then raise exception 'A reason of 1 to 500 characters is required' using errcode='22023'; end if;
  select * into v_row from public.dhaftar_spending_entries where id=p_id for update;
  if not found then raise exception 'Expense not found'; end if;
  if v_row.voided_at is not null then return p_id; end if;
  update public.dhaftar_spending_entries set voided_at=now(),voided_by=v_user,void_reason=trim(p_reason) where id=p_id;
  return p_id;
end $$;
revoke all on function public.dhaftar_void_spending_v1(uuid,text) from public,anon;
grant execute on function public.dhaftar_void_spending_v1(uuid,text) to authenticated;
-- Older clients must fail safely rather than permanently delete expenses.
revoke delete on public.dhaftar_spending_entries from public,anon,authenticated;
commit;
