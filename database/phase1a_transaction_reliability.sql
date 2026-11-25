-- Phase 1A: atomic stock purchases and durable savings writes.
-- Apply to a staging database first. Additive only; no legacy rows are changed.
begin;

create or replace function public.dhaftar_record_stock_purchase_v1(
  p_request_id uuid, p_item_id uuid, p_date date, p_quantity numeric,
  p_amount numeric, p_note text
) returns uuid language plpgsql security invoker set search_path = '' as $$
declare
  v_user uuid := auth.uid();
  v_existing public.stock_purchases%rowtype;
  v_previous public.stock_purchases%rowtype;
  v_archived boolean;
begin
  if v_user is null or not public.is_admin() then raise exception 'Administrator access required' using errcode='42501'; end if;
  if p_request_id is null or p_item_id is null or p_date is null or p_quantity is null or p_quantity <= 0 or p_quantity >= 100000000000 or p_quantity <> round(p_quantity,3) or p_quantity::text in ('NaN','Infinity','-Infinity') or p_amount is null or p_amount < 0 or p_amount >= 1000000000000 or p_amount <> round(p_amount,2) or p_amount::text in ('NaN','Infinity','-Infinity') then
    raise exception 'Invalid purchase details' using errcode='22023';
  end if;
  -- Serialize retries and new purchases for the same item.
  select archived into v_archived from public.stock_items where id=p_item_id for update;
  if not found then raise exception 'Stock item unavailable'; end if;
  select * into v_existing from public.stock_purchases where id=p_request_id;
  if found then
    if v_existing.stock_item_id is distinct from p_item_id or v_existing.created_by is distinct from v_user or v_existing.purchased_on is distinct from p_date or v_existing.quantity is distinct from p_quantity or v_existing.amount is distinct from p_amount or v_existing.note is distinct from nullif(trim(p_note),'') then
      raise exception 'Request ID already used for different details' using errcode='22023';
    end if;
    return v_existing.id;
  end if;
  if v_archived then raise exception 'Stock item unavailable'; end if;
  if exists (select 1 from public.stock_purchases where stock_item_id=p_item_id and voided_at is null and purchased_on>p_date) then
    raise exception 'Purchase date precedes existing stock history' using errcode='22023';
  end if;
  if (select count(*) from public.stock_purchases where stock_item_id=p_item_id and voided_at is null and run_out_on is null and ended_reason is null)>1 then
    raise exception 'Multiple open stock cycles need review; no purchase was recorded' using errcode='23514';
  end if;
  select * into v_previous from public.stock_purchases
    where stock_item_id=p_item_id and voided_at is null and run_out_on is null and ended_reason is null
    order by purchased_on desc, created_at desc, id desc limit 1 for update;
  if found then
    if p_date < v_previous.purchased_on then raise exception 'Purchase date precedes the current stock cycle'; end if;
    update public.stock_purchases set ended_reason='restocked', ended_on=p_date where id=v_previous.id;
  end if;
  insert into public.stock_purchases(id,stock_item_id,purchased_on,quantity,amount,note,created_by)
    values(p_request_id,p_item_id,p_date,p_quantity,p_amount,nullif(trim(p_note),''),v_user);
  return p_request_id;
end $$;
revoke all on function public.dhaftar_record_stock_purchase_v1(uuid,uuid,date,numeric,numeric,text) from public,anon;
grant execute on function public.dhaftar_record_stock_purchase_v1(uuid,uuid,date,numeric,numeric,text) to authenticated;

-- Protect even older clients' direct INSERTs. Serialize savings writes per owner.
create or replace function public.dhaftar_validate_savings_insert_v1()
returns trigger language plpgsql security invoker set search_path = '' as $$
declare v_balance numeric;
begin
  if new.amount::text in ('NaN','Infinity','-Infinity') then raise exception 'Invalid savings amount' using errcode='22023'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('dhaftar-savings:' || new.user_id::text,0));
  if new.transaction_type='withdrawal' then
    select coalesce(sum(case when transaction_type='deposit' then amount else -amount end),0)
      into v_balance from public.amanah_personal_savings_transactions where user_id=new.user_id;
    if new.amount > v_balance then raise exception 'Withdrawal exceeds available savings' using errcode='23514'; end if;
  end if;
  return new;
end $$;
revoke all on function public.dhaftar_validate_savings_insert_v1() from public,anon;
grant execute on function public.dhaftar_validate_savings_insert_v1() to authenticated;
create trigger dhaftar_validate_savings_insert_v1 before insert on public.amanah_personal_savings_transactions
for each row execute function public.dhaftar_validate_savings_insert_v1();

create or replace function public.dhaftar_record_savings_v1(p_request_id uuid,p_date date,p_type text,p_amount numeric,p_note text)
returns uuid language plpgsql security invoker set search_path = '' as $$
declare v_user uuid:=auth.uid(); v_existing public.amanah_personal_savings_transactions%rowtype;
begin
  if v_user is null or not public.is_admin() then raise exception 'Administrator access required' using errcode='42501'; end if;
  if p_request_id is null or p_date is null or p_type is null or p_type not in ('deposit','withdrawal') or p_amount is null or p_amount <= 0 or p_amount <> round(p_amount,2) or p_amount >= 1000000000000 then raise exception 'Invalid savings details' using errcode='22023'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('dhaftar-savings:' || v_user::text,0));
  select * into v_existing from public.amanah_personal_savings_transactions where id=p_request_id and user_id=v_user;
  if found then
    if v_existing.transaction_date is distinct from p_date or v_existing.transaction_type is distinct from p_type or v_existing.amount is distinct from p_amount or v_existing.note is distinct from nullif(trim(p_note),'') then raise exception 'Request ID already used for different details' using errcode='22023'; end if;
    return v_existing.id;
  end if;
  insert into public.amanah_personal_savings_transactions(id,user_id,transaction_date,transaction_type,amount,note)
    values(p_request_id,v_user,p_date,p_type,p_amount,nullif(trim(p_note),''));
  return p_request_id;
end $$;
revoke all on function public.dhaftar_record_savings_v1(uuid,date,text,numeric,text) from public,anon;
grant execute on function public.dhaftar_record_savings_v1(uuid,date,text,numeric,text) to authenticated;

create or replace function public.dhaftar_savings_balance_v1()
returns numeric language plpgsql stable security invoker set search_path = '' as $$
begin
  if auth.uid() is null or not public.is_admin() then raise exception 'Administrator access required' using errcode='42501'; end if;
  return (select coalesce(sum(case when transaction_type='deposit' then amount else -amount end),0) from public.amanah_personal_savings_transactions where user_id=auth.uid());
end $$;
revoke all on function public.dhaftar_savings_balance_v1() from public,anon;
grant execute on function public.dhaftar_savings_balance_v1() to authenticated;
commit;
