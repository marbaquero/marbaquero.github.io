# Customer Tenant Data Model — Proposed v1

Status: design proposal only. This is not a migration and must not be applied to a live Supabase project. It uses synthetic/customer-side concepts only; no family-care data is copied or changed.

## 1. Architecture decision

Keep two distinct layers:

- **Control plane:** the existing Marcello Elite customer platform owns Auth identities, households, household membership, plans, subscriptions, and per-app access.
- **Customer data plane:** a separately designated schema/project owns operational records. It must be tenant-scoped and independently tested. Do not point customer-facing apps at the legacy family-care project.

The authenticated user's identity is resolved from the Supabase JWT. The active household is resolved from membership, not accepted as an authorization fact from browser storage or a URL parameter. Each operation must also verify the app entitlement.

## 2. Shared conventions

Every customer-owned table should have:
- `id` UUID primary key (or a stable domain key where compatibility requires it)
- `household_id` UUID, NOT NULL
- `created_at` and `updated_at` timestamps
- optional `created_by` / `updated_by` UUID references to Auth users where audit value exists

Recommended constraints:
- foreign keys include household context where needed, so a child row cannot reference a parent from another household
- indexes start with `household_id`, followed by common filter/order columns
- update policies include both `USING` and `WITH CHECK`
- SELECT policies are present for UPDATE paths
- tenant data is inaccessible to anon; authenticated access requires active household membership AND the relevant app entitlement
- no client-side PIN or user-editable metadata is an authorization source

Do not create one generic key/value table for all app data. Use relational tables for entities and history; bounded JSON may remain for truly flexible form fields after review.

## 3. Proposed domains and tables

### A. Pagos — caregiver payment management

| Table | Important columns | Purpose |
|---|---|---|
| `caregivers` | `household_id`, `display_name`, `role_label`, `schedule_type`, `weekly_rate`, `active`, `sort_order` | Household's caregiver roster and configurable defaults |
| `caregiver_payment_periods` | `household_id`, `caregiver_id`, `period_start`, `period_end`, `year`, `month`, `week_number`, `amount`, `payment_method`, `status`, `receipt_file_id` | One expected/actual payment per caregiver period |
| `household_app_settings` | `household_id`, `app_key`, `settings_json` | Non-secret display and workflow preferences only |

The current payment source has caregiver records, weekly/weekend period generation, amount, payment method, status, and a receipt/comprobante field. Preserve period boundaries and caregiver linkage. Do not migrate the existing `adminPin` value; replace the PIN gate with Auth membership/roles and database authorization. Receipt search currently involves a Google Apps Script/Drive flow; customer receipts need a private customer-owned storage flow unless Drive access is separately designed and verified.

### B. Inventario — medicine inventory

| Table | Important columns | Purpose |
|---|---|---|
| `medicines` | `household_id`, `name`, `dose`, `brand`, `stock_quantity`, `minimum_threshold`, `daily_dose`, `unit`, `unit_cost`, `active` | Current medicine catalogue and stock snapshot |
| `medicine_purchases` | `household_id`, `purchase_date`, `pharmacy`, `receipt_reference`, `receipt_file_id`, `notes` | Purchase header |
| `medicine_purchase_items` | `household_id`, `purchase_id`, `medicine_id` nullable, `item_name_snapshot`, `quantity`, `subtotal` | Purchased products and historical item labels |
| `medicine_dispensing_events` | `household_id`, `medicine_id`, `event_date`, `quantity`, `notes` | Medicine use/dispensing history |
| `medicine_refill_events` | `household_id`, `medicine_id`, `event_date`, `quantity_added`, `unit_cost`, `notes` | Stock replenishment history |
| `medicine_stock_adjustments` | `household_id`, `medicine_id`, `adjusted_at`, `quantity_delta`, `reason`, `notes` | Auditable manual corrections |

The current source has separate `medications`, `purchases`, `dispensing`, `fills`, and `adjustments` collections. Purchase items can be linked to medicines by `medId`, but legacy items may only have a name; keep an item-name snapshot and allow a nullable link. Current stock can be maintained as a snapshot, but every stock-changing operation should create a corresponding event so balances can be reconciled. Exact fields and quantity semantics need full source review before implementation.

### C. Gastos Admin / Gastos Mamá — household finances

| Table | Important columns | Purpose |
|---|---|---|
| `expense_transactions` | `household_id`, `transaction_date`, `transaction_type`, `amount`, `description`, `recorded_by_label`, `created_by`, `updated_by` | Income/deposit and expense movements |
| `receipt_files` | `household_id`, `app_key`, `storage_path`, `original_filename`, `mime_type`, `size_bytes`, `uploaded_by`, `created_at` | Private receipt metadata linked to storage |
| `expense_transaction_receipts` | `household_id`, `transaction_id`, `receipt_file_id`, `sort_order` | Explicit receipt-to-transaction association |

Use a decimal/numeric currency amount, positive amount plus an explicit transaction type, and a household-scoped foreign key. The current source supports create, edit, delete, monthly filtering/reporting, deposits, expenses, and receipt movement/reassignment. The admin and original expense apps share the legacy `movimientos` table; they should share one customer-side transaction domain, not two competing schemas.

Receipt bytes belong in a private bucket. A path is not proof of access. Storage policies and signed-URL issuance must enforce household membership and app entitlement. Reassigning a receipt should update the association transactionally; it should not copy or expose another household's object.

### D. Rosita / Historial / Médico — care and health reporting

| Table | Important columns | Purpose |
|---|---|---|
| `caregivers` | shared roster from Pagos | Consistent caregiver identity within a household |
| `care_reports` | `household_id`, `caregiver_id` nullable, `caregiver_name_snapshot`, `report_date`, `shift_type`, `general_state`, `breakfast`, `lunch`, `snack`, `hydration`, `medication_observations`, `blood_pressure`, `activities`, `home_condition`, `observations`, `bedtime`, `sleep_quality`, `night_wakeups`, `wake_reasons`, `night_bathroom`, `morning_condition` | Structured daily caregiver report |
| `medical_records` | `household_id`, `record_date`, `record_type`, `title`, `clinical_notes`, `provider_label`, `attachment_file_id` | Explicit clinical records/attachments, only if the product truly collects them |

The current Rosita form inserts structured daily-care fields into `reportes_aracely`. Historial reads, edits, and deletes those reports. Médico currently reads the same report table and presents a medical/reporting view. That does not mean daily caregiver observations are equivalent to formal medical records. Keep the source daily report intact in `care_reports`; add a separate `medical_records` domain only after the product scope and field ownership are confirmed. Do not silently copy all caregiver observations into a clinical record table.

Array-like selections (general state, medication observations, activities, home condition, wake reasons) can be PostgreSQL text arrays or normalized child rows; choose after confirming query/filter requirements and exact values. Retain the original caregiver label as a snapshot when linked to a roster record so historical reports remain readable after a caregiver is renamed or deactivated.

### E. Cognitive sessions — separate scope decision

The `sesion-cognitiva.html` page currently reads/writes `sesiones_cognitivas` and is not in the seven-app catalog. If included in a customer package later, use a separate `cognitive_sessions` table with `household_id`, caregiver reference/snapshot, session date/time, duration, activities, mood, participation, hand observations, notes, and materials. Do not silently expose it as an eighth catalog app.

## 4. Relationships and tenant integrity

- `caregivers` is shared by Pagos and care reports inside the same household.
- `caregiver_payment_periods.caregiver_id` must resolve to a caregiver in the same household.
- Purchase items, dispensing events, refills, and adjustments must resolve to medicines in the same household.
- Receipt associations must ensure both the transaction and receipt metadata belong to the same household.
- Any reference to a parent row should use a composite uniqueness/foreign-key pattern where necessary, such as `(household_id, id)`, to prevent cross-household references.
- Historical snapshots preserve labels/rates/amounts at the time of the transaction/report where later edits should not rewrite history.

## 5. Access and storage rules

For every app domain:
1. Require a real authenticated Supabase user.
2. Resolve active household membership from the control plane.
3. Verify that the household's app entitlement is active under the approved billing policy.
4. Enforce tenant filtering in RLS on every table and private Storage object.
5. Enforce same-household parent/child relationships at the database level.
6. Test anonymous denial, forged household IDs, cross-household CRUD, member removal, entitlement revocation, and Storage read/write/list/delete.

Do not trust browser-supplied household IDs, hidden buttons, PINs, `localStorage`, `sessionStorage`, or user-editable `user_metadata` as authorization. Do not expose service-role keys in app code. For Supabase Storage upsert, validate the required INSERT, SELECT, and UPDATE permissions/policies, not only upload.

## 6. Pilot sequence

Recommended first pilot: **Inventario** as a data-plane proof of concept, not an immediate customer release. It has separable domain collections and no receipt-storage integration in the inspected main page, so it provides a contained CRUD/relationship/RLS exercise. Before choosing it finally, inspect the entire source and verify all its secondary pages and data paths.

After the pilot passes two-household tests, implement the shared access layer and migrate one app at a time in this order:
1. Inventario
2. Pagos (after replacing Drive receipt lookup and PIN handling)
3. Gastos Admin and Gastos Mamá together (shared transactions and private receipts)
4. Rosita, Historial, and Médico (shared care reports; clinical data scope explicitly separated)

The order is a proposal only. Keep the seven existing production apps pointed at their current legacy environment until customer versions are separately tested and approved.

## 7. Decisions still required before SQL implementation

- Designate and provision a separate tenant-data test project/schema; do not use the live control-plane or legacy family-care projects for experimental tables.
- Confirm whether tenant data belongs in a second Supabase project or a non-exposed schema within the customer project. Compare operational separation, Auth identity validation, performance, backup/restore, and admin burden.
- Finalize owner/member roles, invitations, and member removal behavior.
- Define subscription grace-period rules and exactly which subscription statuses grant each app.
- Confirm whether caregiver roster should be shared between Pagos and reporting apps.
- Confirm the intended product scope of Médico: daily care summary, formal clinical record, or both.
- Confirm whether Cognitive Sessions is excluded from the seven-app package or a later add-on.
- Inspect all remaining source files, nested JSON shapes, upload scripts, and data update flows before designing exact DDL.

## 8. Explicit non-actions

This document does not:
- create or apply SQL migrations
- change live Supabase schemas, RLS, Auth, Storage, or Edge Functions
- modify any of the seven existing apps
- copy family-care records, files, or credentials
- deploy customer versions or activate payments
- merge the feature branch or publish the portal
