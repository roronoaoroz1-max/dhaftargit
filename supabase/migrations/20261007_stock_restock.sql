-- Dhaftar Stock & Restock
-- Dedicated schema for household consumables.
-- Safe to run more than once.

begin;

create extension if not exists pgcrypto;

create table if not exists public.stock_items (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) between 1 and 80),
  category text not null default 'Other',
  unit text not null check (length(trim(unit)) between 1 and 20),
  archived boolean not null default false,
  created_by uuid not null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.stock_purchases (
  id uuid primary key default gen_random_uuid(),
  stock_item_id uuid not null references public.stock_items(id) on delete cascade,
  purchased_on date not null,
  quantity numeric(14,3) not null check (quantity > 0),
  amount numeric(14,2) not null default 0 check (amount >= 0),
  note text null check (note is null or length(note) <= 120),
  run_out_on date null,
  ended_reason text null check (ended_reason is null or ended_reason in ('restocked')),
  ended_on date null,
  created_by uuid not null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint stock_purchase_runout_after_purchase
    check (run_out_on is null or run_out_on >= purchased_on),
  constraint stock_purchase_end_after_purchase
    check (ended_on is null or ended_on >= purchased_on)
);

create index if not exists stock_items_archived_name_idx
  on public.stock_items (archived, lower(name));

create index if not exists stock_purchases_item_date_idx
  on public.stock_purchases (stock_item_id, purchased_on desc);

create index if not exists stock_purchases_date_idx
  on public.stock_purchases (purchased_on desc);

create or replace function public.dhaftar_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists stock_items_set_updated_at on public.stock_items;
create trigger stock_items_set_updated_at
before update on public.stock_items
for each row execute function public.dhaftar_set_updated_at();

drop trigger if exists stock_purchases_set_updated_at on public.stock_purchases;
create trigger stock_purchases_set_updated_at
before update on public.stock_purchases
for each row execute function public.dhaftar_set_updated_at();

alter table public.stock_items enable row level security;
alter table public.stock_purchases enable row level security;

drop policy if exists "Dhaftar admins manage stock items" on public.stock_items;
create policy "Dhaftar admins manage stock items"
on public.stock_items
for all
to authenticated
using (
  exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.role = 'admin'
  )
)
with check (
  exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.role = 'admin'
  )
);

drop policy if exists "Dhaftar admins manage stock purchases" on public.stock_purchases;
create policy "Dhaftar admins manage stock purchases"
on public.stock_purchases
for all
to authenticated
using (
  exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.role = 'admin'
  )
)
with check (
  exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.role = 'admin'
  )
);

grant select, insert, update, delete on public.stock_items to authenticated;
grant select, insert, update, delete on public.stock_purchases to authenticated;

-- -----------------------------------------------------------------
-- One-time import from the temporary Stock JSON records in
-- dhaftar_bills. The legacy rows are intentionally retained until
-- the dedicated tables are verified in production.
-- -----------------------------------------------------------------

insert into public.stock_items (
  id,
  name,
  category,
  unit,
  archived,
  created_by,
  created_at,
  updated_at
)
select
  (b.notes::jsonb ->> 'id')::uuid,
  coalesce(nullif(trim(b.notes::jsonb ->> 'name'), ''), 'Untitled item'),
  coalesce(nullif(trim(b.notes::jsonb ->> 'category'), ''), 'Other'),
  coalesce(nullif(trim(b.notes::jsonb ->> 'unit'), ''), 'unit'),
  coalesce((b.notes::jsonb ->> 'archived')::boolean, false),
  b.created_by,
  coalesce(nullif(b.notes::jsonb ->> 'createdAt', '')::timestamptz, now()),
  coalesce(nullif(b.notes::jsonb ->> 'updatedAt', '')::timestamptz, now())
from public.dhaftar_bills b
where b.bill_type like '__stock_item__%'
  and b.billing_month = date '2026-01-01'
  and (b.notes::jsonb ->> 'id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
on conflict (id) do nothing;

insert into public.stock_purchases (
  id,
  stock_item_id,
  purchased_on,
  quantity,
  amount,
  note,
  run_out_on,
  ended_reason,
  ended_on,
  created_by,
  created_at,
  updated_at
)
select
  (cycle ->> 'id')::uuid,
  (b.notes::jsonb ->> 'id')::uuid,
  (cycle ->> 'purchasedOn')::date,
  (cycle ->> 'qty')::numeric,
  round(coalesce((cycle ->> 'amountCents')::numeric, 0) / 100, 2),
  nullif(cycle ->> 'note', ''),
  nullif(cycle ->> 'runOutOn', '')::date,
  nullif(cycle ->> 'endedReason', ''),
  nullif(cycle ->> 'endedOn', '')::date,
  b.created_by,
  coalesce(b.created_at, now()),
  coalesce(b.updated_at, now())
from public.dhaftar_bills b
cross join lateral jsonb_array_elements(
  coalesce(b.notes::jsonb -> 'cycles', '[]'::jsonb)
) as cycle
where b.bill_type like '__stock_item__%'
  and b.billing_month = date '2026-01-01'
  and (b.notes::jsonb ->> 'id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  and (cycle ->> 'id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  and nullif(cycle ->> 'purchasedOn', '') is not null
  and coalesce((cycle ->> 'qty')::numeric, 0) > 0
on conflict (id) do nothing;

commit;
