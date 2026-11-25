-- Synthetic records only; all writes roll back.
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',true);
do $$
declare
 g uuid:=gen_random_uuid(); g2 uuid:=gen_random_uuid(); a uuid:=gen_random_uuid(); b uuid:=gen_random_uuid(); c uuid:=gen_random_uuid();
 dad uuid:=gen_random_uuid(); me uuid:=gen_random_uuid(); borrower uuid:=gen_random_uuid(); acc uuid:=gen_random_uuid();
 d jsonb; today date:=(now() at time zone 'Indian/Maldives')::date;
begin
 insert into public.people(id,name,relationship) values(dad,'Fixture father','father'),(me,'Fixture me','self'),(borrower,'Fixture borrower',null);
 insert into public.accounts(id,account_name,owner_id,holder_id,account_type,currency,opening_balance) values(acc,'Fixture custody',dad,me,'custody','MVR',1000);
 insert into public.loans(id,source_account_id,lender_id,borrower_id,principal_amount,currency,loan_date) values(gen_random_uuid(),acc,dad,borrower,200,'MVR',today);
 perform public.dhaftar_record_savings_v1(gen_random_uuid(),today,'deposit',100,null);
 perform public.dhaftar_create_goal_v2(g,'Emergency',80,today+30);
 perform public.dhaftar_create_goal_v2(g,'Emergency',80,today+30);
 perform public.dhaftar_create_goal_v2(g2,'Travel',100,null);
 perform public.dhaftar_allocate_goal_v2(a,g,70,'reserve');
 perform public.dhaftar_allocate_goal_v2(a,g,70,'reserve');
 d:=public.dhaftar_savings_dashboard_v2();
 if (d->>'balance')::numeric<>100 or (d->>'allocated')::numeric<>70 or (d->>'unallocated')::numeric<>30 or jsonb_array_length(d->'goals')<>2 then raise exception 'Goal totals or idempotency failed';end if;
 begin
  perform public.dhaftar_allocate_goal_v2(a,g,71,'reserve');
  raise exception 'Changed retry accepted';
 exception when sqlstate '22023' then null;end;
 begin
  perform public.dhaftar_allocate_goal_v2(gen_random_uuid(),g2,31,null);
  raise exception 'Excess allocation accepted';
 exception when check_violation then null;end;
 begin
  perform public.dhaftar_allocate_goal_v2(gen_random_uuid(),g,11,null);
  raise exception 'Target overflow accepted';
 exception when check_violation then null;end;
 begin
  perform public.dhaftar_allocate_goal_v2(gen_random_uuid(),g,-71,null);
  raise exception 'Excess release accepted';
 exception when check_violation then null;end;
 begin
  perform public.dhaftar_record_savings_v1(gen_random_uuid(),today,'withdrawal',31,null);
  raise exception 'Reserved funds withdrawn';
 exception when check_violation then null;end;
 perform public.dhaftar_allocate_goal_v2(b,g,-20,'release');
 perform public.dhaftar_allocate_goal_v2(b,g,-20,'release');
 perform public.dhaftar_record_savings_v1(gen_random_uuid(),today,'withdrawal',40,null);
 perform public.dhaftar_save_bank_check_v2(c,860,'matched');
 perform public.dhaftar_save_bank_check_v2(c,860,'matched');
 d:=public.dhaftar_savings_dashboard_v2();
 if (d->>'balance')::numeric<>60 or (d->>'allocated')::numeric<>50 or (d->>'unallocated')::numeric<>10 then raise exception 'Release or withdrawal totals wrong';end if;
 if jsonb_array_length(d->'monthly')<>12 or (d->'monthly'->11->>'deposits')::numeric<>100 or (d->'monthly'->11->>'withdrawals')::numeric<>40 then raise exception 'Analytics incorrect';end if;
 if jsonb_array_length(d->'allocation_history')<>2 or jsonb_array_length(d->'checks')<>1 then raise exception 'History count incorrect';end if;
 if not exists(select 1 from public.amanah_bank_checks_v2 where id=c and dad_cash=800 and personal_savings=60 and expected=860 and difference=0) then raise exception 'Reconciliation incorrect';end if;
 perform public.dhaftar_record_savings_v1(gen_random_uuid(),today,'deposit',5,null);
 if not exists(select 1 from public.amanah_bank_checks_v2 where id=c and personal_savings=60) then raise exception 'Prior snapshot changed';end if;
 raise notice 'PASS: goal retries, allocations, releases, withdrawal protection, monthly analytics and immutable bank snapshots';
end $$;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000002',true);
do $$ begin
 if exists(select 1 from public.amanah_savings_goals_v2) or exists(select 1 from public.amanah_goal_allocations_v2) or exists(select 1 from public.amanah_bank_checks_v2) then raise exception 'Private records exposed';end if;
 begin
  perform public.dhaftar_savings_dashboard_v2();
  raise exception 'Unauthorized dashboard access';
 exception when insufficient_privilege then null;end;
end $$;
reset role;
rollback;
