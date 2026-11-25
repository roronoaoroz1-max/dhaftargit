begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',true);
do $$
declare a uuid:=gen_random_uuid();b uuid:=gen_random_uuid();batch uuid:=gen_random_uuid();bad uuid:=gen_random_uuid();p uuid;d date:=(now() at time zone 'Indian/Maldives')::date;lines jsonb;
begin
 insert into public.stock_items(id,name,unit) values(a,'Fixture A','kg'),(b,'Fixture B','pcs');
 perform public.dhaftar_save_stock_preferences_v4(a,'Shop A',7,true);
 lines:=jsonb_build_array(jsonb_build_object('item_id',a,'quantity',2,'amount',50),jsonb_build_object('item_id',b,'quantity',3,'amount',75));
 perform public.dhaftar_record_stock_batch_v4(batch,d-1,'Shop A',lines);
 perform public.dhaftar_record_stock_batch_v4(batch,d-1,'Shop A',lines);
 if (select count(*) from public.stock_purchases where stock_item_id in(a,b))<>2 then raise exception 'Duplicate purchases';end if;
 if (select count(*) from public.dhaftar_stock_purchase_shops_v4 where batch_id=batch)<>2 then raise exception 'Shop history missing';end if;
 if (select manual_low from public.dhaftar_stock_preferences_v4 where item_id=a) then raise exception 'Low flag not cleared';end if;
 perform public.dhaftar_save_stock_preferences_v4(a,'Shop A',7,true);
 perform public.dhaftar_record_stock_batch_v4(batch,d-1,'Shop A',lines);
 if not (select manual_low from public.dhaftar_stock_preferences_v4 where item_id=a) then raise exception 'Retry cleared low flag';end if;
 begin
 perform public.dhaftar_record_stock_batch_v4(bad,d,'Shop B',jsonb_build_array(jsonb_build_object('item_id',a,'quantity',2,'amount',50),jsonb_build_object('item_id',b,'quantity',0,'amount',75)));
 raise exception 'Invalid batch accepted';exception when sqlstate '22023' then null;end;
 if exists(select 1 from public.dhaftar_stock_batches_v4 where id=bad) or (select count(*) from public.stock_purchases where stock_item_id in(a,b))<>2 or exists(select 1 from public.stock_purchases where stock_item_id in(a,b) and ended_reason is not null) then raise exception 'Partial batch survived';end if;
 begin perform public.dhaftar_record_stock_batch_v4(batch,d-1,'Changed shop',lines);raise exception 'Changed retry accepted';exception when sqlstate '22023' then null;end;
 p:=md5(batch::text||':'||a::text)::uuid;
 perform public.dhaftar_mark_runout_v4(a,p,d);
 perform public.dhaftar_mark_runout_v4(a,p,d);
 if not exists(select 1 from public.stock_purchases where id=p and run_out_on=d) then raise exception 'Runout failed';end if;
 raise notice 'PASS: atomic batch, retries, shop history, manual low flag and runout';
end $$;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000002',true);
do $$ begin
 if exists(select 1 from public.dhaftar_stock_preferences_v4) or exists(select 1 from public.dhaftar_stock_batches_v4) or exists(select 1 from public.dhaftar_stock_purchase_shops_v4) then raise exception 'Private stock exposed';end if;
 begin perform public.dhaftar_record_stock_batch_v4(gen_random_uuid(),current_date,null,'[]');raise exception 'Unauthorized batch';exception when insufficient_privilege then null;end;
end $$;
rollback;
