# Central customer platform — security review

Review date: 2026-11-06
Project: `fftnffmttuzfftntzzhu`

## Current observations

- The only deployed Edge Function found is `complete-onboarding` (active, version 5, JWT verification enabled).
- Its request handler derives the user ID from verified request claims and calls `complete_customer_onboarding` through the admin client.
- The database RPC `complete_customer_onboarding` is SECURITY DEFINER, but its EXECUTE grant is limited to `postgres` and `service_role`. The public Edge Function is the intended authenticated entry point.
- The RPC validates the name and plan, requires an active plan and exactly seven active catalog apps, prevents a second owner household, and creates app-access rows disabled until billing is confirmed.

## Security advisor findings

1. `public.rls_auto_enable()` is SECURITY DEFINER and advisor reports it executable by anon/authenticated. It is an event-trigger helper, not an application API. The feature branch includes a migration revoking execute from PUBLIC, anon, and authenticated.
2. `public.create_household(text)` is SECURITY DEFINER and callable by authenticated users. It can create a household outside the plan-aware onboarding flow. The feature branch includes a migration revoking public-client execute; the portal uses `complete-onboarding` instead.
3. `public.is_household_member(uuid)` and `public.is_household_owner(uuid)` are SECURITY DEFINER and callable by authenticated users. Their definitions check `auth.uid()` and return only membership predicates. They remain available because RLS policies use these helper functions.
4. Supabase Auth leaked-password protection is disabled. Enable it in the Auth security settings before production launch.
5. Performance advisor reports missing indexes on four foreign-key columns: `household_app_access.app_key`, `household_members.user_id`, `households.created_by`, and `subscriptions.household_id`. These are performance improvements, not a reason to bypass tenant security.

## Feature-branch changes not yet applied

- `supabase/migrations/202611060001_stripe_webhook_event_ledger.sql` creates a private Stripe webhook event ledger. It has not been applied; the table was verified absent from the live project.
- `supabase/migrations/202611060002_restrict_security_definer_grants.sql` revokes execution from the two functions identified above. It has not been applied.
- The Stripe webhook source records successfully processed event IDs and uses subscription lifecycle events as the authority for subscription status. It has not been deployed.
- The onboarding Edge Function source has been copied into the repository for version control; the live function has not been replaced.

## Release gate

Apply these migrations only in a reviewed test environment first, run the security advisor again, and test signup/onboarding plus tenant isolation. Do not apply to the live project, deploy payment functions, or enable live billing as part of this source-only review.
