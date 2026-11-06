# Customer Tenant Data Architecture (Design Draft)

Status: design only. This document does not authorize or perform production migrations, deployments, data copies, or changes to the seven existing apps.

## 1. Non-negotiable isolation boundary

- A customer household is the tenant boundary.
- The authenticated Supabase user identity is the source of identity; browser-provided household IDs, PINs, query filters, and local storage are never authorization.
- Every customer-owned row must be scoped to a household and protected by database-enforced policies.
- App entitlement is checked independently from household membership. Membership alone does not grant every app.
- Service-role credentials remain server-side only.
- The existing family-care project and its records remain separate and unchanged.

## 2. Proposed customer data model

Use the central customer platform as the control plane for identity, households, membership, plans, subscriptions, and app entitlements. Customer operational data should live in a separate tenant-data schema or project, subject to a final compatibility and performance review.

Every tenant-owned operational table must include:
- `id`: stable primary key
- `household_id`: non-null foreign key to the tenant household
- `created_at` and `updated_at`
- domain-specific fields preserved from the current app model

Recommended logical domains (not yet migrations):
- `caregiver_payments` — caregiver pay periods, amounts, status, notes, receipt references
- `medicine_inventory` — medicines, dosage/stock thresholds, purchase and dispensing records
- `expense_transactions` — household income/expense movements and categories
- `care_reports` — daily caregiver reports and related observations
- `cognitive_sessions` — cognitive activity/session records
- `medical_records` — medical report entries and document references

Avoid a single opaque key/value blob for customer data. It weakens validation, querying, auditing, and per-record access control. If an app's existing data shape requires JSON for flexible fields, use JSON only for bounded domain-specific attributes inside a household-scoped row.

## 3. Authorization model

For every read/write request:
1. Verify the Supabase Auth JWT.
2. Resolve the user's active household membership on the server/database.
3. Verify the household has an active entitlement for the requested app.
4. Apply row-level security so the operation can affect only rows whose `household_id` belongs to the authenticated user.
5. For writes, derive or validate `household_id` server-side; never trust a client-supplied tenant identifier.

Required negative tests:
- unauthenticated user cannot read or write tenant data
- household A cannot select, insert into, update, or delete household B data
- a household member without the relevant app entitlement is denied app data access
- a removed member loses access immediately
- a disabled/canceled subscription loses app access according to the defined grace-period policy
- changing a request's household ID cannot cross the boundary
- service-role-only functions cannot be invoked by anon/authenticated clients

Policy implementation must be tested against real JWT roles and representative SQL/API calls. UI hiding is not a security test.

## 4. Storage and receipt files

- Store customer receipts and medical attachments in a private bucket.
- Use a canonical object key prefix such as `<household_id>/<app_key>/<object_id>`.
- Storage policies must verify the authenticated user's household membership and app entitlement for the household prefix.
- Do not rely on unguessable filenames or public bucket URLs.
- Prefer short-lived signed URLs issued only after authorization.
- Existing Google Drive links and the legacy `recibos` bucket must not be reused for customer data without a separate ownership, permission, and migration review.
- Verify upload, read, replacement, and deletion isolation across two synthetic households.

## 5. Mapping from existing apps

| App | Current legacy surface observed | Customer-side domain candidate | Additional review |
|---|---|---|---|
| Pagos | `kv_store` | `caregiver_payments` | shared settings/PIN, Google Drive receipt lookup |
| Inventario | `kv_store` | `medicine_inventory` | purchases, dispensing, settings/PIN |
| Gastos Admin | `movimientos`, Storage | `expense_transactions` | receipt object paths and signed URLs |
| Gastos Mamá | `movimientos`, Storage, localStorage | `expense_transactions` | browser-only state and receipt paths |
| Rosita | `reportes_aracely` | `care_reports` | caregiver identity and report ownership |
| Historial | `reportes_aracely` | `care_reports` | admin actions, delete/update permissions |
| Médico | `reportes_aracely` | `medical_records` | distinguish clinical data from daily care reports |

Related cognitive-session page currently uses `sesiones_cognitivas`; determine whether it belongs in the customer catalog and, if so, scope it as `cognitive_sessions`.

This mapping is a design hypothesis, not a finalized schema. Exact fields, relationships, constraints, indexes, and retention rules must be derived from full source and data-shape inspection before migration design.

## 6. Compatibility and rollout strategy

1. Build a separate test tenant-data environment using synthetic fixtures only.
2. Define schema and RLS policies from the inspected app data models.
3. Build a shared authenticated data-access layer for the seven apps; keep existing production URLs and legacy clients unchanged during development.
4. Add household context and entitlement checks to each app, starting with one low-risk app as a pilot.
5. Add automated integration tests for CRUD, membership changes, entitlement changes, and storage objects.
6. Run parallel tests with two synthetic households and prove cross-tenant denial.
7. Validate backups, restore, auditability, and rollback before any customer pilot.
8. Only after explicit release approval, deploy customer-specific changes. Never migrate the user's family records into the customer environment.

## 7. Known blockers before customer data

- Legacy project policies currently allow broad anonymous operations; do not change them in place because existing family apps depend on them.
- Client-side PINs are not authorization and must be replaced by Auth/RLS-backed roles for customer access.
- Confirm exact production URL/source version for each app and the authoritative version where duplicate repositories exist.
- Inspect every table/query, upload/download path, Google Drive integration, localStorage use, and any background automation.
- Define subscription grace-period and member-role rules.
- Verify central platform functions and tenant-data environment with automated tests before deployment.

## 8. Explicitly out of scope for this draft

- Applying SQL migrations to either live Supabase project
- Changing existing RLS policies or storage bucket permissions
- Copying, transforming, or exposing family-care data
- Deploying customer versions of the seven apps
- Enabling live Stripe payments or customer onboarding
- Merging the feature branch or publishing the portal
