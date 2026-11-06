-- Reproducible baseline for the Marcello Elite customer control plane.
-- Captured from the central Customer Platform schema on 2026-11-06.
-- This migration is for clean disposable environments and future reviewed deployments.
-- It contains schema and public catalog configuration only; no customer records or secrets.
-- It does not touch the legacy family-care project.

create table public.customer_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  locale text not null default 'en',
  timezone text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.households (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create table public.household_members (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'owner'
    check (role in ('owner', 'admin', 'member')),
  created_at timestamptz not null default now(),
  unique (household_id, user_id)
);

create table public.subscription_plans (
  plan_key text primary key,
  display_name text not null,
  description text not null,
  monthly_price_cents integer not null check (monthly_price_cents > 0),
  currency text not null default 'USD',
  billing_interval text not null default 'month' check (billing_interval = 'month'),
  includes_all_apps boolean not null default true,
  personalized_setup boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.subscriptions (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  plan_key text not null check (plan_key in ('family', 'full_setup')),
  status text not null default 'incomplete'
    check (status in ('incomplete', 'trialing', 'active', 'past_due', 'canceled', 'unpaid')),
  billing_provider text,
  provider_customer_id text unique,
  provider_subscription_id text unique,
  current_period_start timestamptz,
  current_period_end timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.app_catalog (
  app_key text primary key,
  display_name text not null,
  description text,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.household_app_access (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  app_key text not null references public.app_catalog(app_key),
  is_enabled boolean not null default false,
  created_at timestamptz not null default now(),
  unique (household_id, app_key)
);

create table public.customer_onboarding (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null unique references public.households(id) on delete cascade,
  status text not null default 'not_started'
    check (status in ('not_started', 'in_progress', 'completed')),
  setup_notes text,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Public catalog fixtures: exactly the seven existing application keys and two plans.
insert into public.app_catalog (app_key, display_name, description, is_active) values
  ('gastos_admin', 'Gastos Admin', 'Control total de gastos', true),
  ('gastos_mama', 'Gastos Mamá', 'Gastos y saldo', true),
  ('rosita', 'Rosita', 'Cuidado y sesiones', true),
  ('pagos', 'Pagos', 'Pagos semanales', true),
  ('historial', 'Historial', 'Reportes y gráficas', true),
  ('inventario', 'Inventario', 'Inventario de medicamentos', true),
  ('medico', 'Médico', 'Reportes para el médico', true);

insert into public.subscription_plans
  (plan_key, display_name, description, monthly_price_cents, currency,
   billing_interval, includes_all_apps, personalized_setup, is_active)
values
  ('family', 'Family Plan',
   'Access to all seven Marcello Elite applications with self-service onboarding.',
   2900, 'USD', 'month', true, false, true),
  ('full_setup', 'Full Setup',
   'Access to all seven applications with personalized onboarding, initial configuration and setup assistance.',
   4900, 'USD', 'month', true, true, true);

-- Membership predicates used by tenant-scoped RLS policies.
create or replace function public.is_household_member(p_household_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.household_members
    where household_id = p_household_id
      and user_id = (select auth.uid())
  );
$$;

create or replace function public.is_household_owner(p_household_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.household_members
    where household_id = p_household_id
      and user_id = (select auth.uid())
      and role = 'owner'
  );
$$;

create or replace function public.create_household(p_name text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  new_household_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'Household name is required';
  end if;

  insert into public.households (name, created_by)
  values (trim(p_name), auth.uid())
  returning id into new_household_id;

  insert into public.household_members (household_id, user_id, role)
  values (new_household_id, auth.uid(), 'owner');

  insert into public.customer_onboarding (household_id)
  values (new_household_id);

  return new_household_id;
end;
$$;

create or replace function public.complete_customer_onboarding(
  p_user_id uuid,
  p_name text,
  p_plan_key text,
  p_locale text default 'en',
  p_timezone text default null
)
returns jsonb
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_household_id uuid;
  v_app_count integer;
begin
  if p_user_id is null or p_name is null
     or length(trim(p_name)) = 0 or length(trim(p_name)) > 100 then
    raise exception 'Invalid customer information';
  end if;

  if p_plan_key not in ('family', 'full_setup') then
    raise exception 'Invalid subscription plan';
  end if;

  if not exists (
    select 1 from public.subscription_plans
    where plan_key = p_plan_key and is_active = true
  ) then
    raise exception 'Plan unavailable';
  end if;

  if exists (
    select 1 from public.household_members
    where user_id = p_user_id and role = 'owner'
  ) then
    raise exception 'Customer already has an owner household';
  end if;

  select count(*) into v_app_count
  from public.app_catalog where is_active = true;

  if v_app_count <> 7 then
    raise exception 'Expected seven active applications';
  end if;

  insert into public.households (name, created_by)
  values (trim(p_name), p_user_id)
  returning id into v_household_id;

  insert into public.customer_profiles (id, display_name, locale, timezone)
  values (
    p_user_id, trim(p_name),
    case when p_locale = 'es' then 'es' else 'en' end,
    p_timezone
  )
  on conflict (id) do update set
    display_name = excluded.display_name,
    locale = excluded.locale,
    timezone = excluded.timezone,
    updated_at = now();

  insert into public.household_members (household_id, user_id, role)
  values (v_household_id, p_user_id, 'owner');

  insert into public.subscriptions (household_id, plan_key, status)
  values (v_household_id, p_plan_key, 'incomplete');

  insert into public.household_app_access (household_id, app_key, is_enabled)
  select v_household_id, app_key, false
  from public.app_catalog where is_active = true;

  insert into public.customer_onboarding (household_id, status)
  values (v_household_id, 'not_started');

  return jsonb_build_object(
    'success', true,
    'household_id', v_household_id,
    'plan', p_plan_key,
    'applications_prepared', v_app_count,
    'access_enabled', false
  );
end;
$$;

create or replace function public.handle_new_customer()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.customer_profiles (id)
  values (new.id)
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created_customer
after insert on auth.users
for each row execute function public.handle_new_customer();

-- Match the current project's automatic RLS-on-create safeguard.
create or replace function public.rls_auto_enable()
returns event_trigger
language plpgsql
security definer
set search_path = 'pg_catalog'
as $
declare
  cmd record;
  tbl name;
begin
  for cmd in
    select *
    from pg_event_trigger_ddl_commands()
    where command_tag in ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      and object_type in ('table','partitioned table')
  loop
     if cmd.schema_name is not null
        and cmd.schema_name in ('public')
        and cmd.schema_name not in ('pg_catalog','information_schema')
        and cmd.schema_name not like 'pg_toast%'
        and cmd.schema_name not like 'pg_temp%' then
      begin
        select c.relname into tbl from pg_catalog.pg_class c where c.oid = cmd.objid;
        execute format('alter table if exists %I.%I enable row level security', cmd.schema_name, tbl);
        raise log 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      exception
        when others then
          raise log 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      end;
     else
        raise log 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
     end if;
  end loop;
end;
$;

create event trigger ensure_rls
on ddl_command_end
when tag in ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
execute function public.rls_auto_enable();

alter table public.customer_profiles enable row level security;
alter table public.households enable row level security;
alter table public.household_members enable row level security;
alter table public.subscriptions enable row level security;
alter table public.app_catalog enable row level security;
alter table public.household_app_access enable row level security;
alter table public.customer_onboarding enable row level security;

create policy "Anyone can view active plans"
on public.subscription_plans for select to anon, authenticated
using (is_active = true);

create policy "Customers read own profile"
on public.customer_profiles for select to authenticated
using (id = (select auth.uid()));

create policy "Customers update own profile"
on public.customer_profiles for update to authenticated
using (id = (select auth.uid()))
with check (id = (select auth.uid()));

create policy "Members read their households"
on public.households for select to authenticated
using (public.is_household_member(id));

create policy "Owners update their households"
on public.households for update to authenticated
using (public.is_household_owner(id))
with check (public.is_household_owner(id));

create policy "Members read household membership"
on public.household_members for select to authenticated
using (public.is_household_member(household_id));

create policy "Members read household subscriptions"
on public.subscriptions for select to authenticated
using (public.is_household_member(household_id));

create policy "Authenticated customers read active apps"
on public.app_catalog for select to authenticated
using (is_active = true);

create policy "Members read their application access"
on public.household_app_access for select to authenticated
using (public.is_household_member(household_id));

create policy "Members read onboarding status"
on public.customer_onboarding for select to authenticated
using (public.is_household_member(household_id));

create policy "Owners update onboarding"
on public.customer_onboarding for update to authenticated
using (public.is_household_owner(household_id))
with check (public.is_household_owner(household_id));

-- Table privileges mirror the live project's exposed read surfaces.
grant select on public.subscription_plans to anon, authenticated;
grant select on public.customer_profiles, public.households, public.household_members,
  public.subscriptions, public.app_catalog, public.household_app_access,
  public.customer_onboarding to authenticated;

grant execute on function public.create_household(text) to authenticated;
grant execute on function public.is_household_member(uuid) to authenticated;
grant execute on function public.is_household_owner(uuid) to authenticated;
revoke execute on function public.complete_customer_onboarding(uuid, text, text, text, text)
  from public, anon, authenticated;
grant execute on function public.complete_customer_onboarding(uuid, text, text, text, text)
  to service_role;

-- The subsequent hardening migration revokes public access to the two
-- unnecessary SECURITY DEFINER entry points: create_household and rls_auto_enable.
