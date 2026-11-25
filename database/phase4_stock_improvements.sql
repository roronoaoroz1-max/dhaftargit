-- Additive stock planning metadata and atomic bulk purchase recording. No existing rows rewritten.
begin;
create table public.dhaftar_stock_preferences_v4(
 item_id uuid primary key references public.stock_items(id) on delete restrict,
 preferred_shop text check(length(preferred_shop)<=100),
 reminder_days integer not null default 5 check(reminder_days between 0 and 30),
 manual_low boolean not null default false,
 updated_at timestamptz not null default now()
);
create table public.dhaftar_stock_batches_v4(
 id uuid primary key,user_id uuid not null references auth.users(id),purchased_on date not null,
 shop text check(length(shop)<=100),payload jsonb not null,created_at timestamptz not null default now()
);
create table public.dhaftar_stock_purchase_shops_v4(
 purchase_id uuid primary key references public.stock_purchases(id) on delete restrict,
 batch_id uuid references public.dhaftar_stock_batches_v4(id),shop text not null check(length(trim(shop)) between 1 and 100)
);
alter table public.dhaftar_stock_preferences_v4 enable row level security;
alter table public.dhaftar_stock_batches_v4 enable row level security;
alter table public.dhaftar_stock_purchase_shops_v4 enable row level security;
revoke all on public.dhaftar_stock_preferences_v4,public.dhaftar_stock_batches_v4,public.dhaftar_stock_purchase_shops_v4 from public,anon,authenticated;
grant select,insert,update on public.dhaftar_stock_preferences_v4 to authenticated;
grant select,insert on public.dhaftar_stock_batches_v4,public.dhaftar_stock_purchase_shops_v4 to authenticated;
create policy stock_preferences_admin on public.dhaftar_stock_preferences_v4 for all to authenticated using((select public.is_admin())) with check((select public.is_admin()));
create policy stock_batches_read on public.dhaftar_stock_batches_v4 for select to authenticated using((select public.is_admin()));
create policy stock_batches_insert on public.dhaftar_stock_batches_v4 for insert to authenticated with check((select public.is_admin()) and user_id=(select auth.uid()));
create policy stock_shops_read on public.dhaftar_stock_purchase_shops_v4 for select to authenticated using((select public.is_admin()));
create policy stock_shops_insert on public.dhaftar_stock_purchase_shops_v4 for insert to authenticated with check((select public.is_admin()));

create function public.dhaftar_save_stock_preferences_v4(p_item uuid,p_shop text,p_days integer,p_low boolean) returns void
language plpgsql security invoker set search_path='' as $$
begin
 if auth.uid() is null or not public.is_admin() then raise exception 'Administrator access required' using errcode='42501';end if;
 if p_item is null or length(p_shop)>100 or p_days is null or p_days not between 0 and 30 or p_low is null then raise exception 'Invalid stock preferences' using errcode='22023';end if;
 perform 1 from public.stock_items where id=p_item and not archived for update;
 if not found then raise exception 'Stock item unavailable' using errcode='23503';end if;
 insert into public.dhaftar_stock_preferences_v4(item_id,preferred_shop,reminder_days,manual_low) values(p_item,nullif(trim(p_shop),''),p_days,p_low)
 on conflict(item_id) do update set preferred_shop=excluded.preferred_shop,reminder_days=excluded.reminder_days,manual_low=excluded.manual_low,updated_at=now();
end $$;

-- Clearing a low flag is part of the successful new purchase, never a retry.
create function public.dhaftar_clear_stock_low_v4() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 update public.dhaftar_stock_preferences_v4 set manual_low=false,updated_at=now() where item_id=new.stock_item_id and manual_low;
 return new;
end $$;
create trigger clear_stock_low_v4 after insert on public.stock_purchases for each row execute function public.dhaftar_clear_stock_low_v4();

-- Stable batch identity; all lines are written in one transaction using Phase 1 RPC.
-- One row per distinct item; deterministic UUID derives from batch+item for safe retries.
create function public.dhaftar_record_stock_batch_v4(p_id uuid,p_date date,p_shop text,p_lines jsonb) returns uuid
language plpgsql security invoker set search_path='' as $$
declare u uuid:=auth.uid();b public.dhaftar_stock_batches_v4%rowtype;r record;v_purchase uuid;v_payload jsonb;v_shop text:=nullif(trim(p_shop),'');
begin
 if u is null or not public.is_admin() then raise exception 'Administrator access required' using errcode='42501';end if;
 if p_id is null or p_date is null or p_date>(now() at time zone 'Indian/Maldives')::date or length(p_shop)>100 or p_lines is null or jsonb_typeof(p_lines)<>'array' then raise exception 'Invalid bulk purchase' using errcode='22023';end if;
 if jsonb_array_length(p_lines) not between 1 and 50 then raise exception 'Enter 1 to 50 purchase lines' using errcode='22023';end if;
 if exists(select 1 from jsonb_array_elements(p_lines) e where jsonb_typeof(e)<>'object' or jsonb_typeof(e->'quantity') is distinct from 'number' or jsonb_typeof(e->'amount') is distinct from 'number' or jsonb_typeof(e->'item_id') is distinct from 'string') then raise exception 'Invalid purchase line' using errcode='22023';end if;
 if (select count(distinct item_id) from jsonb_to_recordset(p_lines) as x(item_id uuid))<>jsonb_array_length(p_lines) then raise exception 'Each item can appear only once per batch' using errcode='22023';end if;
 select jsonb_agg(jsonb_build_object('item_id',item_id,'quantity',quantity,'amount',amount,'note',nullif(trim(note),'')) order by item_id) into v_payload from jsonb_to_recordset(p_lines) as x(item_id uuid,quantity numeric,amount numeric,note text);
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('dhaftar-stock-batch:'||p_id::text,0));
 select * into b from public.dhaftar_stock_batches_v4 where id=p_id;
 if found then
  if b.user_id<>u or b.purchased_on<>p_date or b.shop is distinct from v_shop or b.payload is distinct from v_payload then raise exception 'Request ID already used for different details' using errcode='22023';end if;
  return p_id;
 end if;
 -- Lock each item before changing any purchase cycles.
 perform 1 from public.stock_items where id in(select item_id from jsonb_to_recordset(v_payload) as x(item_id uuid)) order by id for update;
 insert into public.dhaftar_stock_batches_v4(id,user_id,purchased_on,shop,payload) values(p_id,u,p_date,v_shop,v_payload);
 for r in select * from jsonb_to_recordset(v_payload) as x(item_id uuid,quantity numeric,amount numeric,note text) order by item_id loop
  if length(r.note)>120 then raise exception 'Purchase note too long' using errcode='22023';end if;
  v_purchase:=md5(p_id::text||':'||r.item_id::text)::uuid;
  perform public.dhaftar_record_stock_purchase_v1(v_purchase,r.item_id,p_date,r.quantity,r.amount,r.note);
  if v_shop is not null then insert into public.dhaftar_stock_purchase_shops_v4(purchase_id,batch_id,shop) values(v_purchase,p_id,v_shop);end if;
 end loop;
 return p_id;
end $$;

-- Runout can only close the current open cycle, not an already superseded or voided purchase.
create function public.dhaftar_mark_runout_v4(p_item uuid,p_purchase uuid,p_date date) returns void
language plpgsql security invoker set search_path='' as $$
declare r public.stock_purchases%rowtype;
begin
 if auth.uid() is null or not public.is_admin() then raise exception 'Administrator access required' using errcode='42501';end if;
 perform 1 from public.stock_items where id=p_item and not archived for update;
 if not found then raise exception 'Stock item unavailable' using errcode='23503';end if;
 select * into r from public.stock_purchases where id=p_purchase and stock_item_id=p_item and voided_at is null for update;
 if not found then raise exception 'Stock purchase unavailable' using errcode='23503';end if;
 if r.run_out_on=p_date then return;end if;
 if p_date is null or p_date<r.purchased_on or p_date>(now() at time zone 'Indian/Maldives')::date or r.run_out_on is not null or r.ended_reason is not null then raise exception 'Stock cycle changed; refresh before recording runout' using errcode='23514';end if;
 update public.stock_purchases set run_out_on=p_date,ended_reason=null,ended_on=null where id=p_purchase;
end $$;
revoke all on function public.dhaftar_save_stock_preferences_v4(uuid,text,integer,boolean),public.dhaftar_clear_stock_low_v4(),public.dhaftar_record_stock_batch_v4(uuid,date,text,jsonb),public.dhaftar_mark_runout_v4(uuid,uuid,date) from public,anon;
grant execute on function public.dhaftar_save_stock_preferences_v4(uuid,text,integer,boolean),public.dhaftar_clear_stock_low_v4(),public.dhaftar_record_stock_batch_v4(uuid,date,text,jsonb),public.dhaftar_mark_runout_v4(uuid,uuid,date) to authenticated;
commit;
