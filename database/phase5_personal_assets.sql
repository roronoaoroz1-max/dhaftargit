-- Additive Phase 5: personal assets, liabilities, dated valuations, maintenance and net-worth snapshots.
begin;
create table public.dhaftar_personal_assets_v5(
 id uuid primary key,user_id uuid not null references auth.users(id),
 name text not null check(length(trim(name)) between 1 and 100),
 kind text not null check(kind in ('physical','investment','external_cash','external_liability')),
 currency text not null check(currency in ('MVR','USD')),
 acquired_on date not null, acquisition_cost numeric(18,2) not null check(acquisition_cost>=0 and acquisition_cost::text<>'NaN'),
 initial_value numeric(18,2) not null check(initial_value>=0 and initial_value::text<>'NaN'),
 note text check(length(note)<=500),created_at timestamptz not null default now(),unique(user_id,id)
);
create table public.dhaftar_asset_events_v5(
 id uuid primary key,user_id uuid not null references auth.users(id),asset_id uuid not null,
 kind text not null check(kind in ('valuation','maintenance','retirement')),
 event_date date not null,amount numeric(18,2) not null check(amount>=0 and amount::text<>'NaN'),
 next_service date,note text check(length(note)<=500),created_at timestamptz not null default now(),
 foreign key(user_id,asset_id) references public.dhaftar_personal_assets_v5(user_id,id),
 check(next_service is null or (kind='maintenance' and next_service>=event_date))
);
create index asset_events_lookup_v5 on public.dhaftar_asset_events_v5(user_id,asset_id,event_date desc,created_at desc,id desc);
create table public.dhaftar_net_worth_snapshots_v5(
 id uuid primary key,user_id uuid not null references auth.users(id),captured_at timestamptz not null default now(),
 totals jsonb not null,note text check(length(note)<=500)
);
alter table public.dhaftar_personal_assets_v5 enable row level security;
alter table public.dhaftar_asset_events_v5 enable row level security;
alter table public.dhaftar_net_worth_snapshots_v5 enable row level security;
revoke all on public.dhaftar_personal_assets_v5,public.dhaftar_asset_events_v5,public.dhaftar_net_worth_snapshots_v5 from public,anon,authenticated;
grant select,insert on public.dhaftar_personal_assets_v5,public.dhaftar_asset_events_v5,public.dhaftar_net_worth_snapshots_v5 to authenticated;
create policy assets_owner_read_v5 on public.dhaftar_personal_assets_v5 for select to authenticated using(user_id=(select auth.uid()) and (select public.is_admin()));
create policy assets_owner_insert_v5 on public.dhaftar_personal_assets_v5 for insert to authenticated with check(user_id=(select auth.uid()) and (select public.is_admin()));
create policy events_owner_read_v5 on public.dhaftar_asset_events_v5 for select to authenticated using(user_id=(select auth.uid()) and (select public.is_admin()));
create policy events_owner_insert_v5 on public.dhaftar_asset_events_v5 for insert to authenticated with check(user_id=(select auth.uid()) and (select public.is_admin()));
create policy snapshots_owner_read_v5 on public.dhaftar_net_worth_snapshots_v5 for select to authenticated using(user_id=(select auth.uid()) and (select public.is_admin()));
create policy snapshots_owner_insert_v5 on public.dhaftar_net_worth_snapshots_v5 for insert to authenticated with check(user_id=(select auth.uid()) and (select public.is_admin()));

create function public.dhaftar_create_asset_v5(p_id uuid,p_name text,p_kind text,p_currency text,p_date date,p_cost numeric,p_value numeric,p_note text) returns uuid
language plpgsql security invoker set search_path='' as $$
declare u uuid:=auth.uid();r public.dhaftar_personal_assets_v5%rowtype;
begin
 if u is null or not public.is_admin() then raise exception 'Administrator access required' using errcode='42501';end if;
 if p_id is null or p_name is null or length(trim(p_name)) not between 1 and 100 or p_kind is null or p_kind not in ('physical','investment','external_cash','external_liability') or p_currency is null or p_currency not in ('MVR','USD') or p_date is null or p_date>(now() at time zone 'Indian/Maldives')::date or p_cost is null or p_value is null or p_cost<0 or p_value<0 or p_cost>=1000000000000 or p_value>=1000000000000 or p_cost<>round(p_cost,2) or p_value<>round(p_value,2) or length(p_note)>500 then raise exception 'Invalid asset details' using errcode='22023';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('dhaftar-asset:'||u::text,0));
 select * into r from public.dhaftar_personal_assets_v5 where id=p_id and user_id=u;
 if found then
  if r.name<>trim(p_name) or r.kind<>p_kind or r.currency<>p_currency or r.acquired_on<>p_date or r.acquisition_cost<>p_cost or r.initial_value<>p_value or r.note is distinct from nullif(trim(p_note),'') then raise exception 'Request details changed' using errcode='22023';end if;return p_id;
 end if;
 insert into public.dhaftar_personal_assets_v5(id,user_id,name,kind,currency,acquired_on,acquisition_cost,initial_value,note) values(p_id,u,trim(p_name),p_kind,p_currency,p_date,p_cost,p_value,nullif(trim(p_note),''));
 return p_id;
end $$;

create function public.dhaftar_validate_asset_event_v5() returns trigger language plpgsql security invoker set search_path='' as $$
declare r public.dhaftar_personal_assets_v5%rowtype;
begin
 if auth.uid() is null or not public.is_admin() or new.user_id<>auth.uid() then raise exception 'Administrator access required' using errcode='42501';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('dhaftar-asset:'||new.user_id::text,0));
 select * into r from public.dhaftar_personal_assets_v5 where id=new.asset_id and user_id=new.user_id;
 if not found then raise exception 'Asset unavailable' using errcode='23503';end if;
 if new.event_date<r.acquired_on or new.event_date>(now() at time zone 'Indian/Maldives')::date or (new.kind='maintenance' and r.kind<>'physical') or (new.kind='retirement' and (new.amount<>0 or length(trim(coalesce(new.note,'')))<3)) then raise exception 'Invalid asset event' using errcode='22023';end if;
 if exists(select 1 from public.dhaftar_asset_events_v5 where asset_id=new.asset_id and user_id=new.user_id and kind='retirement') then raise exception 'Asset already retired' using errcode='23514';end if;
 if new.kind='retirement' and exists(select 1 from public.dhaftar_asset_events_v5 where asset_id=new.asset_id and user_id=new.user_id and event_date>new.event_date) then raise exception 'Retirement precedes existing history' using errcode='23514';end if;
 new.created_at:=now();return new;
end $$;
create trigger validate_asset_event_v5 before insert on public.dhaftar_asset_events_v5 for each row execute function public.dhaftar_validate_asset_event_v5();

create function public.dhaftar_record_asset_event_v5(p_id uuid,p_asset uuid,p_kind text,p_date date,p_amount numeric,p_next date,p_note text) returns uuid
language plpgsql security invoker set search_path='' as $$
declare u uuid:=auth.uid();r public.dhaftar_asset_events_v5%rowtype;
begin
 if u is null or not public.is_admin() then raise exception 'Administrator access required' using errcode='42501';end if;
 if p_id is null or p_asset is null or p_kind is null or p_kind not in ('valuation','maintenance','retirement') or p_date is null or p_amount is null or p_amount<0 or p_amount>=1000000000000 or p_amount<>round(p_amount,2) or length(p_note)>500 then raise exception 'Invalid event details' using errcode='22023';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('dhaftar-asset:'||u::text,0));
 select * into r from public.dhaftar_asset_events_v5 where id=p_id and user_id=u;
 if found then
  if r.asset_id<>p_asset or r.kind<>p_kind or r.event_date<>p_date or r.amount<>p_amount or r.next_service is distinct from p_next or r.note is distinct from nullif(trim(p_note),'') then raise exception 'Request details changed' using errcode='22023';end if;return p_id;
 end if;
 insert into public.dhaftar_asset_events_v5(id,user_id,asset_id,kind,event_date,amount,next_service,note) values(p_id,u,p_asset,p_kind,p_date,p_amount,p_next,nullif(trim(p_note),''));
 return p_id;
end $$;

create function public.dhaftar_asset_register_v5() returns jsonb
language sql stable security invoker set search_path='' as $$
 select coalesce(jsonb_agg(to_jsonb(q) order by q.created_at desc,q.id),'[]'::jsonb) from (
 select a.*,coalesce(v.amount,a.initial_value) current_value,coalesce(v.event_date,a.acquired_on) valuation_date,
 exists(select 1 from public.dhaftar_asset_events_v5 e where e.asset_id=a.id and e.user_id=a.user_id and e.kind='retirement') retired,
 m.next_service,coalesce((select sum(e.amount) from public.dhaftar_asset_events_v5 e where e.asset_id=a.id and e.user_id=a.user_id and e.kind='maintenance'),0) maintenance_total
 from public.dhaftar_personal_assets_v5 a
 left join lateral(select amount,event_date from public.dhaftar_asset_events_v5 e where e.asset_id=a.id and e.user_id=a.user_id and e.kind='valuation' order by event_date desc,created_at desc,id desc limit 1) v on true
 left join lateral(select next_service from public.dhaftar_asset_events_v5 e where e.asset_id=a.id and e.user_id=a.user_id and e.kind='maintenance' order by event_date desc,created_at desc,id desc limit 1) m on true
 where a.user_id=auth.uid() and public.is_admin()
 ) q
$$;

-- Keep currencies separate. Personal savings counted once, including all allocated envelopes.
-- Own Amanah accounts use available balance, not managed balance, to avoid counting lent cash twice.
-- The existing loan position is used as-is; Dad and other owners' accounts excluded.
create function public.dhaftar_net_worth_v5() returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare u uuid:=auth.uid();result jsonb;
begin
 if u is null or not public.is_admin() then raise exception 'Administrator access required' using errcode='42501';end if;
 with reg as(select * from jsonb_to_recordset(public.dhaftar_asset_register_v5()) as r(kind text,currency text,current_value numeric,retired boolean) where not retired),
 c as(select 'MVR'::text currency union all select 'USD'::text),
 components as(
 select c.currency,case when c.currency='MVR' then public.dhaftar_savings_balance_v1() else 0 end savings,
 coalesce((select sum(greatest(a.available_balance,0)) from public.account_balances a join public.people p on p.id=a.owner_id where a.user_id=u and a.currency=c.currency and lower(trim(p.relationship))='self'),0) account_cash,
 coalesce((select sum(greatest(-a.available_balance,0)) from public.account_balances a join public.people p on p.id=a.owner_id where a.user_id=u and a.currency=c.currency and lower(trim(p.relationship))='self'),0) account_overdraft,
 coalesce((select sum(owed_to_me) from public.personal_money_position p where p.user_id=u and p.currency=c.currency),0) receivables,
 coalesce((select sum(i_owe) from public.personal_money_position p where p.user_id=u and p.currency=c.currency),0) loan_liabilities,
 coalesce((select sum(current_value) from reg where currency=c.currency and kind='physical'),0) physical_assets,
 coalesce((select sum(current_value) from reg where currency=c.currency and kind='investment'),0) investments,
 coalesce((select sum(current_value) from reg where currency=c.currency and kind='external_cash'),0) external_cash,
 coalesce((select sum(current_value) from reg where currency=c.currency and kind='external_liability'),0) external_liabilities
 from c), totals as(select *,greatest(savings,0)+account_cash+receivables+physical_assets+investments+external_cash total_assets,greatest(-savings,0)+account_overdraft+loan_liabilities+external_liabilities total_liabilities from components)
 select jsonb_agg(to_jsonb(t)||jsonb_build_object('net_worth',total_assets-total_liabilities) order by currency) into result from totals t;
 return result;
end $$;
create function public.dhaftar_snapshot_values_v5() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if auth.uid() is null or not public.is_admin() or new.user_id<>auth.uid() then raise exception 'Administrator access required' using errcode='42501';end if;
 new.totals:=public.dhaftar_net_worth_v5();new.captured_at:=now();return new;
end $$;
create trigger snapshot_values_v5 before insert on public.dhaftar_net_worth_snapshots_v5 for each row execute function public.dhaftar_snapshot_values_v5();
create function public.dhaftar_save_net_worth_v5(p_id uuid,p_note text) returns uuid
language plpgsql security invoker set search_path='' as $$
declare u uuid:=auth.uid();r public.dhaftar_net_worth_snapshots_v5%rowtype;
begin
 if u is null or not public.is_admin() then raise exception 'Administrator access required' using errcode='42501';end if;
 if p_id is null or length(p_note)>500 then raise exception 'Invalid snapshot details' using errcode='22023';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('dhaftar-asset:'||u::text,0));
 select * into r from public.dhaftar_net_worth_snapshots_v5 where id=p_id and user_id=u;
 if found then if r.note is distinct from nullif(trim(p_note),'') then raise exception 'Request details changed' using errcode='22023';end if;return p_id;end if;
 insert into public.dhaftar_net_worth_snapshots_v5(id,user_id,totals,note) values(p_id,u,'[]'::jsonb,nullif(trim(p_note),''));return p_id;
end $$;
revoke all on function public.dhaftar_create_asset_v5(uuid,text,text,text,date,numeric,numeric,text),public.dhaftar_validate_asset_event_v5(),public.dhaftar_record_asset_event_v5(uuid,uuid,text,date,numeric,date,text),public.dhaftar_asset_register_v5(),public.dhaftar_net_worth_v5(),public.dhaftar_snapshot_values_v5(),public.dhaftar_save_net_worth_v5(uuid,text) from public,anon;
grant execute on function public.dhaftar_create_asset_v5(uuid,text,text,text,date,numeric,numeric,text),public.dhaftar_validate_asset_event_v5(),public.dhaftar_record_asset_event_v5(uuid,uuid,text,date,numeric,date,text),public.dhaftar_asset_register_v5(),public.dhaftar_net_worth_v5(),public.dhaftar_snapshot_values_v5(),public.dhaftar_save_net_worth_v5(uuid,text) to authenticated;
commit;
