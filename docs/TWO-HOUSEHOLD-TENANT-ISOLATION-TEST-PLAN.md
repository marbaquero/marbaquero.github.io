# Two-Household Tenant Isolation Test Plan

Status: test specification only. No test users, household rows, migrations, or production data were created by this document.

## 1. Preconditions

Do not run the integration suite against the legacy family-data project or the live customer platform.

Required isolated test environment:
- Dedicated Supabase project or disposable branch database
- No production credentials or copied family-care data
- Two synthetic Auth users: Tenant A owner and Tenant B owner
- Two synthetic households: Household A and Household B
- Separate test fixtures for each domain and private storage objects
- A third unauthenticated client
- A test user who is a household member but lacks the app entitlement being tested

Use synthetic names and values only (for example, "Demo Household A", "Demo Household B", "Sample medicine A").

## 2. Required test matrix

| Actor | Operation | Target | Expected |
|---|---|---|---|
| Anonymous | SELECT | Any tenant table | Denied / zero rows |
| Anonymous | INSERT | Any tenant table | Denied |
| Tenant A owner | SELECT | Household A rows | Allowed |
| Tenant A owner | SELECT | Household B rows | Zero rows |
| Tenant A owner | INSERT | Household A | Allowed only with valid app entitlement |
| Tenant A owner | INSERT | Household B by forged household_id | Denied |
| Tenant A owner | UPDATE | Household A rows | Allowed only with valid app entitlement |
| Tenant A owner | UPDATE | Household B rows | Zero affected rows / denied |
| Tenant A owner | DELETE | Household B rows | Zero affected rows / denied |
| Tenant B owner | SELECT | Household A rows | Zero rows |
| Tenant B owner | SELECT | Household B rows | Allowed |
| Member without app entitlement | SELECT/WRITE | That app's data | Denied |
| Removed household member | SELECT/WRITE | Former household | Denied after membership removal |
| Canceled/unpaid subscription | SELECT/WRITE | Entitled app data | Denied according to finalized grace-period rule |
| Tenant A owner | Read object | Household B receipt | Denied |
| Tenant A owner | Upload object | Household B prefix | Denied |
| Tenant A owner | Read object | Household A receipt | Allowed with authorization |
| Authenticated client | Invoke admin-only function | Any household | Denied |

Expected results must be asserted from the database/API response, not inferred from hidden UI controls.

## 3. Authorization contract to implement and verify

The final implementation must provide database-enforced equivalents of these checks:

- `is_household_member(household_id)`: true only when `auth.uid()` has an active membership for that household.
- `has_app_entitlement(household_id, app_key)`: true only when membership is active, the app access row is enabled, and the subscription status satisfies the finalized billing policy.
- `can_access_household_app(household_id, app_key)`: combines membership and entitlement checks.
- Every tenant table policy checks both the authenticated identity and the row's `household_id`.
- INSERT policies validate the new row's household and entitlement; clients cannot select a different household by submitting an arbitrary UUID.
- UPDATE policies enforce both USING and WITH CHECK so a row cannot be moved from one household to another.
- DELETE policies use the same household and entitlement boundary.

Function implementation details (SECURITY DEFINER vs invoker, search_path, grants, and recursion avoidance) must be reviewed with actual schema and RLS behavior before use. Do not copy a policy snippet into production without executing the negative tests.

## 4. Entitlement state policy decisions

The current central platform subscription statuses include `incomplete`, `trialing`, `active`, `past_due`, `canceled`, and `unpaid`. The product must explicitly decide which states allow access.

Recommended default for initial test design:
- `active`: allow
- `trialing`: allow only if trials are intentionally enabled
- `incomplete`: deny
- `canceled`: deny at the paid-through period end or at cancellation time, depending on the Stripe cancellation configuration
- `unpaid`: deny
- `past_due`: deny initially unless a documented grace period is approved

This is a policy proposal, not a live setting. Align webhook state mapping, app access rows, and customer-facing billing language before enabling payments.

## 5. Storage test requirements

Use a private bucket and synthetic files only. Validate:
1. Household A can upload under its own household/app prefix.
2. Household A cannot upload to Household B's prefix.
3. Household A cannot list, download, replace, or delete Household B's objects.
4. A signed URL is issued only after a server-side authorization check.
5. Expired signed URLs stop working.
6. Object metadata and filenames do not disclose another household's identity or medical information.

## 6. Test execution and release gates

- [ ] Dedicated test project exists and contains no production/family data.
- [ ] Schema and RLS policies are version-controlled and reviewed.
- [ ] Two-household CRUD isolation tests pass for every app domain.
- [ ] Entitlement denial tests pass for every app.
- [ ] Membership removal tests pass.
- [ ] Storage isolation tests pass.
- [ ] Webhook idempotency and subscription lifecycle tests pass in Stripe test mode.
- [ ] Restore test succeeds from a test backup.
- [ ] Security advisor reviewed; all material tenant-access findings resolved.
- [ ] A reviewer verifies that no legacy project or live customer data is involved.
- [ ] User explicitly approves production rollout separately.

## 7. Current blockers

The available central project is a control plane with households, members, subscriptions, and app access. It is not yet a proven tenant data plane. The inspected seven app sources still use the legacy family project and/or browser storage. There is no verified isolated tenant-data environment in which to run the matrix above.

Therefore the correct next implementation step is to provision or designate a separate test tenant-data environment, then derive schema and policies from the full app data models. Do not point the apps at the central control-plane tables as a shortcut, and do not retrofit the legacy family database for customer tenancy.
