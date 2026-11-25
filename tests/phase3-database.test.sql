-- Synthetic fixture only; rollback every test write.
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',true);
do $$
declare today date:=(now() at time zone 'Indian/Maldives')::date; g uuid:=gen_random_uuid(); p uuid:=gen_random_uuid(); d date; n int;
begin
 if public.dhaftar_medication_init_v3(today+5)<>today+5 then raise exception 'Import failed';end if;
 if public.dhaftar_medication_init_v3(today+10)<>today+5 then raise exception 'Existing medication date overwritten';end if;
 d:=public.dhaftar_medication_renew_v3(today+5);
 if d<>(today+interval '3 months')::date or public.dhaftar_medication_renew_v3(today+5)<>d then raise exception 'Renewal retry failed';end if;
 begin perform public.dhaftar_medication_renew_v3(d);raise exception 'Early renewal accepted';exception when check_violation then null;end;
 if public.dhaftar_next_due_v3('2027-01-31',1,31)<>date '2027-02-28' or public.dhaftar_next_due_v3('2027-02-28',1,31)<>date '2027-03-31' or public.dhaftar_next_due_v3('2028-01-31',1,31)<>date '2028-02-29' then raise exception 'Calendar clamp failed';end if;
 perform public.dhaftar_create_schedule_v3(g,'Fixture subscription',20,'USD',1,'2026-01-31',5);
 perform public.dhaftar_create_schedule_v3(g,'Fixture subscription',20,'USD',1,'2026-01-31',5);
 perform public.dhaftar_confirm_recurring_v3(p,g,'2026-01-31',today,21,'paid');
 perform public.dhaftar_confirm_recurring_v3(p,g,'2026-01-31',today,21,'paid');
 if (select count(*) from public.dhaftar_recurring_payments_v3 where schedule_id=g)<>1 or (select next_due from public.dhaftar_recurring_schedules_v3 where id=g)<>date '2026-02-28' then raise exception 'Duplicate payment or next date failed';end if;
 begin perform public.dhaftar_confirm_recurring_v3(gen_random_uuid(),g,'2026-01-31',today,21,'paid');raise exception 'Duplicate occurrence accepted';exception when check_violation then null;end;
 begin perform public.dhaftar_confirm_recurring_v3(p,g,'2026-01-31',today,22,'paid');raise exception 'Changed retry accepted';exception when sqlstate '22023' then null;end;
 update public.dhaftar_recurring_schedules_v3 set active=false where id=g;
 begin perform public.dhaftar_confirm_recurring_v3(gen_random_uuid(),g,'2026-02-28',today,20,null);raise exception 'Paused payment accepted';exception when check_violation then null;end;
 insert into public.dhaftar_bills(bill_type,billing_month,amount,notes) values
 ('__default_amount__wifi','2026-01-01',0,'{"cents":45000}'),
 ('__default_amount__tv','2026-01-01',0,'{"cents":10000}'),
 ('__default_amount__my_phone','2026-01-01',0,'{"cents":25000}'),
 ('WiFi','2026-03-01',777,'existing'),
 ('__payment_status__my_phone','2026-03-01',0,'{"paidCents":10000,"paidOn":"2026-03-01"}');
 n:=public.dhaftar_setup_month_v3('2026-03-01',false);
 if n<>2 or public.dhaftar_setup_month_v3('2026-03-01',false)<>0 then raise exception 'Setup retry failed';end if;
 if not exists(select 1 from public.dhaftar_bills where bill_type='WiFi' and billing_month='2026-03-01' and amount=777 and notes='existing') then raise exception 'Existing bill overwritten';end if;
 if not exists(select 1 from public.dhaftar_bills where bill_type='TV' and billing_month='2026-03-01' and amount=100) then raise exception 'Default cents not applied';end if;
 if not exists(select 1 from public.dhaftar_bills where bill_type='__payment_status__my_phone' and billing_month='2026-03-01' and (notes::jsonb->>'paidCents')::numeric=10000 and (notes::jsonb->>'dueCents')::numeric=25000) then raise exception 'Existing paid status lost';end if;
 if public.dhaftar_setup_month_v3('2026-04-01',true)<>3 then raise exception 'Copy previous failed';end if;
 insert into public.dhaftar_bills(bill_type,billing_month,amount,notes) values('__month_close__','2026-05-01',0,'{"closed":true}');
 begin perform public.dhaftar_setup_month_v3('2026-05-01',false);raise exception 'Closed month modified';exception when check_violation then null;end;
 raise notice 'PASS: medication import and retry, date clamping, personal recurring payment retries and atomic household defaults';
end $$;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000002',true);
do $$ begin
 if exists(select 1 from public.dhaftar_recurring_schedules_v3) or exists(select 1 from public.dhaftar_recurring_payments_v3) or exists(select 1 from public.dhaftar_medication_schedule_v3) then raise exception 'Private data exposed';end if;
 begin perform public.dhaftar_medication_init_v3(null);raise exception 'Unauthorized medication access';exception when insufficient_privilege then null;end;
end $$;
reset role;
rollback;
