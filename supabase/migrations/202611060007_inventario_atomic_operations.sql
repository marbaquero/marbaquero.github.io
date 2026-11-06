-- Narrow server-only operations for the Inventario pilot.
-- Callers must be authenticated by the Edge Function, which checks membership
-- and active Inventario entitlement before invoking these RPCs with service_role.

create or replace function customer_data.create_medicine(
  p_household_id uuid,
  p_name text,
  p_dose text default '',
  p_brand text default '',
  p_stock_quantity numeric default 0,
  p_minimum_threshold numeric default 0,
  p_daily_dose numeric default 0,
  p_unit text default 'unidad',
  p_unit_cost numeric default 0
)
returns customer_data.medicines
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row customer_data.medicines;
begin
  if p_household_id is null
     or p_name is null or length(btrim(p_name)) not between 1 and 160
     or coalesce(p_stock_quantity, -1) < 0
     or coalesce(p_minimum_threshold, -1) < 0
     or coalesce(p_daily_dose, -1) < 0
     or coalesce(p_unit_cost, -1) < 0
     or p_unit is null or length(btrim(p_unit)) not between 1 and 40 then
    raise exception 'Invalid medicine fields' using errcode = '22023';
  end if;

  insert into customer_data.medicines (
    household_id, name, dose, brand, stock_quantity,
    minimum_threshold, daily_dose, unit, unit_cost
  ) values (
    p_household_id, btrim(p_name), coalesce(p_dose, ''),
    coalesce(p_brand, ''), p_stock_quantity,
    p_minimum_threshold, p_daily_dose, btrim(p_unit), p_unit_cost
  ) returning * into v_row;

  return v_row;
end;
$$;

create or replace function customer_data.record_dispensing(
  p_household_id uuid,
  p_medicine_id uuid,
  p_quantity numeric,
  p_caregiver_label text default '',
  p_event_date timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_medicine customer_data.medicines;
  v_event_id uuid;
begin
  if p_household_id is null or p_medicine_id is null
     or p_quantity is null or p_quantity <= 0
     or length(coalesce(p_caregiver_label, '')) > 120 then
    raise exception 'Invalid dispensing fields' using errcode = '22023';
  end if;

  select * into v_medicine
  from customer_data.medicines
  where household_id = p_household_id and id = p_medicine_id and active
  for update;

  if not found then
    raise exception 'Medicine not found' using errcode = 'P0002';
  end if;
  if v_medicine.stock_quantity < p_quantity then
    raise exception 'Insufficient stock' using errcode = '22023';
  end if;

  update customer_data.medicines
  set stock_quantity = stock_quantity - p_quantity, updated_at = now()
  where household_id = p_household_id and id = p_medicine_id;

  insert into customer_data.medicine_dispensing_events (
    household_id, medicine_id, medicine_name_snapshot,
    event_date, quantity, caregiver_label
  ) values (
    p_household_id, p_medicine_id, v_medicine.name,
    coalesce(p_event_date, now()), p_quantity, coalesce(p_caregiver_label, '')
  ) returning id into v_event_id;

  return jsonb_build_object(
    'event_id', v_event_id,
    'medicine_id', p_medicine_id,
    'medicine_name', v_medicine.name,
    'quantity_dispensed', p_quantity,
    'remaining_stock', v_medicine.stock_quantity - p_quantity
  );
end;
$$;

revoke all on function customer_data.create_medicine(uuid,text,text,text,numeric,numeric,numeric,text,numeric)
  from public, anon, authenticated;
revoke all on function customer_data.record_dispensing(uuid,uuid,numeric,text,timestamptz)
  from public, anon, authenticated;
grant execute on function customer_data.create_medicine(uuid,text,text,text,numeric,numeric,numeric,text,numeric)
  to service_role;
grant execute on function customer_data.record_dispensing(uuid,uuid,numeric,text,timestamptz)
  to service_role;

comment on function customer_data.record_dispensing(uuid,uuid,numeric,text,timestamptz) is
  'Atomically decrements household medicine stock and writes dispensing history; service_role only.';
