-- Harden Stock & Restock RLS and trigger helper.

begin;

alter function public.dhaftar_set_updated_at()
  set search_path = pg_catalog, public;

drop policy if exists "Dhaftar admins manage stock items"
  on public.stock_items;

create policy "Dhaftar admins manage stock items"
on public.stock_items
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

drop policy if exists "Dhaftar admins manage stock purchases"
  on public.stock_purchases;

create policy "Dhaftar admins manage stock purchases"
on public.stock_purchases
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

commit;
