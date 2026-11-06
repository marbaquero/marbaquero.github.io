-- Public PostgREST entry point for the private Inventario read model.
-- The underlying customer_data schema remains unexposed and inaccessible to browser roles.

create or replace function public.list_customer_medicines(p_household_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', m.id,
        'name', m.name,
        'dose', m.dose,
        'brand', m.brand,
        'stock_quantity', m.stock_quantity,
        'minimum_threshold', m.minimum_threshold,
        'daily_dose', m.daily_dose,
        'unit', m.unit,
        'unit_cost', m.unit_cost,
        'active', m.active,
        'created_at', m.created_at,
        'updated_at', m.updated_at
      ) order by m.name
    ),
    '[]'::jsonb
  )
  from customer_data.medicines m
  where m.household_id = p_household_id;
$$;

revoke all on function public.list_customer_medicines(uuid) from public, anon, authenticated;
grant execute on function public.list_customer_medicines(uuid) to service_role;

comment on function public.list_customer_medicines(uuid) is
  'Service-role-only read model for the private customer Inventario schema.';
