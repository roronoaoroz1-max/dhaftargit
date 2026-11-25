begin;
-- The production rent-rate table was not needed by earlier phase fixtures.
create table public.dhaftar_rent_rates(
 id uuid primary key default gen_random_uuid(),effective_from date not null unique check(extract(day from effective_from)=1),
 fixed_rent_share numeric(14,2) not null check(fixed_rent_share>=0),note text not null default '',
 created_by uuid default auth.uid() references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),full_rent_amount numeric(14,2) not null default 0 check(full_rent_amount>=0)
);
alter table public.dhaftar_rent_rates enable row level security;
grant select,insert on public.dhaftar_rent_rates to authenticated;
create policy fixture_rent_admin on public.dhaftar_rent_rates for all to authenticated using(public.is_admin()) with check(public.is_admin());
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',true);
do $$
declare d date:=(now() at time zone 'Indian/Maldives')::date;m date:=date_trunc('month',d)::date;
s uuid:=gen_random_uuid();item uuid:=gen_random_uuid();a uuid:=gen_random_uuid();k text;f jsonb;
begin
 perform public.dhaftar_medication_init_v3(d+2);
 perform public.dhaftar_create_schedule_v3(s,'Fixture subscription',20,'USD',1,d,5);
 insert into public.stock_items(id,name,unit) values(item,'Fixture stock','pcs');
 perform public.dhaftar_save_stock_preferences_v4(item,'Shop',5,true);
 perform public.dhaftar_create_asset_v5(a,'Fixture bike','physical','MVR',d-10,100,100,null);
 perform public.dhaftar_record_asset_event_v5(gen_random_uuid(),a,'maintenance',d,5,d+3,'Service');
 insert into public.dhaftar_bills(bill_type,billing_month,amount,notes) values('__due_day__wifi','2026-01-01',0,jsonb_build_object('dueDay',extract(day from d))::text),('WiFi',m,100,null);
 insert into public.dhaftar_rent_rates(effective_from,fixed_rent_share,full_rent_amount) values(m,500,1500);
 insert into public.dhaftar_bills(bill_type,billing_month,amount,notes) values('__due_day__rent','2026-01-01',0,jsonb_build_object('dueDay',extract(day from d))::text);
 f:=public.dhaftar_notifications_v6();
 if not exists(select 1 from jsonb_array_elements(f->'notifications') x where x->>'notification_key'='bill:rent:'||m::text) then raise exception 'Rent reminder missing';end if;
 if (select count(distinct x->>'category') from jsonb_array_elements(f->'notifications') x)<>5 then raise exception 'Missing reminder source: %',f;end if;
 select x->>'notification_key' into k from jsonb_array_elements(f->'notifications') x where x->>'category'='recurring';
 perform public.dhaftar_notification_action_v6(k,'read',null);
 if not exists(select 1 from jsonb_array_elements(public.dhaftar_notifications_v6()->'notifications') x where x->>'notification_key'=k and x->>'read_at' is not null) then raise exception 'Read failed';end if;
 perform public.dhaftar_notification_action_v6(k,'unread',null);
 perform public.dhaftar_notification_action_v6(k,'snooze',3);
 if not exists(select 1 from jsonb_array_elements(public.dhaftar_notifications_v6()->'notifications') x where x->>'notification_key'=k and (x->>'snoozed')::boolean) then raise exception 'Snooze failed';end if;
 perform public.dhaftar_notification_action_v6(k,'unsnooze',null);
 perform public.dhaftar_notification_action_v6(k,'snooze',1);
 update public.dhaftar_notification_state_v6 set snoozed_until=now()-interval '1 second' where notification_key=k;
 if not exists(select 1 from jsonb_array_elements(public.dhaftar_notifications_v6()->'notifications') x where x->>'notification_key'=k and not (x->>'snoozed')::boolean and x->>'read_at' is null) then raise exception 'Snooze expiry failed';end if;
 perform public.dhaftar_notification_action_v6(null,'read-all',null);
 if (public.dhaftar_notifications_v6()->>'unread')::int<>0 then raise exception 'Mark all failed';end if;
 perform public.dhaftar_confirm_recurring_v3(gen_random_uuid(),s,d,d,20,null);
 perform public.dhaftar_medication_renew_v3(d+2);
 perform public.dhaftar_record_stock_purchase_v1(gen_random_uuid(),item,d,2,10,null);
 perform public.dhaftar_record_asset_event_v5(gen_random_uuid(),a,'retirement',d,0,null,'Sold');
 insert into public.dhaftar_bills(bill_type,billing_month,amount,notes) values('__payment_status__wifi',m,0,'{"paidCents":10000}');
 insert into public.dhaftar_bills(bill_type,billing_month,amount,notes) values('__payment_status__rent',m,0,'{"paidCents":150000}');
 if exists(select 1 from jsonb_array_elements(public.dhaftar_notifications_v6()->'notifications') x where x->>'notification_key'='bill:rent:'||m::text) then raise exception 'Paid rent reminder remains';end if;
 if exists(select 1 from jsonb_array_elements(public.dhaftar_notifications_v6()->'notifications') x where x->>'category' in ('medication','recurring','stock','maintenance') or x->>'notification_key'='bill:wifi:'||m::text) then raise exception 'Completed source remains active';end if;
 raise notice 'PASS: five notification sources, read/unread, snooze and expiry, mark all and automatic source resolution';
end $$;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000002',true);
do $$ begin
 if exists(select 1 from public.dhaftar_notification_state_v6) then raise exception 'Private reminder state exposed';end if;
 begin perform public.dhaftar_notifications_v6();raise exception 'Unauthorized feed';exception when insufficient_privilege then null;end;
end $$;
rollback;
