-- Dhaftar Spending module: Enjoyments + Medical expenses
-- Applied to Supabase on 2026-10-09.

begin;

create table if not exists public.dhaftar_spending_entries (
  id uuid primary key default gen_random_uuid(),
  spending_type text not null check (spending_type in ('enjoyment','medical')),
  category text not null check (length(trim(category)) between 1 and 60),
  expense_date date not null default current_date,
  amount numeric(14,2) not null check (amount > 0),
  person_name text null check (person_name is null or length(person_name) <= 80),
  provider_name text null check (provider_name is null or length(provider_name) <= 120),
  activity_group text null check (activity_group is null or length(activity_group) <= 120),
  notes text null check (notes is null or length(notes) <= 500),
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists dhaftar_spending_entries_date_idx
  on public.dhaftar_spending_entries (expense_date desc);

create index if not exists dhaftar_spending_entries_type_date_idx
  on public.dhaftar_spending_entries (spending_type, expense_date desc);

drop trigger if exists dhaftar_spending_entries_set_updated_at
  on public.dhaftar_spending_entries;

create trigger dhaftar_spending_entries_set_updated_at
before update on public.dhaftar_spending_entries
for each row
execute function public.dhaftar_set_updated_at();

alter table public.dhaftar_spending_entries enable row level security;

drop policy if exists "Dhaftar admins manage spending entries"
  on public.dhaftar_spending_entries;

create policy "Dhaftar admins manage spending entries"
on public.dhaftar_spending_entries
for all
to authenticated
using (
  exists (
    select 1
    from public.profiles p
    where p.id = (select auth.uid())
      and p.role = 'admin'
  )
)
with check (
  exists (
    select 1
    from public.profiles p
    where p.id = (select auth.uid())
      and p.role = 'admin'
  )
);

grant select, insert, update, delete
on public.dhaftar_spending_entries
to authenticated;

commit;
