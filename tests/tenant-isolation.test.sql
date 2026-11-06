begin;

create extension if not exists pgtap with schema extensions;

-- Synthetic auth users only. The auth trigger should create their profiles.
insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('11111111-1111-4111-8111-111111111111', 'authenticated', 'authenticated',
   'tenant-a@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('22222222-2222-4222-8222-222222222222', 'authenticated', 'authenticated',
   'tenant-b@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now())
on conflict (id) do nothing;

insert into public.households (id, name, created_by) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Synthetic Household A',
   '11111111-1111-4111-8111-111111111111'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'Synthetic Household B',
   '22222222-2222-4222-8222-222222222222');

insert into public.household_members (household_id, user_id, role) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '11111111-1111-4111-8111-111111111111', 'owner'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', '22222222-2222-4222-8222-222222222222', 'owner');

insert into public.subscriptions (household_id, plan_key, status) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'family', 'active'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'full_setup', 'active');

insert into public.household_app_access (household_id, app_key, is_enabled)
select 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', app_key, true
from public.app_catalog;
insert into public.household_app_access (household_id, app_key, is_enabled)
select 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', app_key, true
from public.app_catalog;

insert into public.customer_onboarding (household_id, status) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'completed'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'completed');

-- Confirm the post-hardening event trigger still enables RLS on newly created
-- public tables even after PUBLIC/anon/authenticated EXECUTE was revoked.
create table public._ci_post_hardening_rls_probe (id bigint);
select plan(17);
select ok(
  (select relrowsecurity from pg_class where oid = 'public._ci_post_hardening_rls_probe'::regclass),
  'RLS auto-enable event trigger still works after its function EXECUTE grant is revoked'
);
drop table public._ci_post_hardening_rls_probe;

-- Confirm the clean baseline contains the seven configured applications.
select is((select count(*)::integer from public.app_catalog where is_active), 7,
  'Baseline includes exactly seven active applications');

-- Trusted Edge Functions use the service_role key for these narrowly scoped operations.
select ok(has_table_privilege('service_role', 'public.household_members', 'select'),
  'Backend service role can look up household owner membership');
select ok(has_table_privilege('service_role', 'public.subscriptions', 'select'),
  'Backend service role can read subscriptions for billing flows');
select ok(has_table_privilege('service_role', 'public.subscriptions', 'insert'),
  'Backend service role can insert subscription records from Stripe webhooks');
select ok(has_table_privilege('service_role', 'public.subscriptions', 'update'),
  'Backend service role can update subscription lifecycle state');
select ok(has_table_privilege('service_role', 'public.household_app_access', 'select'),
  'Backend service role can filter household application access rows');
select ok(has_table_privilege('service_role', 'public.household_app_access', 'update'),
  'Backend service role can enable or disable household application access');

-- User A: verify household-scoped reads across the real platform tables.
set local role authenticated;
select set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', true);

select is((select count(*)::integer from public.customer_profiles), 1,
  'User A can read only their own customer profile');
select is((select count(*)::integer from public.households), 1,
  'User A can read only their own household');
select is((select count(*)::integer from public.household_members), 1,
  'User A can read only their own household membership');
select is((select count(*)::integer from public.subscriptions), 1,
  'User A can read only their own subscription');
select is((select count(*)::integer from public.household_app_access), 7,
  'User A can read only their household app access rows');
select is((select count(*)::integer from public.customer_onboarding), 1,
  'User A can read only their own onboarding status');
select is((select count(*)::integer from public.households
  where id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'), 0,
  'User A cannot read Household B');

-- User B: ensure the policies are symmetric and do not leak A's data.
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '22222222-2222-4222-8222-222222222222', true);

select is((select count(*)::integer from public.households), 1,
  'User B can read only their own household');
select is((select count(*)::integer from public.household_app_access), 7,
  'User B can read only their household app access rows');

select * from finish();
rollback;
