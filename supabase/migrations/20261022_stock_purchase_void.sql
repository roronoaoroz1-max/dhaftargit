-- Dhaftar: reversible stock purchase corrections.
-- Apply to Supabase only after reviewing a database backup.
alter table public.stock_purchases
  add column if not exists voided_at timestamptz,
  add column if not exists voided_by uuid,
  add column if not exists void_reason text;

create or replace function public.dhaftar_void_stock_purchase(
  p_purchase_id uuid,
  p_reason text
) returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_item uuid;
  v_admin boolean;
begin
  select exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid()) and p.role = 'admin'
  ) into v_admin;
  if not v_admin then
    raise exception 'Only an administrator can void purchases';
  end if;
  if length(trim(coalesce(p_reason,''))) < 3 then
    raise exception 'A correction reason is required';
  end if;

  select stock_item_id into v_item
  from public.stock_purchases
  where id = p_purchase_id and voided_at is null
  for update;
  if v_item is null then
    raise exception 'Purchase not found or already voided';
  end if;

  -- Serialize corrections and purchases for the same item where possible.
  perform 1 from public.stock_items where id = v_item for update;

  update public.stock_purchases
  set voided_at = now(), voided_by = (select auth.uid()),
      void_reason = left(trim(p_reason),500)
  where id = p_purchase_id and voided_at is null;

  -- Restore each active purchase cycle's restock ending from the next
  -- non-voided purchase; do not change explicit run-out dates.
  with ordered as (
    select id, purchased_on,
      lead(purchased_on) over (order by purchased_on, created_at, id) as next_date
    from public.stock_purchases
    where stock_item_id = v_item and voided_at is null
  )
  update public.stock_purchases p
  set ended_reason = case
        when p.run_out_on is null and o.next_date is not null then 'restocked'
        else null end,
      ended_on = case
        when p.run_out_on is null then o.next_date else null end
  from ordered o
  where p.id = o.id;
end;
$$;
revoke all on function public.dhaftar_void_stock_purchase(uuid,text) from public, anon;
grant execute on function public.dhaftar_void_stock_purchase(uuid,text) to authenticated;
