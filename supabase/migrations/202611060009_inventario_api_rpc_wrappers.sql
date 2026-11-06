-- Exposed-schema RPC wrappers. Browser roles cannot execute these; the
-- Edge Function calls them with its server-side service_role client.

create or replace function public.create_customer_medicine(
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
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select to_jsonb(customer_data.create_medicine(
    p_household_id, p_name, p_dose, p_brand, p_stock_quantity,
    p_minimum_threshold, p_daily_dose, p_unit, p_unit_cost
  ));
$$;

create or replace function public.record_customer_dispensing(
  p_household_id uuid,
  p_medicine_id uuid,
  p_quantity numeric,
  p_caregiver_label text default '',
  p_event_date timestamptz default now()
)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select customer_data.record_dispensing(
    p_household_id, p_medicine_id, p_quantity, p_caregiver_label, p_event_date
  );
$$;

revoke all on function public.create_customer_medicine(uuid,text,text,text,numeric,numeric,numeric,text,numeric)
  from public, anon, authenticated;
revoke all on function public.record_customer_dispensing(uuid,uuid,numeric,text,timestamptz)
  from public, anon, authenticated;
grant execute on function public.create_customer_medicine(uuid,text,text,text,numeric,numeric,numeric,text,numeric)
  to service_role;
grant execute on function public.record_customer_dispensing(uuid,uuid,numeric,text,timestamptz)
  to service_role;
