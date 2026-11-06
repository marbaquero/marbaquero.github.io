# Accelerated Customer Launch — MVP Scope

Status: execution plan for the customer-platform feature branch. This document narrows the first release; it does not authorize production deployment, a PR merge, live Stripe activation, or changes to the existing family-care applications.

## Target

Target a first controlled customer pilot in approximately **6–10 working days**, subject to the external Stripe/Supabase configuration and successful testing. This is an accelerated target, not a guarantee.

## Release 1: customer-ready MVP

Release 1 will include only what is necessary to onboard and serve the first household safely:

1. **Customer portal**
   - English and Spanish sign-up, sign-in, password reset, and session restoration.
   - Household creation/onboarding after verified email sign-in.
   - Clear account and subscription status.
2. **Billing**
   - Stripe test-mode checkout for the Family Plan ($29/month) and Full Setup ($99 one-time + $49/month).
   - Billing portal and webhook lifecycle verification.
   - No live charges until a separate explicit approval.
3. **One integrated application: Inventario**
   - Customer-specific data plane, not the legacy family-care project.
   - Authenticated access, household membership, app entitlement, and database-enforced tenant isolation.
   - Medicine catalogue, purchase history, dispensing, refills, adjustments, and stock snapshot, preserving the current app's observed behavior.
   - Two synthetic households for positive and negative CRUD tests.
4. **Release controls**
   - Verified Auth redirect URLs and app launch URL.
   - Backup/restore and rollback procedure for the pilot environment.
   - Manual acceptance test in both languages.

## Deferred to Release 2

The following are intentionally excluded from the first pilot and remain on the roadmap:
- Pagos
- Gastos Admin and Gastos Mamá (together because they share transaction/receipt behavior)
- Rosita, Historial, and Médico (shared care-report data; medical-record scope needs separate confirmation)
- Cognitive Sessions (not one of the seven catalog apps)

The existing seven apps remain available in their current environment. Release 1 does not replace, migrate, or modify them.

## Work sequence

| Workstream | Exit condition |
|---|---|
| 1. Close architecture decisions | Select customer data-plane environment and confirm Auth/JWT membership resolution |
| 2. Prepare pilot data plane | Isolated test environment, schema, RLS, indexes, private storage decision |
| 3. Integrate Inventario | All required CRUD paths use authenticated household-scoped access |
| 4. Prove isolation | Household A cannot read/write Household B; unauthenticated and unentitled requests fail |
| 5. Verify billing | Test checkout, webhook delivery/idempotency, subscription changes, cancellation and portal |
| 6. Pilot acceptance | English/Spanish flows, app launch, backup/restore and rollback checks pass |

## Time-saving rules

- Stop adding planning documents unless they resolve a real implementation blocker.
- Do not integrate all seven apps before the first pilot; complete one vertical slice end to end.
- Reuse the existing portal, customer control-plane schema, CI workflow, and tenant-isolation test harness where appropriate.
- Batch related code changes and run CI after each coherent implementation milestone.
- Use synthetic fixtures only. Do not copy personal or family-care data into the pilot.

## Non-negotiable safety boundaries

- Do not modify the legacy family-care or medical Supabase projects.
- Do not change the existing apps' production endpoints, policies, or data.
- Do not apply experimental migrations to the live customer control-plane project.
- Do not expose service-role or Stripe secret keys in browser code.
- Do not merge to `main`, deploy Edge Functions, or activate live Stripe payments without explicit release approval.

## Definition of first-pilot complete

The first pilot is complete only when a new customer can register, confirm email, complete household onboarding, complete a Stripe test-mode purchase, see the correct entitlement, launch Inventario, and perform the supported inventory operations while a second synthetic household is demonstrably unable to access that data.
