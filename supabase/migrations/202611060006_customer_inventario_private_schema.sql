-- Customer Inventario private data plane.
-- This migration is exercised by disposable local Supabase CI only.
-- Do not apply to the hosted customer project without separate release approval.

create schema if not exists customer_data;

revoke all on schema customer_data from public, anon, authenticated;
grant usage on schema customer_data to service_role;

create table customer_data.medicines (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  name text not null check (length(btrim(name)) between 1 and 160),
  dose text not null default '' check (length(dose) <= 80),
  brand text not null default '' check (length(brand) <= 120),
  stock_quantity numeric(12,3) not null default 0 check (stock_quantity >= 0),
  minimum_threshold numeric(12,3) not null default 0 check (minimum_threshold >= 0),
  daily_dose numeric(12,3) not null default 0 check (daily_dose >= 0),
  unit text not null default 'unidad' check (length(btrim(unit)) between 1 and 40),
  unit_cost numeric(12,4) not null default 0 check (unit_cost >= 0),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (household_id, id)
);

create table customer_data.medicine_purchases (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  purchase_date date not null default current_date,
  pharmacy text not null default '' check (length(pharmacy) <= 160),
  receipt_reference text not null default '' check (length(receipt_reference) <= 240),
  total numeric(12,2) not null default 0 check (total >= 0),
  saved numeric(12,2) not null default 0 check (saved >= 0),
  stock_applied boolean not null default false,
  created_at timestamptz not null default now(),
  unique (household_id, id)
);

create table customer_data.medicine_purchase_items (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null,
  purchase_id uuid not null,
  medicine_id uuid,
  item_name_snapshot text not null check (length(btrim(item_name_snapshot)) between 1 and 160),
  quantity numeric(12,3) not null check (quantity > 0),
  subtotal numeric(12,2) not null default 0 check (subtotal >= 0),
  created_at timestamptz not null default now(),
  foreign key (household_id, purchase_id)
    references customer_data.medicine_purchases(household_id, id) on delete cascade,
  foreign key (household_id, medicine_id)
    references customer_data.medicines(household_id, id) on delete restrict
);

create table customer_data.medicine_dispensing_events (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null,
  medicine_id uuid not null,
  medicine_name_snapshot text not null,
  event_date timestamptz not null default now(),
  quantity numeric(12,3) not null check (quantity > 0),
  caregiver_label text not null default '' check (length(caregiver_label) <= 120),
  created_at timestamptz not null default now(),
  foreign key (household_id, medicine_id)
    references customer_data.medicines(household_id, id) on delete restrict
);

create table customer_data.medicine_fill_events (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  event_date timestamptz not null default now(),
  caregiver_label text not null default '' check (length(caregiver_label) <= 120),
  stock_applied boolean not null default false,
  created_at timestamptz not null default now(),
  unique (household_id, id)
);

create table customer_data.medicine_fill_items (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null,
  fill_event_id uuid not null,
  medicine_id uuid not null,
  medicine_name_snapshot text not null,
  quantity numeric(12,3) not null check (quantity > 0),
  foreign key (household_id, fill_event_id)
    references customer_data.medicine_fill_events(household_id, id) on delete cascade,
  foreign key (household_id, medicine_id)
    references customer_data.medicines(household_id, id) on delete restrict
);

create table customer_data.medicine_stock_adjustments (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  adjustment_date timestamptz not null default now(),
  caregiver_label text not null default '' check (length(caregiver_label) <= 120),
  created_at timestamptz not null default now(),
  unique (household_id, id)
);

create table customer_data.medicine_stock_adjustment_items (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null,
  adjustment_id uuid not null,
  medicine_id uuid not null,
  medicine_name_snapshot text not null,
  quantity_before numeric(12,3) not null check (quantity_before >= 0),
  quantity_after numeric(12,3) not null check (quantity_after >= 0),
  foreign key (household_id, adjustment_id)
    references customer_data.medicine_stock_adjustments(household_id, id) on delete cascade,
  foreign key (household_id, medicine_id)
    references customer_data.medicines(household_id, id) on delete restrict
);

create index medicines_household_active_idx
  on customer_data.medicines(household_id, active, name);
create index medicine_purchases_household_date_idx
  on customer_data.medicine_purchases(household_id, purchase_date desc);
create index medicine_purchase_items_household_medicine_idx
  on customer_data.medicine_purchase_items(household_id, medicine_id);
create index medicine_dispensing_household_date_idx
  on customer_data.medicine_dispensing_events(household_id, event_date desc);
create index medicine_dispensing_household_medicine_idx
  on customer_data.medicine_dispensing_events(household_id, medicine_id);
create index medicine_fill_events_household_date_idx
  on customer_data.medicine_fill_events(household_id, event_date desc);
create index medicine_stock_adjustments_household_date_idx
  on customer_data.medicine_stock_adjustments(household_id, adjustment_date desc);

alter table customer_data.medicines enable row level security;
alter table customer_data.medicine_purchases enable row level security;
alter table customer_data.medicine_purchase_items enable row level security;
alter table customer_data.medicine_dispensing_events enable row level security;
alter table customer_data.medicine_fill_events enable row level security;
alter table customer_data.medicine_fill_items enable row level security;
alter table customer_data.medicine_stock_adjustments enable row level security;
alter table customer_data.medicine_stock_adjustment_items enable row level security;

-- Browser roles receive no schema usage or table privileges. The future
-- authenticated Edge Function/API layer will perform membership and
-- entitlement checks, then call narrowly scoped service-role-only DB functions.
revoke all on all tables in schema customer_data from public, anon, authenticated;
grant select, insert, update, delete on all tables in schema customer_data to service_role;
alter default privileges in schema customer_data
  revoke all on tables from public, anon, authenticated;
alter default privileges in schema customer_data
  grant select, insert, update, delete on tables to service_role;

comment on schema customer_data is
  'Private household-scoped customer data. Not exposed to browser roles through the Data API.';
