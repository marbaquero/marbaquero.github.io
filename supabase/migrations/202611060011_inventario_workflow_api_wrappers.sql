create or replace function public.record_customer_purchase(
  p_household_id uuid,p_purchase_date date,p_pharmacy text,p_receipt_reference text,
  p_total numeric,p_saved numeric,p_stock_applied boolean,p_items jsonb
) returns jsonb language sql security definer set search_path=''
as $$ select customer_data.record_purchase(p_household_id,p_purchase_date,p_pharmacy,p_receipt_reference,p_total,p_saved,p_stock_applied,p_items); $$;

create or replace function public.record_customer_weekly_fill(
  p_household_id uuid,p_event_date timestamptz,p_caregiver_label text,p_stock_applied boolean,p_items jsonb
) returns jsonb language sql security definer set search_path=''
as $$ select customer_data.record_weekly_fill(p_household_id,p_event_date,p_caregiver_label,p_stock_applied,p_items); $$;

create or replace function public.record_customer_stock_count(
  p_household_id uuid,p_caregiver_label text,p_items jsonb
) returns jsonb language sql security definer set search_path=''
as $$ select customer_data.record_stock_count(p_household_id,p_caregiver_label,p_items); $$;

revoke all on function public.record_customer_purchase(uuid,date,text,text,numeric,numeric,boolean,jsonb) from public,anon,authenticated;
revoke all on function public.record_customer_weekly_fill(uuid,timestamptz,text,boolean,jsonb) from public,anon,authenticated;
revoke all on function public.record_customer_stock_count(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.record_customer_purchase(uuid,date,text,text,numeric,numeric,boolean,jsonb) to service_role;
grant execute on function public.record_customer_weekly_fill(uuid,timestamptz,text,boolean,jsonb) to service_role;
grant execute on function public.record_customer_stock_count(uuid,text,jsonb) to service_role;
