# Marcello Elite / Cuidar a Distancia — final release checklist

Last checked: 2026-11-06  
Repository: `marbaquero/marbaquero.github.io`  
Working branch: `customer-portal-auth`  
Pull request: #3 (draft)

This checklist defines what “wrapped up” means. A successful CI run validates the portal source and isolated control-plane tenant policies; it does not mean the complete SaaS is ready to accept paying customers.

## Completed on the feature branch

- [x] Bilingual English/Spanish customer portal source.
- [x] Email/password signup, login, password reset, and session restoration source.
- [x] Household onboarding routed through the authenticated Edge Function.
- [x] Family Plan displayed at $29/month.
- [x] Full Setup displayed at $99 one-time plus $49/month.
- [x] Server-side source for Stripe Checkout and Billing Portal.
- [x] Stripe webhook signature verification and event ledger source.
- [x] Subscription lifecycle controls app entitlement; checkout redirect alone does not.
- [x] Clean-install baseline and incremental SQL migrations for disposable test environments.
- [x] Automated tenant-isolation tests with 29 assertions.
- [x] Production database upgrade runbook.
- [x] Security and seven-app integration architecture notes.
- [x] Latest GitHub Actions run #35 passed both jobs: portal/security validation and isolated Supabase migration + tenant-isolation test.

## Blocking before a customer-facing production launch

### A. Central Supabase database
- [ ] Establish an accurate remote schema baseline and migration history. The live project has the platform schema already, but its migration list currently reports zero entries.
- [ ] Test an upgrade path against a disposable database that faithfully represents the current hosted schema; do not apply the clean-install baseline to the live database.
- [ ] Apply reviewed additive hardening migrations only after backup verification and explicit release approval.
- [ ] Re-run security/performance advisors after changes.
- [ ] Enable leaked-password protection in Auth and test signup/reset behavior.

### B. Stripe test mode
- [ ] Verify the actual three Stripe test Price IDs: Family monthly, Full Setup monthly, Full Setup one-time fee.
- [ ] Configure Edge Function secrets securely (never commit secrets).
- [ ] Deploy the three payment functions to a non-live/test environment.
- [ ] Verify webhook endpoint and signing secret.
- [ ] Execute end-to-end tests: successful checkout, canceled checkout, initial payment failure, renewal, past-due, cancellation, duplicate webhook delivery, retry after a failed webhook.
- [ ] Confirm entitlements are enabled/disabled only by verified subscription lifecycle events.
- [ ] Verify customer billing portal session and return URL.

### C. Authentication and portal
- [ ] Configure the exact final portal URL in Supabase Auth redirect allowlist.
- [ ] Test email confirmation, login, logout, restored session, password reset, and expired session.
- [ ] Test both languages on desktop and mobile.
- [ ] Add verified destination links for all seven applications to the portal. Current portal code displays application names and entitlement status, but the current `app_catalog` schema has no destination URL field, so the portal does not yet provide actual app launch links.

### D. Seven existing applications — major remaining integration
- [ ] Confirm the canonical deployed source and URL for each of the seven apps.
- [ ] Build a customer-safe data plane and household-scoped schema/RLS. The existing family-care database is not a SaaS tenant database and currently has broad anonymous policies used by the owner's existing apps.
- [ ] Add shared Supabase Auth session handling to each customer-facing app.
- [ ] Enforce household membership and per-app entitlement in database policies, not just in the UI.
- [ ] Keep the owner's existing family-care data, projects, and current app behavior isolated and unchanged.
- [ ] Test two synthetic households across all seven apps, including reads, inserts, updates, deletes, file access, and entitlement revocation.
- [ ] Verify backups and restore before the first customer pilot.

## Final acceptance criteria

The release is ready only when:
1. All four sections above have passed their applicable tests.
2. Two independent synthetic households cannot access each other's records or files in any of the seven apps.
3. Billing and entitlement transitions pass Stripe test-mode end-to-end tests.
4. The final portal provides working links to all seven apps.
5. The hosted database migration plan is reviewed, backed up, and applied under explicit approval.
6. A final production checklist confirms no family-care data was copied or exposed.

## Change-control boundary

Until separately approved:
- Keep PR #3 on the feature branch and in draft.
- Do not merge to `main`.
- Do not apply SQL migrations or alter live RLS/Auth settings.
- Do not deploy/replace live Edge Functions.
- Do not activate Stripe live payments.
- Do not change either legacy family-care Supabase project or its data.
