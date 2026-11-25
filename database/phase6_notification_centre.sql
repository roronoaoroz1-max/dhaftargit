-- Phase 6: source-derived reminders and private per-occurrence state.
-- Existing source tables and records are not modified.
begin;
create table public.dhaftar_notification_state_v6(
 user_id uuid not null references auth.users(id),notification_key text not null check(length(notification_key) between 1 and 250),
 read_at timestamptz,snoozed_until timestamptz,updated_at timestamptz not null default now(),
 primary key(user_id,notification_key)
);
alter table public.dhaftar_notification_state_v6 enable row level security;
revoke all on public.dhaftar_notification_state_v6 from public,anon,authenticated;
grant select,insert,update on public.dhaftar_notification_state_v6 to authenticated;
create policy notification_owner_read_v6 on public.dhaftar_notification_state_v6 for select to authenticated using(user_id=(select auth.uid()) and (select public.is_admin()));
create policy notification_owner_insert_v6 on public.dhaftar_notification_state_v6 for insert to authenticated with check(user_id=(select auth.uid()) and (select public.is_admin()));
create policy notification_owner_update_v6 on public.dhaftar_notification_state_v6 for update to authenticated using(user_id=(select auth.uid()) and (select public.is_admin())) with check(user_id=(select auth.uid()) and (select public.is_admin()));

-- Legacy bill metadata can be malformed: do not let one marker break the entire centre.
create function public.dhaftar_notice_json_v6(p_text text) returns jsonb language plpgsql immutable security invoker set search_path='' as $$
declare v jsonb;
begin
 v:=p_text::jsonb;return case when jsonb_typeof(v)='object' then v else '{}'::jsonb end;
exception when invalid_text_representation then return '{}'::jsonb;
end $$;
create function public.dhaftar_notice_number_v6(p jsonb,p_key text) returns numeric language plpgsql immutable security invoker set search_path='' as $$
declare n numeric;
begin
 if jsonb_typeof(p->p_key) not in ('number','string') then return null;end if;
 if coalesce(p->>p_key,'') !~ '^[0-9]+([.][0-9]+)?$' then return null;end if;
 n:=(p->>p_key)::numeric;
 return case when n>=0 and n<100000000000000 then n else null end;
exception when numeric_value_out_of_range or invalid_text_representation then return null;
end $$;

-- Mirror the stock page: last six positive restock intervals, then measured runout.
-- Stable ordering includes same-day purchases; no estimated alert without evidence.
create function public.dhaftar_stock_reminders_v6(p_today date)
returns table(notification_key text,title text,due_date date,detail text)
language sql stable security invoker set search_path='' as $$
 with purchases as(
 select p.*,lag(p.purchased_on) over w previous_date,lag(p.quantity) over w previous_qty
 from public.stock_purchases p where p.voided_at is null
 window w as(partition by stock_item_id order by purchased_on,created_at,id)),
 intervals as(select *,row_number() over(partition by stock_item_id order by purchased_on desc,created_at desc,id desc) rn
 from purchases where purchased_on>previous_date),
 rates as(select stock_item_id,avg(previous_qty/(purchased_on-previous_date)) rate from intervals where rn<=6 and previous_qty>0 group by stock_item_id),
 runs as(select stock_item_id,avg(quantity/(run_out_on-purchased_on)) rate from purchases where run_out_on>purchased_on and quantity>0 group by stock_item_id),
 latest as(select distinct on(stock_item_id) * from purchases order by stock_item_id,purchased_on desc,created_at desc,id desc),
 active as(select distinct on(stock_item_id) * from purchases where run_out_on is null and ended_reason is null order by stock_item_id,purchased_on desc,created_at desc,id desc),
 calc as(select i.id,i.name,l.id latest_id,a.id active_id,l.run_out_on,p.manual_low,p.updated_at,coalesce(p.reminder_days,5) remind,
 case when a.id is not null and coalesce(r.rate,s.rate)>0 then a.purchased_on+least(365000,round(a.quantity/coalesce(r.rate,s.rate)))::integer end predicted
 from public.stock_items i left join latest l on l.stock_item_id=i.id left join active a on a.stock_item_id=i.id
 left join rates r on r.stock_item_id=i.id left join runs s on s.stock_item_id=i.id left join public.dhaftar_stock_preferences_v4 p on p.item_id=i.id
 where not i.archived and auth.uid() is not null and public.is_admin())
 select 'stock:'||id::text||':'||case when manual_low then 'manual:'||extract(epoch from updated_at)::text else coalesce(active_id,latest_id)::text end,
 name,case when manual_low then null::date when active_id is null then run_out_on else predicted end,
 case when manual_low then 'Manually marked low' when active_id is null then 'No open stock cycle; restock needed' else 'Estimated restock date from quantity and purchase history' end
 from calc where manual_low or (latest_id is not null and (active_id is null or predicted<=p_today+remind))
$$;

create function public.dhaftar_notifications_v6() returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare u uuid:=auth.uid();today date:=(now() at time zone 'Indian/Maldives')::date;m date:=date_trunc('month',today::timestamp)::date;result jsonb;
begin
 if u is null or not public.is_admin() then raise exception 'Administrator access required' using errcode='42501';end if;
 with kinds as(select * from (values
 ('rent','Rent','rent','rent'),('electricity','Electricity','electricity','Electricity'),('water','Water','water','Water'),
 ('wifi','WiFi','wifi','WiFi'),('malPhone','Mal phone bill','mal_phone',''),('myPhone','My phone bill','my_phone',''),('tv','TV','tv','TV')) k(code,label,marker,bill_type)),
 -- Current and next month plus earlier months with explicit bill/status records.
 months as(select m as month union select (m+interval '1 month')::date union
 select distinct billing_month from public.dhaftar_bills where billing_month<m and (bill_type in ('Water','Electricity','WiFi','TV') or left(bill_type,18)='__payment_status__')),
 bills as(select x.month,k.code,k.label,
 public.dhaftar_notice_number_v6(public.dhaftar_notice_json_v6(cfg.notes),'dueDay') day_num,
 case when k.code='rent' then coalesce((select full_rent_amount*100 from public.dhaftar_rent_rates where effective_from<=x.month order by effective_from desc limit 1),0)
 when k.bill_type='' then public.dhaftar_notice_number_v6(public.dhaftar_notice_json_v6(st.notes),'dueCents')
 else actual.amount*100 end due_cents,
 coalesce(public.dhaftar_notice_number_v6(public.dhaftar_notice_json_v6(st.notes),'paidCents'),0) paid_cents,
 (st.id is not null or actual.id is not null) has_record
 from months x cross join kinds k
 left join public.dhaftar_bills cfg on cfg.bill_type='__due_day__'||k.code and cfg.billing_month=date '2026-01-01'
 left join public.dhaftar_bills st on st.bill_type='__payment_status__'||k.marker and st.billing_month=x.month
 left join public.dhaftar_bills actual on actual.bill_type=k.bill_type and actual.billing_month=x.month
 left join public.dhaftar_bills closed on closed.bill_type='__month_close__' and closed.billing_month=x.month
 where public.dhaftar_notice_json_v6(closed.notes)->'closed' is distinct from 'true'::jsonb),
 dated as(select *,month+least(day_num::integer,extract(day from (month+interval '1 month'-interval '1 day'))::integer)-1 due
 from bills where day_num between 1 and 31 and day_num=trunc(day_num) and (month>=m or has_record)),
 raw as(
 select 'medication:'||next_due::text notification_key,'medication' category,'Medication renewal' title,next_due due_date,'Confirm purchase on the overview to renew' detail,'index.html#medicationUrgent' href
 from public.dhaftar_medication_schedule_v3 where next_due<=today+5
 union all select 'recurring:'||id::text||':'||next_due::text,'recurring',title,next_due,'Confirm the payment to advance the schedule','admin.html#recurringPersonalPanel'
 from public.dhaftar_recurring_schedules_v3 where user_id=u and active and next_due<=today+remind_days
 union all select 'bill:'||code||':'||month::text,'household',label,due,case when due_cents is null then 'Bill amount not entered' else 'Outstanding household bill' end,'admin.html#billStatusSection'
 from dated where due<=today+7 and (due_cents>paid_cents or (due_cents is null and month=m))
 union all select notification_key,'stock',title,due_date,detail,'stock.html' from public.dhaftar_stock_reminders_v6(today)
 union all select 'maintenance:'||a.id::text||':'||a.next_service::text,'maintenance',a.name,a.next_service,'Scheduled asset maintenance','amanah.html#personalAssetsPanel'
 from jsonb_to_recordset(public.dhaftar_asset_register_v5()) as a(id uuid,name text,kind text,retired boolean,next_service date) where not a.retired and a.kind='physical' and a.next_service<=today+7
 ),
 joined as(select r.*,s.read_at,s.snoozed_until,(coalesce(s.snoozed_until>now(),false)) snoozed,
 case when r.due_date is null then 'attention' when r.due_date<today then 'overdue' when r.due_date=today then 'today' else 'upcoming' end urgency
 from raw r left join public.dhaftar_notification_state_v6 s on s.notification_key=r.notification_key and s.user_id=u)
 select jsonb_build_object('today',today,'notifications',coalesce(jsonb_agg(to_jsonb(j) order by j.snoozed,j.due_date nulls first,j.notification_key),'[]'::jsonb),
 'unread',count(*) filter(where read_at is null and not snoozed),'attention',count(*) filter(where not snoozed and urgency in ('attention','overdue','today')))
 into result from joined j;
 return result;
end $$;

create function public.dhaftar_notification_action_v6(p_key text,p_action text,p_days integer default null) returns void
language plpgsql security invoker set search_path='' as $$
declare u uuid:=auth.uid();v_keys jsonb;
begin
 if u is null or not public.is_admin() then raise exception 'Administrator access required' using errcode='42501';end if;
 if p_action is null or p_action not in ('read','unread','snooze','unsnooze','read-all') or (p_action='snooze' and (p_days is null or p_days not in (1,3,7))) then raise exception 'Invalid notification action' using errcode='22023';end if;
 v_keys:=public.dhaftar_notifications_v6()->'notifications';
 if p_action='read-all' then
 insert into public.dhaftar_notification_state_v6(user_id,notification_key,read_at)
 select u,x->>'notification_key',now() from jsonb_array_elements(v_keys) x where not (x->>'snoozed')::boolean
 on conflict(user_id,notification_key) do update set read_at=now(),updated_at=now();return;
 end if;
 if p_key is null or not exists(select 1 from jsonb_array_elements(v_keys) x where x->>'notification_key'=p_key) then raise exception 'Reminder no longer active; refresh' using errcode='22023';end if;
 insert into public.dhaftar_notification_state_v6(user_id,notification_key,read_at,snoozed_until) values(u,p_key,case when p_action='read' then now() end,case when p_action='snooze' then now()+make_interval(days=>p_days) end)
 on conflict(user_id,notification_key) do update set read_at=case when p_action='read' then now() when p_action in ('unread','snooze') then null else dhaftar_notification_state_v6.read_at end,
 snoozed_until=case when p_action='snooze' then now()+make_interval(days=>p_days) when p_action='unsnooze' then null else dhaftar_notification_state_v6.snoozed_until end,updated_at=now();
end $$;
revoke all on function public.dhaftar_notice_json_v6(text),public.dhaftar_notice_number_v6(jsonb,text),public.dhaftar_stock_reminders_v6(date),public.dhaftar_notifications_v6(),public.dhaftar_notification_action_v6(text,text,integer) from public,anon;
grant execute on function public.dhaftar_notice_json_v6(text),public.dhaftar_notice_number_v6(jsonb,text),public.dhaftar_stock_reminders_v6(date),public.dhaftar_notifications_v6(),public.dhaftar_notification_action_v6(text,text,integer) to authenticated;
commit;
