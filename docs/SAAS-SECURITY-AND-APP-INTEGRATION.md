# Customer Platform — Application Integration & Security Plan

Status: internal implementation note; no production changes authorized by this document.

## Product constraints

- Preserve the seven existing applications and their current behavior.
- Keep existing owner/family records in the legacy Supabase project untouched.
- Use the central customer platform for identity, household membership, plan/subscription state, and app entitlements.
- Every customer household must be isolated from every other household and from the original owner's private family records.
- The marketing site and customer portal are separate from the seven app repositories.
- Billing activation must be driven by verified Stripe webhooks, not by a browser redirect.

## Verified repository and database observations

| Repository | Observed application/data integration | Current status |
|---|---|---|
| `Pago-Cuidadoras` | Browser client uses legacy project `ywegbbdnphbbqiimqhqf`; reads/writes `public.kv_store` | Existing app; shared key/value store |
| `inventario-medicinas` | Browser client uses legacy project `ywegbbdnphbbqiimqhqf`; reads/writes `public.kv_store` | Existing app; shared key/value store |
| `Gastos-de-mama-admin` | Uses REST access to `public.movimientos` | Existing admin app |
| `Gastos-de-mama-original` | Uses REST access to `public.movimientos` | Existing caregiver app |
| `reporte-rosita` | Uses `public.reportes_aracely`; config references the legacy project | Existing report/dashboard/cognitive-session app |
| `Reporte-Diario-Rosita` | Older/smaller sibling repository; README describes the same reporting workflow | Relationship to current deployed version must be confirmed |
| `Gastos-de-mama-admin-optimizado` | Standalone compiled React artifact; app integration needs separate source/config inspection | Do not assume it is the deployed admin app |

The legacy database currently contains these populated tables: `movimientos` (194 rows), `kv_store` (9), `reportes` (1), `reportes_aracely` (118), and `sesiones_cognitivas` (8). These counts are observations from inspection, not migration targets.

The live app code and README files are not fully aligned: some reporting READMEs mention an older inactive Supabase project, while the inspected current app configuration points to the active legacy project. Treat executable app configuration as the stronger evidence, and verify each deployed URL before changing anything.

## Critical legacy security boundary

The legacy project has RLS enabled, but its current policies permit broad anonymous access:
- `kv_store`: public read/write.
- `movimientos`: anonymous read/insert/update/delete.
- `reportes`: public all operations.
- `reportes_aracely`: anonymous read/insert/update/delete.
- `sesiones_cognitivas`: anonymous read/insert/delete.

This is incompatible with a multi-customer SaaS. It is also the live database for the existing family apps. Do **not** revoke anonymous access, replace policies, move records, or change table structure in place as a shortcut; that could break the current apps or expose/alter personal records.

## Required integration design

1. Keep the central customer platform as the identity and entitlement authority.
2. Introduce customer data storage with explicit `household_id` ownership on every customer-owned record, or provision physically separate data stores where justified.
3. Enforce tenant boundaries in database policies using authenticated identity and trusted membership relationships. Never trust browser-supplied household IDs or user-editable user metadata as authorization.
4. Make each app resolve the signed-in user, active household membership, and app entitlement before reading or writing customer data.
5. Keep the owner's existing legacy data on its current path until a separately tested, reversible migration is explicitly approved.
6. Add negative cross-tenant tests: household A cannot read, update, delete, or infer household B's records; unauthenticated users cannot access customer data; a user without an app entitlement cannot access that app's data.
7. Keep public demo data synthetic and separate from both the owner's private data and customer production data.

## Billing and onboarding release gates

- Verify the Stripe test-mode price IDs and webhook signing secret from the connected Stripe account; never infer price IDs from their names.
- Test signup, email confirmation, login, password reset, onboarding idempotency, checkout, subscription updates, failed payment, cancellation, and billing portal.
- Persist and deduplicate Stripe event IDs so webhook retries are safe.
- Validate webhook event ordering and subscription-to-household association.
- Confirm that entitlement changes affect only the matching household.
- Configure Auth redirect allowlists and the portal return URL.
- Run static checks and end-to-end tests before changing the PR from draft.
- Do not deploy billing functions, activate live payments, merge the PR, or publish the portal until these gates pass.

## Immediate next engineering work

- Confirm all seven catalog app keys against actual repositories and deployed URLs.
- Inspect the full data/API/storage paths of each app, including the optimized admin artifact and the medical app.
- Build a tenant-aware compatibility layer and test fixture using synthetic household data.
- Add webhook idempotency and automated tests in the isolated feature branch.
