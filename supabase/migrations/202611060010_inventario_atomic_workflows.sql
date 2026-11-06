-- Atomic purchase, weekly-fill, and physical-count operations.

create or replace function customer_data.record_purchase(
  p_household_id uuid,
  p_purchase_date date,
  p_pharmacy text,
  p_receipt_reference text,
  p_total numeric,
  p_saved numeric,
  p_stock_applied boolean,
  p_items jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_purchase_id uuid;
  v_item jsonb;
  v_medicine_id uuid;
  v_name text;
  v_qty numeric;
  v_subtotal numeric;
  v_count integer := 0;
begin
  if p_household_id is null or p_total is null or p_total < 0
     or coalesce(p_saved,0) < 0 or p_items is null or jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) = 0
     or length(coalesce(p_pharmacy,'')) > 160
     or length(coalesce(p_receipt_reference,'')) > 240 then
    raise exception 'Invalid purchase fields' using errcode='22023';
  end if;

  insert into customer_data.medicine_purchases(
    household_id,purchase_date,pharmacy,receipt_reference,total,saved,stock_applied
  ) values (
    p_household_id,coalesce(p_purchase_date,current_date),coalesce(p_pharmacy,''),
    coalesce(p_receipt_reference,''),p_total,coalesce(p_saved,0),coalesce(p_stock_applied,false)
  ) returning id into v_purchase_id;

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    v_name := btrim(coalesce(v_item->>'name',''));
    v_qty := (v_item->>'quantity')::numeric;
    v_subtotal := coalesce((v_item->>'subtotal')::numeric,0);
    v_medicine_id := nullif(v_item->>'medicine_id','')::uuid;
    if length(v_name) not between 1 and 160 or v_qty is null or v_qty <= 0 or v_subtotal is null or v_subtotal < 0 then
      raise exception 'Invalid purchase item' using errcode='22023';
    end if;
    if p_stock_applied and v_medicine_id is null then
      raise exception 'Every stock-applied purchase item must be linked to a medicine' using errcode='22023';
    end if;
    insert into customer_data.medicine_purchase_items(
      household_id,purchase_id,medicine_id,item_name_snapshot,quantity,subtotal
    ) values (p_household_id,v_purchase_id,v_medicine_id,v_name,v_qty,v_subtotal);
    if p_stock_applied then
      update customer_data.medicines
      set stock_quantity=stock_quantity+v_qty,
          unit_cost=case when v_qty > 0 then v_subtotal/v_qty else unit_cost end,
          updated_at=now()
      where household_id=p_household_id and id=v_medicine_id and active;
      if not found then
        raise exception 'Purchase medicine not found' using errcode='P0002';
      end if;
    end if;
    v_count := v_count+1;
  end loop;

  return jsonb_build_object('purchase_id',v_purchase_id,'items_recorded',v_count,'stock_applied',coalesce(p_stock_applied,false));
end;
$$;

create or replace function customer_data.record_weekly_fill(
  p_household_id uuid,
  p_event_date timestamptz,
  p_caregiver_label text,
  p_stock_applied boolean,
  p_items jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_fill_id uuid;
  v_item jsonb;
  v_medicine_id uuid;
  v_medicine customer_data.medicines;
  v_qty numeric;
  v_count integer := 0;
begin
  if p_household_id is null or p_items is null or jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items)=0
     or length(coalesce(p_caregiver_label,''))>120 then
    raise exception 'Invalid weekly fill fields' using errcode='22023';
  end if;
  insert into customer_data.medicine_fill_events(
    household_id,event_date,caregiver_label,stock_applied
  ) values (
    p_household_id,coalesce(p_event_date,now()),coalesce(p_caregiver_label,''),coalesce(p_stock_applied,false)
  ) returning id into v_fill_id;

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    v_medicine_id := (v_item->>'medicine_id')::uuid;
    v_qty := (v_item->>'quantity')::numeric;
    if v_qty is null or v_qty <= 0 then raise exception 'Fill quantity must be positive' using errcode='22023'; end if;
    select * into v_medicine from customer_data.medicines
    where household_id=p_household_id and id=v_medicine_id and active for update;
    if not found then raise exception 'Fill medicine not found' using errcode='P0002'; end if;
    if p_stock_applied and v_medicine.stock_quantity < v_qty then
      raise exception 'Insufficient stock for weekly fill' using errcode='22023';
    end if;
    insert into customer_data.medicine_fill_items(
      household_id,fill_event_id,medicine_id,medicine_name_snapshot,quantity
    ) values (p_household_id,v_fill_id,v_medicine_id,v_medicine.name,v_qty);
    if p_stock_applied then
      update customer_data.medicines set stock_quantity=stock_quantity-v_qty,updated_at=now()
      where household_id=p_household_id and id=v_medicine_id;
    end if;
    v_count := v_count+1;
  end loop;
  return jsonb_build_object('fill_id',v_fill_id,'items_recorded',v_count,'stock_applied',coalesce(p_stock_applied,false));
end;
$$;

create or replace function customer_data.record_stock_count(
  p_household_id uuid,
  p_caregiver_label text,
  p_items jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_adjustment_id uuid;
  v_item jsonb;
  v_medicine_id uuid;
  v_medicine customer_data.medicines;
  v_after numeric;
  v_count integer := 0;
begin
  if p_household_id is null or p_items is null or jsonb_typeof(p_items)<>'array'
     or jsonb_array_length(p_items)=0
     or length(coalesce(p_caregiver_label,''))>120 then
    raise exception 'Invalid stock count fields' using errcode='22023';
  end if;
  insert into customer_data.medicine_stock_adjustments(household_id,caregiver_label)
  values(p_household_id,coalesce(p_caregiver_label,'')) returning id into v_adjustment_id;

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    v_medicine_id := (v_item->>'medicine_id')::uuid;
    v_after := (v_item->>'quantity_after')::numeric;
    if v_after is null or v_after < 0 then raise exception 'Count cannot be negative' using errcode='22023'; end if;
    select * into v_medicine from customer_data.medicines
    where household_id=p_household_id and id=v_medicine_id and active for update;
    if not found then raise exception 'Count medicine not found' using errcode='P0002'; end if;
    if v_after <> v_medicine.stock_quantity then
      insert into customer_data.medicine_stock_adjustment_items(
        household_id,adjustment_id,medicine_id,medicine_name_snapshot,quantity_before,quantity_after
      ) values (
        p_household_id,v_adjustment_id,v_medicine_id,v_medicine.name,v_medicine.stock_quantity,v_after
      );
      update customer_data.medicines set stock_quantity=v_after,updated_at=now()
      where household_id=p_household_id and id=v_medicine_id;
      v_count := v_count+1;
    end if;
  end loop;
  return jsonb_build_object('adjustment_id',v_adjustment_id,'medicines_changed',v_count);
end;
$$;

revoke all on function customer_data.record_purchase(uuid,date,text,text,numeric,numeric,boolean,jsonb) from public,anon,authenticated;
revoke all on function customer_data.record_weekly_fill(uuid,timestamptz,text,boolean,jsonb) from public,anon,authenticated;
revoke all on function customer_data.record_stock_count(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function customer_data.record_purchase(uuid,date,text,text,numeric,numeric,boolean,jsonb) to service_role;
grant execute on function customer_data.record_weekly_fill(uuid,timestamptz,text,boolean,jsonb) to service_role;
grant execute on function customer_data.record_stock_count(uuid,text,jsonb) to service_role;
