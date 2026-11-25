-- Phase 3: shared medication renewal date, private recurring payments and safe month setup.
begin;
create table public.dhaftar_medication_schedule_v3(
 id integer primary key check(id=1), next_due date not null, updated_at timestamptz not null default now()
);
alter table public.dhaftar_medication_schedule_v3 enable row level security;
revoke all on public.dhaftar_medication_schedule_v3 from public,anon,authenticated;
grant select,insert,update on public.dhaftar_medication_schedule_v3 to authenticated;
create policy medication_admin on public.dhaftar_medication_schedule_v3 for all to authenticated using((select public.is_admin())) with check((select public.is_admin()));
-- No seed row: first authenticated device can import its existing local date.
create function public.dhaftar_medication_init_v3(p_local_due date) returns date
language plpgsql security invoker set search_path='' as $$
declare d date;
begin
 if auth.uid() is null or not public.is_admin() then raise exception 'Administrator access required' using errcode='42501';end if;
 insert into public.dhaftar_medication_schedule_v3(id,next_due)
 values(1,coalesce(p_local_due,date '2027-02-17')) on conflict(id) do nothing;
 select next_due into d from public.dhaftar_medication_schedule_v3 where id=1;return d;
end $$;
create function public.dhaftar_medication_renew_v3(p_expected_due date) returns date
language plpgsql security invoker set search_path='' as $$
declare d date;today date:=(now() at time zone 'Indian/Maldives')::date;
begin
 if auth.uid() is null or not public.is_admin() then raise exception 'Administrator access required' using errcode='42501';end if;
 select next_due into d from public.dhaftar_medication_schedule_v3 where id=1 for update;
 if not found or p_expected_due is null then raise exception 'Refresh the medication schedule first' using errcode='22023';end if;
 if d<>p_expected_due then return d;end if;
 if d>today+5 then raise exception 'Renewal is not within the five-day window' using errcode='23514';end if;
 d:=(today+interval '3 months')::date;
 update public.dhaftar_medication_schedule_v3 set next_due=d,updated_at=now() where id=1;
 return d;
end $$;

create table public.dhaftar_recurring_schedules_v3(
 id uuid primary key,user_id uuid not null references auth.users(id),
 title text not null check(length(trim(title)) between 1 and 100),
 amount numeric(14,2) not null check(amount>=0 and amount::text<>'NaN'),
 currency text not null check(currency in ('MVR','USD')),
 interval_months integer not null check(interval_months in (1,2,3,6,12)),
 first_due date not null,next_due date not null,
 anchor_day integer not null check(anchor_day between 1 and 31),
 remind_days integer not null check(remind_days between 0 and 30),
 active boolean not null default true,created_at timestamptz not null default now(),
 unique(user_id,id)
);
create table public.dhaftar_recurring_payments_v3(
 id uuid primary key,user_id uuid not null references auth.users(id),schedule_id uuid not null,
 due_date date not null,paid_on date not null,amount numeric(14,2) not null check(amount>=0 and amount::text<>'NaN'),
 currency text not null check(currency in ('MVR','USD')),note text check(length(note)<=200),
 created_at timestamptz not null default now(),
 foreign key(user_id,schedule_id) references public.dhaftar_recurring_schedules_v3(user_id,id),
 unique(schedule_id,due_date)
);
alter table public.dhaftar_recurring_schedules_v3 enable row level security;
alter table public.dhaftar_recurring_payments_v3 enable row level security;
revoke all on public.dhaftar_recurring_schedules_v3,public.dhaftar_recurring_payments_v3 from public,anon,authenticated;
grant select,insert,update on public.dhaftar_recurring_schedules_v3 to authenticated;
grant select,insert on public.dhaftar_recurring_payments_v3 to authenticated;
create policy schedule_owner on public.dhaftar_recurring_schedules_v3 for all to authenticated using(user_id=(select auth.uid()) and (select public.is_admin())) with check(user_id=(select auth.uid()) and (select public.is_admin()));
create policy payment_owner_read on public.dhaftar_recurring_payments_v3 for select to authenticated using(user_id=(select auth.uid()) and (select public.is_admin()));
create policy payment_owner_insert on public.dhaftar_recurring_payments_v3 for insert to authenticated with check(user_id=(select auth.uid()) and (select public.is_admin()));

create function public.dhaftar_next_due_v3(p_due date,p_months integer,p_day integer) returns date
language sql immutable security invoker set search_path='' as $$
 select (m + (least(p_day,extract(day from (m+interval '1 month-1 day'))::integer)-1))::date
 from (select (date_trunc('month',p_due::timestamp)+make_interval(months=>p_months))::date m) s
$$;
create function public.dhaftar_create_schedule_v3(p_id uuid,p_title text,p_amount numeric,p_currency text,p_months integer,p_due date,p_remind integer) returns uuid
language plpgsql security invoker set search_path='' as $$
declare u uuid:=auth.uid();r public.dhaftar_recurring_schedules_v3%rowtype;
begin
 if u is null or not public.is_admin() then raise exception 'Administrator access required' using errcode='42501';end if;
 if p_id is null or p_title is null or length(trim(p_title)) not between 1 and 100 or p_amount is null or p_amount<0 or p_amount>=1000000000000 or p_amount<>round(p_amount,2) or p_currency is null or p_currency not in ('MVR','USD') or p_months is null or p_months not in (1,2,3,6,12) or p_due is null or p_remind is null or p_remind not between 0 and 30 then raise exception 'Invalid recurring schedule' using errcode='22023';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('dhaftar-recurring:'||p_id::text,0));
 select * into r from public.dhaftar_recurring_schedules_v3 where id=p_id and user_id=u;
 if found then
  if r.title<>trim(p_title) or r.amount<>p_amount or r.currency<>p_currency or r.interval_months<>p_months or r.first_due<>p_due or r.remind_days<>p_remind then raise exception 'Request details changed' using errcode='22023';end if;return p_id;
 end if;
 insert into public.dhaftar_recurring_schedules_v3(id,user_id,title,amount,currency,interval_months,first_due,next_due,anchor_day,remind_days) values(p_id,u,trim(p_title),p_amount,p_currency,p_months,p_due,p_due,extract(day from p_due)::integer,p_remind);return p_id;
end $$;
create function public.dhaftar_confirm_recurring_v3(p_id uuid,p_schedule uuid,p_due date,p_paid date,p_amount numeric,p_note text) returns uuid
language plpgsql security invoker set search_path='' as $$
declare u uuid:=auth.uid();r public.dhaftar_recurring_schedules_v3%rowtype;a public.dhaftar_recurring_payments_v3%rowtype;today date:=(now() at time zone 'Indian/Maldives')::date;
begin
 if u is null or not public.is_admin() then raise exception 'Administrator access required' using errcode='42501';end if;
 if p_id is null or p_schedule is null or p_due is null or p_paid is null or p_paid>today or p_amount is null or p_amount<0 or p_amount>=1000000000000 or p_amount<>round(p_amount,2) or length(p_note)>200 then raise exception 'Invalid payment details' using errcode='22023';end if;
 select * into r from public.dhaftar_recurring_schedules_v3 where id=p_schedule and user_id=u for update;
 if not found then raise exception 'Schedule not found' using errcode='23503';end if;
 select * into a from public.dhaftar_recurring_payments_v3 where id=p_id and user_id=u;
 if found then
  if a.schedule_id<>p_schedule or a.due_date<>p_due or a.paid_on<>p_paid or a.amount<>p_amount or a.note is distinct from nullif(trim(p_note),'') then raise exception 'Request details changed' using errcode='22023';end if;return p_id;
 end if;
 if not r.active or r.next_due<>p_due then raise exception 'Schedule changed; refresh before recording payment' using errcode='23514';end if;
 insert into public.dhaftar_recurring_payments_v3(id,user_id,schedule_id,due_date,paid_on,amount,currency,note) values(p_id,u,p_schedule,p_due,p_paid,p_amount,r.currency,nullif(trim(p_note),''));
 update public.dhaftar_recurring_schedules_v3 set next_due=public.dhaftar_next_due_v3(r.next_due,r.interval_months,r.anchor_day) where id=p_schedule;
 return p_id;
end $$;

-- Existing household defaults and due dates are authoritative. Atomic setup fills only missing values.
create function public.dhaftar_setup_month_v3(p_month date,p_copy boolean) returns integer
language plpgsql security invoker set search_path='' as $$
declare u uuid:=auth.uid();r record;v_previous date;v_count integer:=0;n integer;v_amount numeric;v_meta jsonb;v_old jsonb;v_source text;v_target text;
begin
 if u is null or not public.is_admin() then raise exception 'Administrator access required' using errcode='42501';end if;
 if p_month is null or extract(day from p_month)<>1 or p_copy is null then raise exception 'Invalid billing month' using errcode='22023';end if;
 -- Serialize setup with other bill writes. Lock prevents overwriting another session's changes.
 lock table public.dhaftar_bills in share row exclusive mode;
 if exists(select 1 from public.dhaftar_bills where billing_month=p_month and bill_type='__month_close__' and notes::jsonb->'closed'='true'::jsonb) then raise exception 'Month is closed' using errcode='23514';end if;
 v_previous:=(p_month-interval '1 month')::date;
 for r in select * from (values ('WiFi','__default_amount__wifi'),('TV','__default_amount__tv'),('Water',null),('Electricity',null)) x(target,source) loop
  v_source:=case when p_copy then r.target else r.source end;
  if v_source is null then continue;end if;
  select amount into v_amount from public.dhaftar_bills where bill_type=v_source and billing_month=case when p_copy then v_previous else date '2026-01-01' end;
  if not found then continue;end if;
  insert into public.dhaftar_bills(bill_type,billing_month,amount,notes,created_by,updated_by) values(r.target,p_month,v_amount,case when p_copy then 'Copied from previous month' else 'Smart Month Setup default' end,u,u) on conflict(bill_type,billing_month) do nothing;
  get diagnostics n=row_count;v_count:=v_count+n;
 end loop;
 for r in select * from (values ('__payment_status__mal_phone','__default_amount__mal_phone'),('__payment_status__my_phone','__default_amount__my_phone')) x(target,source) loop
  if p_copy then
   select notes::jsonb into v_meta from public.dhaftar_bills where bill_type=r.target and billing_month=v_previous;
   if not found or jsonb_typeof(v_meta->'dueCents') is distinct from 'number' then continue;end if;
   v_amount:=(v_meta->>'dueCents')::numeric/100;
  else
   select amount into v_amount from public.dhaftar_bills where bill_type=r.source and billing_month=date '2026-01-01';
   if not found then continue;end if;
  end if;
  if v_amount<0 or v_amount<>round(v_amount,2) then continue;end if;
  select coalesce(notes::jsonb,'{}'::jsonb) into v_old from public.dhaftar_bills where bill_type=r.target and billing_month=p_month for update;
  if found then
   if jsonb_typeof(v_old->'dueCents')='number' then continue;end if;
   update public.dhaftar_bills set notes=(v_old||jsonb_build_object('dueCents',v_amount*100))::text,updated_by=u where bill_type=r.target and billing_month=p_month;
  else
   insert into public.dhaftar_bills(bill_type,billing_month,amount,notes,created_by,updated_by) values(r.target,p_month,0,jsonb_build_object('dueCents',v_amount*100,'paidCents',0,'paidOn','')::text,u,u);
  end if;
  v_count:=v_count+1;
 end loop;
 return v_count;
end $$;
revoke all on function public.dhaftar_medication_init_v3(date),public.dhaftar_medication_renew_v3(date),public.dhaftar_next_due_v3(date,integer,integer),public.dhaftar_create_schedule_v3(uuid,text,numeric,text,integer,date,integer),public.dhaftar_confirm_recurring_v3(uuid,uuid,date,date,numeric,text),public.dhaftar_setup_month_v3(date,boolean) from public,anon;
grant execute on function public.dhaftar_medication_init_v3(date),public.dhaftar_medication_renew_v3(date),public.dhaftar_next_due_v3(date,integer,integer),public.dhaftar_create_schedule_v3(uuid,text,numeric,text,integer,date,integer),public.dhaftar_confirm_recurring_v3(uuid,uuid,date,date,numeric,text),public.dhaftar_setup_month_v3(date,boolean) to authenticated;
commit;
