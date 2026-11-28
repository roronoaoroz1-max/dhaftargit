begin;
create table public.amanah_mal_savings_transactions (
 id uuid primary key,user_id uuid not null references auth.users(id),
 transaction_date date not null,transaction_type text not null check(transaction_type in ('deposit','withdrawal')),
 amount numeric(14,2) not null check(amount>0 and amount::text<>'NaN'),note text check(length(note)<=200),
 created_at timestamptz not null default now()
);
alter table public.amanah_mal_savings_transactions enable row level security;
revoke all on public.amanah_mal_savings_transactions from public,anon,authenticated;
grant select,insert on public.amanah_mal_savings_transactions to authenticated;
create policy mal_read on public.amanah_mal_savings_transactions for select to authenticated using(user_id=(select auth.uid()) and (select public.is_admin()));
create policy mal_insert on public.amanah_mal_savings_transactions for insert to authenticated with check(user_id=(select auth.uid()) and (select public.is_admin()));
create function public.dhaftar_mal_balance() returns numeric language sql stable security invoker set search_path='' as $$
 select coalesce(sum(case when transaction_type='deposit' then amount else -amount end),0) from public.amanah_mal_savings_transactions where user_id=auth.uid() and public.is_admin()
$$;
create function public.dhaftar_mal_validate() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if auth.uid() is null or not public.is_admin() or new.user_id<>auth.uid() then raise exception 'Administrator access required' using errcode='42501';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('dhaftar-savings:'||new.user_id::text,0));
 if new.transaction_date>(now() at time zone 'Indian/Maldives')::date then raise exception 'Future date not allowed' using errcode='22023';end if;
 if new.transaction_type='withdrawal' and new.amount>public.dhaftar_mal_balance() then raise exception 'Withdrawal exceeds Mal available savings' using errcode='23514';end if;
 return new;
end $$;
create trigger mal_validate before insert on public.amanah_mal_savings_transactions for each row execute function public.dhaftar_mal_validate();
create function public.dhaftar_record_mal_savings(p_id uuid,p_date date,p_type text,p_amount numeric,p_note text) returns uuid language plpgsql security invoker set search_path='' as $$
declare u uuid:=auth.uid();r public.amanah_mal_savings_transactions%rowtype;
begin
 if u is null or not public.is_admin() then raise exception 'Administrator access required' using errcode='42501';end if;
 if p_id is null or p_date is null or p_type is null or p_type not in ('deposit','withdrawal') or p_amount is null or p_amount::text in ('NaN','Infinity','-Infinity') or p_amount<=0 or p_amount>=1000000000000 or p_amount<>round(p_amount,2) or length(p_note)>200 then raise exception 'Invalid savings details' using errcode='22023';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('dhaftar-savings:'||u::text,0));
 select * into r from public.amanah_mal_savings_transactions where id=p_id and user_id=u;
 if found then
 if r.transaction_date is distinct from p_date or r.transaction_type is distinct from p_type or r.amount is distinct from p_amount or r.note is distinct from nullif(trim(p_note),'') then raise exception 'Request details changed' using errcode='22023';end if;
 return p_id;end if;
 insert into public.amanah_mal_savings_transactions(id,user_id,transaction_date,transaction_type,amount,note) values(p_id,u,p_date,p_type,p_amount,nullif(trim(p_note),''));return p_id;
end $$;
alter table public.amanah_bank_checks_v2 add column mal_savings numeric(18,2) not null default 0;
alter table public.amanah_bank_checks_v2 drop column expected,drop column difference;
alter table public.amanah_bank_checks_v2 add column expected numeric(18,2) generated always as (dad_cash+personal_savings+mal_savings) stored,add column difference numeric(18,2) generated always as (actual-dad_cash-personal_savings-mal_savings) stored;
create or replace function public.dhaftar_bank_check_snapshot_v2() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if auth.uid() is null or not public.is_admin() or new.user_id<>auth.uid() then raise exception 'Administrator access required' using errcode='42501';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('dhaftar-savings:'||new.user_id::text,0));
 new.dad_cash:=public.dhaftar_dad_cash_snapshot_v2();new.personal_savings:=public.dhaftar_savings_balance_v1();new.mal_savings:=public.dhaftar_mal_balance();new.created_at:=now();return new;
end $$;
create or replace function public.dhaftar_savings_dashboard_v2() returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare u uuid:=auth.uid();v_balance numeric;v_allocated numeric;v_month date:=date_trunc('month',now() at time zone 'Indian/Maldives')::date;
begin
 if u is null or not public.is_admin() then raise exception 'Administrator access required' using errcode='42501';end if;
 v_balance:=public.dhaftar_savings_balance_v1();
 select coalesce(sum(amount),0) into v_allocated from public.amanah_goal_allocations_v2 where user_id=u;
 return jsonb_build_object('balance',v_balance,'allocated',v_allocated,'unallocated',v_balance-v_allocated,
 'goals',coalesce((select jsonb_agg(to_jsonb(g) order by g.created_at desc) from (select g.id,g.name,g.target_amount,g.target_date,g.created_at,coalesce(sum(a.amount),0) allocated from public.amanah_savings_goals_v2 g left join public.amanah_goal_allocations_v2 a on a.goal_id=g.id and a.user_id=g.user_id where g.user_id=u group by g.id) g),'[]'::jsonb),
 'monthly',coalesce((select jsonb_agg(to_jsonb(m) order by m.month) from (select gs::date as month,coalesce(sum(t.amount) filter(where t.transaction_type='deposit'),0) deposits,coalesce(sum(t.amount) filter(where t.transaction_type='withdrawal'),0) withdrawals from generate_series(v_month-interval '11 months',v_month,interval '1 month') gs left join public.amanah_personal_savings_transactions t on t.user_id=u and t.transaction_date>=gs and t.transaction_date<gs+interval '1 month' group by gs) m),'[]'::jsonb),
 'allocation_history',coalesce((select jsonb_agg(to_jsonb(a) order by a.created_at desc,a.id desc) from (select a.id,a.amount,a.note,a.created_at,g.name from public.amanah_goal_allocations_v2 a join public.amanah_savings_goals_v2 g on g.id=a.goal_id where a.user_id=u order by a.created_at desc,a.id desc limit 20) a),'[]'::jsonb),
 'checks',coalesce((select jsonb_agg(to_jsonb(r) order by r.created_at desc,r.id desc) from (select id,actual,dad_cash,personal_savings,mal_savings,expected,difference,note,created_at from public.amanah_bank_checks_v2 where user_id=u order by created_at desc,id desc limit 20) r),'[]'::jsonb));
end $$;

revoke all on function public.dhaftar_mal_balance(),public.dhaftar_mal_validate(),public.dhaftar_record_mal_savings(uuid,date,text,numeric,text) from public,anon;
grant execute on function public.dhaftar_mal_balance(),public.dhaftar_mal_validate(),public.dhaftar_record_mal_savings(uuid,date,text,numeric,text) to authenticated;
commit;
