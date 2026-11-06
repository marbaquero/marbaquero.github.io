# Production upgrade runbook — central customer platform

Review date: 2026-11-06  
Project ref: `fftnffmttuzfftntzzhu`  
Feature branch: `customer-portal-auth`

## Release decision

**Do not apply the clean-install baseline to the existing hosted project.** The hosted project already contains the seven customer-platform tables, policies, functions, trigger, seven application catalog rows, and two plan rows. The hosted migration registry currently reports zero migrations. This is a migration-adoption problem, not an empty-database problem.

No production changes are authorized by this runbook. It is a preparation and release-control document.

## Verified live state

- Tables present: `customer_profiles`, `households`, `household_members`, `subscription_plans`, `subscriptions`, `app_catalog`, `household_app_access`, `customer_onboarding`.
- All eight tables have RLS enabled (verified in the prior security review).
- Rows: 1 customer profile; 0 households; 0 household members; 0 subscriptions; 0 household app-access rows; 0 onboarding rows; 7 app-catalog rows; 2 plan rows.
- Constraints and primary/unique keys match the feature-branch baseline for these tables.
- Existing RLS policy set: 11 policies, matching the baseline policy names and intended access model.
- Existing `complete_customer_onboarding(uuid,text,text,text,text)` is executable only by `postgres` and `service_role`.
- `create_household(text)` remains executable by `authenticated`; `rls_auto_enable()` has default/public execution according to the advisor. These are hardening items.
- `is_household_member(uuid)` and `is_household_owner(uuid)` are SECURITY DEFINER helpers used by RLS policies. Do not revoke them casually; first redesign policies to avoid breaking tenant isolation.
- Performance advisor identified four missing FK indexes: `household_app_access(app_key)`, `household_members(user_id)`, `households(created_by)`, and `subscriptions(household_id)`.
- Security advisor also reports Supabase Auth leaked-password protection disabled.
- The Stripe webhook event ledger table does not exist yet.

## Why the baseline must not be run against production

`202611050001_customer_platform_baseline.sql` creates the existing tables, trigger, functions, policies, catalog fixtures, and plans. It is intended for a clean disposable database and for CI. Running it against the populated hosted database would collide with existing objects and could partially apply depending on transaction handling. It is not an upgrade migration.

## Required migration-history adoption procedure

1. Take and verify a fresh database backup before any production work.
2. In a controlled local working copy linked to the central customer-platform project, use the current Supabase CLI's documented existing-project workflow: pull the remote schema into a baseline migration. The current Supabase guide states that `supabase db pull` creates the baseline migration and records it as already applied in `supabase_migrations.schema_migrations`.
3. Inspect the generated baseline carefully. Remove secrets and all production customer data from any committed artifacts. Do not replace the clean-install baseline used by CI unless CI is deliberately migrated to the new baseline architecture.
4. Reconcile the repository's migration chain so that the hosted baseline is recorded as already applied, while disposable CI still has a deterministic clean-install path. Do not manually fabricate migration-history rows or mark the clean-install baseline as applied without verifying its exact equivalence to the hosted schema.
5. Run the full migration chain against a disposable database restored from a schema-only snapshot or a structurally equivalent test fixture. Verify every migration and rerun RLS tenant-isolation tests.
6. Preview the exact remote migration plan. Confirm it contains only the approved additive/hardening changes and no table recreation, data deletion, broad grants, or unexpected drops.
7. Apply production migrations only after an explicit release approval and verified backup.

## Candidate additive/hardening changes to validate

- Create the private `stripe_webhook_events` idempotency ledger with RLS enabled, no anon/authenticated access, and service-role-only grants.
- Revoke client execution of `public.create_household(text)` and `public.rls_auto_enable()` while preserving the event trigger's ability to invoke its trigger function.
- Keep `complete_customer_onboarding` restricted to `service_role`.
- Add the four missing FK indexes using `CREATE INDEX IF NOT EXISTS`.
- Review the two SECURITY DEFINER membership helper functions. Their direct RPC exposure should be removed only after replacing policy calls with a safe design that preserves caller-scoped membership checks and passing tenant-isolation tests.
- Enable leaked-password protection in Supabase Auth settings after reviewing its impact on signup/password flows.

## Release gates still outstanding

- Confirm Stripe test-mode Price IDs match the intended $29/month Family Plan and $49/month Full Setup subscription. The $99 Full Setup fee must remain a one-time setup charge, not be confused with the recurring price.
- Test checkout, cancellation, failed payment, renewal, duplicate webhook delivery, and recovery from webhook processing failure in Stripe test mode.
- Verify Auth signup, login, logout, session restoration, email confirmation, and password reset with the production redirect URLs.
- Confirm all seven app links and access checks work for two separate test households. Use synthetic test data only.
- Re-run Supabase security and performance advisors after hardening.
- Confirm the live Edge Function inventory and source/version match the reviewed branch before any deployment.

## Explicit exclusions

This procedure does not authorize merging PR #3, deploying Edge Functions, changing live database grants/policies, changing Auth settings, activating Stripe live payments, or modifying either legacy family-care Supabase project. Those actions require a separate release approval.
