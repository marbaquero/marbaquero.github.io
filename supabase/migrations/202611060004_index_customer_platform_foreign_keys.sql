-- Add covering indexes for the four foreign keys flagged by Supabase's
-- performance advisor. These indexes do not change application data or RLS.

create index if not exists household_app_access_app_key_idx
  on public.household_app_access (app_key);

create index if not exists household_members_user_id_idx
  on public.household_members (user_id);

create index if not exists households_created_by_idx
  on public.households (created_by);

create index if not exists subscriptions_household_id_idx
  on public.subscriptions (household_id);
