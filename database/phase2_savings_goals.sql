-- Phase 2: personal goal envelopes, monthly savings analytics and bank reconciliation.
-- No existing savings, Dad's balances or loan records are rewritten.
begin;
create table public.amanah_savings_goals_v2 (
 id uuid primary key, user_id uuid not null references auth.users(id),
 name text not null check(length(trim(name)) between 1 and 100),
 target_amount numeric(14,2) not null check(target_amount>0 and target_amount::text<>'NaN'),
 target_date date, created_at timestamptz not null default now(),
 unique(user_id,id)
);
create table public.amanah_goal_allocations_v2 (
 id uuid primary key,user_id uuid not null references auth.users(id),goal_id uuid not null,
 amount numeric(14,2) not null check(amount<>0 and amount::text<>'NaN'),
 note text check(length(note)<=200),created_at timestamptz not null default now(),
 foreign key(user_id,goal_id) references public.amanah_savings_goals_v2(user_id,id)
);
create index amanah_goal_allocations_owner_v2 on public.amanah_goal_allocations_v2(user_id,goal_id);
create table public.amanah_bank_checks_v2 (
 id uuid primary key,user_id uuid not null references auth.users(id),
 actual numeric(14,2) not null check(actual>=0 and actual::text<>'NaN'),
 dad_cash numeric(18,2) not null,personal_savings numeric(18,2) not null,
 expected numeric(18,2) generated always as (dad_cash+personal_savings) stored,
 difference numeric(18,2) generated always as (actual-dad_cash-personal_savings) stored,
 note text check(length(note)<=200),created_at timestamptz not null default now()
);
alter table public.amanah_savings_goals_v2 enable row level security;
alter table public.amanah_goal_allocations_v2 enable row level security;
alter table public.amanah_bank_checks_v2 enable row level security;
revoke all on public.amanah_savings_goals_v2,public.amanah_goal_allocations_v2,public.amanah_bank_checks_v2 from public,anon,authenticated;
grant select,insert on public.amanah_savings_goals_v2,public.amanah_goal_allocations_v2,public.amanah_bank_checks_v2 to authenticated;
create policy goals_owner_read on public.amanah_savings_goals_v2 for select to authenticated using(user_id=(select auth.uid()) and (select public.is_admin()));
create policy goals_owner_insert on public.amanah_savings_goals_v2 for insert to authenticated with check(user_id=(select auth.uid()) and (select public.is_admin()));
create policy allocations_owner_read on public.amanah_goal_allocations_v2 for select to authenticated using(user_id=(select auth.uid()) and (select public.is_admin()));
create policy allocations_owner_insert on public.amanah_goal_allocations_v2 for insert to authenticated with check(user_id=(select auth.uid()) and (select public.is_admin()));
create policy checks_owner_read on public.amanah_bank_checks_v2 for select to authenticated using(user_id=(select auth.uid()) and (select public.is_admin()));
create policy checks_owner_insert on public.amanah_bank_checks_v2 for insert to authenticated with check(user_id=(select auth.uid()) and (select public.is_admin()));

-- The same lock used by Phase 1 withdrawals serializes goal allocations.
create function public.dhaftar_validate_goal_allocation_v2() returns trigger language plpgsql security invoker set search_path='' as $$
declare v_balance numeric;v_reserved numeric;v_goal numeric;v_target numeric;
begin
 if auth.uid() is null or not public.is_admin() or new.user_id<>auth.uid() then raise exception 'Administrator access required' using errcode='42501';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('dhaftar-savings:'||new.user_id::text,0));
 select target_amount into v_target from public.amanah_savings_goals_v2 where user_id=new.user_id and id=new.goal_id;
 if not found then raise exception 'Goal not found' using errcode='23503';end if;
 select coalesce(sum(amount),0),coalesce(sum(amount) filter(where goal_id=new.goal_id),0) into v_reserved,v_goal from public.amanah_goal_allocations_v2 where user_id=new.user_id;
 v_balance:=public.dhaftar_savings_balance_v1();
 if new.amount::text='NaN' or new.amount=0 or v_goal+new.amount<0 or (new.amount>0 and (v_reserved+new.amount>v_balance or v_goal+new.amount>v_target)) then
  raise exception 'Allocation exceeds unallocated savings or goal target, or release exceeds allocated amount' using errcode='23514';
 end if;
 return new;
end $$;
create trigger validate_goal_allocation_v2 before insert on public.amanah_goal_allocations_v2 for each row execute function public.dhaftar_validate_goal_allocation_v2();

create or replace function public.dhaftar_validate_savings_insert_v1() returns trigger language plpgsql security invoker set search_path='' as $$
declare v_balance numeric;v_reserved numeric;
begin
 if new.amount::text in ('NaN','Infinity','-Infinity') then raise exception 'Invalid savings amount' using errcode='22023';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('dhaftar-savings:'||new.user_id::text,0));
 if new.transaction_type='withdrawal' then
  select coalesce(sum(case when transaction_type='deposit' then amount else -amount end),0) into v_balance from public.amanah_personal_savings_transactions where user_id=new.user_id;
  select coalesce(sum(amount),0) into v_reserved from public.amanah_goal_allocations_v2 where user_id=new.user_id;
  if new.amount>v_balance-v_reserved then raise exception 'Withdrawal exceeds unallocated savings. Release goal funds first.' using errcode='23514';end if;
 end if;
 return new;
end $$;

create function public.dhaftar_create_goal_v2(p_id uuid,p_name text,p_target numeric,p_date date)
returns uuid language plpgsql security invoker set search_path='' as $$
declare u uuid:=auth.uid();g public.amanah_savings_goals_v2%rowtype;
begin
 if u is null or not public.is_admin() then raise exception 'Administrator access required' using errcode='42501';end if;
 if p_id is null or p_name is null or length(trim(p_name)) not between 1 and 100 or p_target is null or p_target<=0 or p_target>=1000000000000 or p_target<>round(p_target,2) then raise exception 'Invalid goal details' using errcode='22023';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('dhaftar-savings:'||u::text,0));
 select * into g from public.amanah_savings_goals_v2 where id=p_id and user_id=u;
 if found then
  if g.name is distinct from trim(p_name) or g.target_amount is distinct from p_target or g.target_date is distinct from p_date then raise exception 'Request details changed' using errcode='22023';end if;
  return p_id;
 end if;
 insert into public.amanah_savings_goals_v2(id,user_id,name,target_amount,target_date) values(p_id,u,trim(p_name),p_target,p_date);return p_id;
end $$;

create function public.dhaftar_allocate_goal_v2(p_id uuid,p_goal uuid,p_amount numeric,p_note text)
returns uuid language plpgsql security invoker set search_path='' as $$
declare u uuid:=auth.uid();a public.amanah_goal_allocations_v2%rowtype;
begin
 if u is null or not public.is_admin() then raise exception 'Administrator access required' using errcode='42501';end if;
 if p_id is null or p_goal is null or p_amount is null or p_amount=0 or abs(p_amount)>=1000000000000 or p_amount<>round(p_amount,2) or length(p_note)>200 then raise exception 'Invalid allocation details' using errcode='22023';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('dhaftar-savings:'||u::text,0));
 select * into a from public.amanah_goal_allocations_v2 where id=p_id and user_id=u;
 if found then
  if a.goal_id is distinct from p_goal or a.amount is distinct from p_amount or a.note is distinct from nullif(trim(p_note),'') then raise exception 'Request details changed' using errcode='22023';end if;
  return p_id;
 end if;
 insert into public.amanah_goal_allocations_v2(id,user_id,goal_id,amount,note) values(p_id,u,p_goal,p_amount,nullif(trim(p_note),''));return p_id;
end $$;

-- Match the existing Amanah Dad-custody filter exactly; no loan principal is included.
create function public.dhaftar_dad_cash_snapshot_v2() returns numeric language sql stable security invoker set search_path='' as $$
 select coalesce(sum(a.available_balance),0) from public.account_balances a
 where public.is_admin() and auth.uid() is not null and lower(trim(a.currency))='mvr'
 and (lower(trim(a.owner_name))='dad' or exists(select 1 from public.people p where p.id=a.owner_id and (lower(trim(p.name))='dad' or lower(trim(p.relationship))='father')))
 and (lower(trim(a.holder_name)) in ('me','inaad') or exists(select 1 from public.people p where p.id=a.holder_id and (lower(trim(p.name)) in ('me','inaad') or lower(trim(p.relationship))='self')))
$$;
-- Enforce server snapshots even for direct inserts.
create function public.dhaftar_bank_check_snapshot_v2() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if auth.uid() is null or not public.is_admin() or new.user_id<>auth.uid() then raise exception 'Administrator access required' using errcode='42501';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('dhaftar-savings:'||new.user_id::text,0));
 new.dad_cash:=public.dhaftar_dad_cash_snapshot_v2();new.personal_savings:=public.dhaftar_savings_balance_v1();
 new.created_at:=now();return new;
end $$;
create trigger bank_check_snapshot_v2 before insert on public.amanah_bank_checks_v2 for each row execute function public.dhaftar_bank_check_snapshot_v2();
create function public.dhaftar_save_bank_check_v2(p_id uuid,p_actual numeric,p_note text) returns uuid language plpgsql security invoker set search_path='' as $$
declare u uuid:=auth.uid();r public.amanah_bank_checks_v2%rowtype;
begin
 if u is null or not public.is_admin() then raise exception 'Administrator access required' using errcode='42501';end if;
 if p_id is null or p_actual is null or p_actual<0 or p_actual>=1000000000000 or p_actual<>round(p_actual,2) or length(p_note)>200 then raise exception 'Invalid bank balance' using errcode='22023';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('dhaftar-savings:'||u::text,0));
 select * into r from public.amanah_bank_checks_v2 where id=p_id and user_id=u;
 if found then
  if r.actual is distinct from p_actual or r.note is distinct from nullif(trim(p_note),'') then raise exception 'Request details changed' using errcode='22023';end if;return p_id;
 end if;
 insert into public.amanah_bank_checks_v2(id,user_id,actual,dad_cash,personal_savings,note) values(p_id,u,p_actual,0,0,nullif(trim(p_note),''));return p_id;
end $$;

create function public.dhaftar_savings_dashboard_v2() returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare u uuid:=auth.uid();v_balance numeric;v_allocated numeric;v_month date:=date_trunc('month',now() at time zone 'Indian/Maldives')::date;
begin
 if u is null or not public.is_admin() then raise exception 'Administrator access required' using errcode='42501';end if;
 v_balance:=public.dhaftar_savings_balance_v1();
 select coalesce(sum(amount),0) into v_allocated from public.amanah_goal_allocations_v2 where user_id=u;
 return jsonb_build_object('balance',v_balance,'allocated',v_allocated,'unallocated',v_balance-v_allocated,
 'goals',coalesce((select jsonb_agg(to_jsonb(g) order by g.created_at desc) from (select g.id,g.name,g.target_amount,g.target_date,g.created_at,coalesce(sum(a.amount),0) allocated from public.amanah_savings_goals_v2 g left join public.amanah_goal_allocations_v2 a on a.goal_id=g.id and a.user_id=g.user_id where g.user_id=u group by g.id) g),'[]'::jsonb),
 'monthly',coalesce((select jsonb_agg(to_jsonb(m) order by m.month) from (select gs::date month,coalesce(sum(t.amount) filter(where t.transaction_type='deposit'),0) deposits,coalesce(sum(t.amount) filter(where t.transaction_type='withdrawal'),0) withdrawals from generate_series(v_month-interval '11 months',v_month,interval '1 month') gs left join public.amanah_personal_savings_transactions t on t.user_id=u and t.transaction_date>=gs and t.transaction_date<gs+interval '1 month' group by gs) m),'[]'::jsonb),
 'allocation_history',coalesce((select jsonb_agg(to_jsonb(a) order by a.created_at desc,a.id desc) from (select a.id,a.amount,a.note,a.created_at,g.name from public.amanah_goal_allocations_v2 a join public.amanah_savings_goals_v2 g on g.id=a.goal_id where a.user_id=u order by a.created_at desc,a.id desc limit 20) a),'[]'::jsonb),
 'checks',coalesce((select jsonb_agg(to_jsonb(r) order by r.created_at desc,r.id desc) from (select id,actual,dad_cash,personal_savings,expected,difference,note,created_at from public.amanah_bank_checks_v2 where user_id=u order by created_at desc,id desc limit 20) r),'[]'::jsonb));
end $$;
revoke all on function public.dhaftar_validate_goal_allocation_v2(),public.dhaftar_bank_check_snapshot_v2(),public.dhaftar_dad_cash_snapshot_v2(),public.dhaftar_create_goal_v2(uuid,text,numeric,date),public.dhaftar_allocate_goal_v2(uuid,uuid,numeric,text),public.dhaftar_save_bank_check_v2(uuid,numeric,text),public.dhaftar_savings_dashboard_v2() from public,anon;
grant execute on function public.dhaftar_validate_goal_allocation_v2(),public.dhaftar_bank_check_snapshot_v2(),public.dhaftar_dad_cash_snapshot_v2(),public.dhaftar_create_goal_v2(uuid,text,numeric,date),public.dhaftar_allocate_goal_v2(uuid,uuid,numeric,text),public.dhaftar_save_bank_check_v2(uuid,numeric,text),public.dhaftar_savings_dashboard_v2() to authenticated;
commit;
