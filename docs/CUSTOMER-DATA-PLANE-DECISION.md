# Architecture Decision Record: Customer Data Plane for the First Pilot

**Status:** Accepted for the first pilot; production implementation still requires explicit release approval  
**Date:** 2026-11-06  
**Scope:** Customer-facing Inventario pilot only

## Decision

Use the existing **customer-platform Supabase project** for the first pilot, but keep Inventario customer records in a dedicated, non-exposed PostgreSQL schema. Expose a small, explicit API schema containing only the approved RPC functions. Do not create another Supabase project for this pilot.

This is a logical data-plane boundary inside the customer SaaS project, not a claim of physical project-level isolation. Reassess a separate Supabase project when customer volume, compliance requirements, operational capacity, or backup/restore needs justify the additional cost and complexity.

## Why this is the right first-pilot trade-off

- The customer platform already owns Auth, households, memberships, subscriptions, and app entitlements. Reusing the same project avoids duplicating identity and entitlement synchronization.
- A new project introduces additional cost, another set of credentials and secrets, separate backups/monitoring, and a cross-project identity/authorization bridge.
- A private data schema plus a deliberately small exposed API schema keeps customer business tables out of the PostgREST-exposed schema surface.
- Tenant isolation remains enforced by database grants, row-level security, household-aware foreign keys, membership checks, and app-entitlement checks. A schema name alone is not a security boundary.

## Proposed schema boundaries

| Schema | Purpose | Data API exposure |
|---|---|---|
| public | Existing customer identity, household, membership, subscription, plan, and app-catalog tables | Existing configuration; do not broaden casually |
| customer_data | Inventario medicines, purchases, dispensing, fills, adjustments, and audit records | **Not exposed** |
| customer_api | Narrow RPC surface for customer Inventario operations | Exposed only after explicit configuration and review |

The actual schema names and grants must be checked against the live project before any migration is proposed for release. Do not assume the current Data API exposed-schema configuration.

## Authorization contract

Every customer API operation must:

1. Require a genuinely authenticated user (auth.uid() is not null).
2. Resolve the household from trusted membership records; never trust a household ID supplied by the browser as proof of access.
3. Verify active household membership.
4. Verify the household has active Inventario entitlement.
5. Apply household-scoped RLS and composite household-aware foreign keys.
6. Reject cross-household references even when a caller forges valid UUIDs from another household.
7. Deny anonymous access and deny access after membership or entitlement is removed, subject to the documented token/session revocation model.

Never use user-editable raw_user_meta_data as an authorization source. Subscription and entitlement decisions must come from trusted database records, not browser state.

## RPC and transaction design

- Expose only specific functions needed by the UI, such as listing/creating/updating medicines, recording a purchase, dispensing, recording a pillbox fill, and applying a physical-count adjustment.
- Prefer SECURITY INVOKER functions with explicit grants and RLS on underlying tables.
- Fully qualify object names; use a controlled search_path where applicable.
- Do not add broad SECURITY DEFINER functions to the exposed API. If a privileged function is proven necessary, isolate it in a non-exposed schema, validate auth.uid() and household membership inside it, minimize its owner privileges, and restrict EXECUTE grants.
- Stock changes and their corresponding history rows must commit in one PostgreSQL transaction. Do not repeat the legacy app's multiple independent JSON writes.
- Define and test insufficient-stock behavior, numeric precision, units, and purchase stock-application behavior before implementing the UI.

## Data separation and migration boundary

- Do not connect the customer pilot to the legacy family-care project or medical project.
- Do not copy personal medication records, caregiver records, reports, or any other family data into the customer platform.
- Start each synthetic test household with empty customer data. No legacy seed data.
- Do not use the legacy client-side admin PIN as authorization or as a customer role.
- Do not change existing personal applications or their production Supabase configuration.

## Required verification before pilot release

- Anonymous requests cannot read or mutate customer data.
- Authenticated user without household membership cannot access it.
- Household A cannot read, update, delete, or reference Household B records.
- A household without Inventario entitlement cannot call the API.
- Removing membership or entitlement blocks subsequent operations.
- Forged cross-household foreign keys are rejected.
- Concurrent dispensing cannot create negative stock or mismatched history.
- Purchase, dispense, fill, and adjustment operations are atomic under injected failure.
- Backup and restore of customer data are tested independently from personal systems.
- The test suite uses at least two synthetic households and never production family data.

## Operational and platform notes

- Supabase's Data API uses both PostgreSQL grants and RLS. RLS does not replace object grants, and grants do not replace row policies.
- Custom schemas can be exposed through API settings, but this design deliberately keeps customer_data unexposed and exposes only the RPC schema.
- Supabase announced that new public tables are no longer automatically exposed by default, with enforcement on existing projects from 2026-10-30. Explicitly inspect the project's current API settings and grants rather than relying on defaults.
- Supabase CLI v3 changed hosted-command defaults to local-first and requires explicit hosted targeting/confirmation. Pin and inspect the CLI version in CI; never assume a CLI command targets the intended database.

## Revisit this decision when

- A separate customer data project becomes affordable and operationally supportable.
- Regulatory or contractual isolation requirements demand project-level separation.
- Customer data volume, recovery objectives, or backup retention require an independent lifecycle.
- The platform adds multiple customer apps with distinct data-plane scaling or availability needs.

## Approval boundary

This ADR is documentation and design only. It does not create schemas, alter grants or RLS, change API settings, deploy functions, create projects, or touch production data. Those actions remain gated by the existing release approval boundary.

## Read-only verification of the customer platform (2026-11-06)

The existing customer project was inspected read-only before implementation. No SQL, grants, RLS, Auth settings, or Edge Functions were changed.

- Project: `fftnffmttuzfftntzzhu`, region `us-east-1`, PostgreSQL 17.11, status healthy.
- The seven existing customer-platform tables are present and RLS-enabled: `customer_profiles`, `households`, `household_members`, `subscriptions`, `app_catalog`, `household_app_access`, and `customer_onboarding`, plus `subscription_plans`.
- The project has one customer profile record and no household, membership, subscription, household-app-access, or onboarding records. The app catalog has seven rows.
- The migration-history listing returned no recorded migrations even though the schema already exists. Treat this as schema/migration drift: do not run the branch's clean-install baseline against this hosted project or assume migration history accurately describes its live schema.
- Security Advisor currently reports four callable SECURITY DEFINER functions: `public.rls_auto_enable()` is callable by anon and authenticated; `public.create_household(text)`, `public.is_household_member(uuid)`, and `public.is_household_owner(uuid)` are callable by authenticated. It also reports leaked-password protection disabled.
- Performance Advisor reports four unindexed foreign keys in the customer-platform tables: `household_app_access.app_key`, `household_members.user_id`, `households.created_by`, and `subscriptions.household_id`.

These findings are not authorization to change the live project. In particular, do not revoke existing function privileges or alter the Auth setting as part of Inventario work without a separately reviewed migration and explicit approval. New Inventario work must avoid adding another exposed SECURITY DEFINER endpoint. The current GitHub validation workflow uses pinned Supabase CLI `2.84.2` and a disposable local Supabase stack; keep that workflow isolated from hosted projects while developing.
