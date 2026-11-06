# Inventario Customer Pilot — Source-Derived Integration Specification

Status: implementation specification for the customer pilot. Derived from read-only inspection of `marbaquero/inventario-medicinas` on `main`. It does not modify that repository or any Supabase project.

## 1. Current application behavior

The current app is a single-page HTML application with four views: Dashboard, Inventario, Compras, and Pastillero. It reads and writes six JSON collections in the legacy `kv_store` table:

- `medications`
- `purchases`
- `dispensing`
- `fills`
- `settings`
- `adjustments`

On first load it seeds missing medications and purchases from hard-coded defaults, then persists them. Customer onboarding must not reuse these personal seed records. A new household should start empty or use a clearly labeled, customer-neutral starter catalogue.

The existing client has an administrator PIN stored in `settings.adminPin`. This is only a browser-side UI gate and is not authorization. Customer version must use Supabase Auth, household membership/role, app entitlement, and RLS. Do not migrate the PIN.

## 2. Observed data contracts

### Medicines

Observed fields:
- `id`
- `name`
- `dose`
- `brand`
- `stock`
- `minThreshold`
- `dailyDose`
- `unit`
- `pricePerPill`

The app uses medicine ID references in dispensing, refill/fill and adjustment entries. It calculates low-stock state from zero stock, the minimum threshold, and a 10-day supply warning. It calculates days of supply from stock and daily dose.

### Purchases

Observed purchase header fields:
- `id`
- `date`
- `pharmacy`
- `receiptRef`
- `items`
- `total`
- `saved`
- `stockApplied` (used by delete/reversal behavior when present)

Observed purchase item fields:
- `name`
- `qty`
- `subtotal`
- optional `medId`

Older items may have only a name. On load, the current app attempts to match those names to medicines using normalized medicine/brand names and dose digits. Preserve the item-name snapshot and allow a nullable medicine link for unmatched historical items.

Purchase creation can add quantities to stock when selected. Purchase price updates set a medicine's `pricePerPill` to item subtotal divided by quantity. The app comments that purchase records may be historical/price-only; the explicit `stockApplied` behavior must be retained so deletion can reverse only stock actually added.

### Dispensing

Observed fields:
- `id`
- `date`
- `medId`
- `medName` (snapshot)
- `qty`
- `by` (optional caregiver label)

Dispensing creates a history event and decreases stock, clamped at zero in the current UI implementation.

### Weekly fills

Observed fill header fields:
- `id`
- `date`
- `by`
- `items`
- `stockApplied`

Observed fill item fields:
- `medId`
- `medName` (snapshot)
- `qty`

A fill can include many medicines. The form defaults quantities to daily dose × 7. Stock deduction is optional. Editing a fill reverses its previous deduction before optionally applying the new quantities; deleting a fill restores quantities only if that fill had applied stock.

### Stock adjustments

Observed adjustment header fields:
- `id`
- `date`
- `by`
- `changes`

Observed adjustment change fields:
- `medId`
- `medName` (snapshot)
- `before`
- `after`

Physical count replaces the stock snapshot with the counted amount and records only medicines whose count changed.

### Settings

Observed `settings` stores `adminPin`. Do not migrate this secret or use it as a role. Customer preferences may be stored separately only after excluding authentication or authorization material.

## 3. Recommended customer data model

Use household-scoped relational tables rather than one customer-facing JSON key/value collection:

- `medicines`: household_id, id, name, dose, brand, stock_quantity, minimum_threshold, daily_dose, unit, unit_cost, active, timestamps.
- `medicine_purchases`: household_id, id, purchase_date, pharmacy, receipt_reference, total, saved, stock_applied, timestamps.
- `medicine_purchase_items`: household_id, id, purchase_id, medicine_id nullable, item_name_snapshot, quantity, subtotal.
- `medicine_dispensing_events`: household_id, id, medicine_id, medicine_name_snapshot, event_date, quantity, caregiver_label, created_at.
- `medicine_fill_events`: household_id, id, event_date, caregiver_label, stock_applied, created_at.
- `medicine_fill_items`: household_id, id, fill_event_id, medicine_id, medicine_name_snapshot, quantity.
- `medicine_stock_adjustments`: household_id, id, adjustment_date, caregiver_label, created_at.
- `medicine_stock_adjustment_items`: household_id, id, adjustment_id, medicine_id, medicine_name_snapshot, quantity_before, quantity_after.

This is a proposed mapping, not finalized DDL. Keep exact units and quantity semantics under review before migration. Add composite household-aware foreign keys for every parent/child relationship. Index household_id plus the most common date and medicine filters.

## 4. Critical implementation requirement: atomic stock operations

The existing app updates separate JSON collections in separate requests. For example, dispensing first writes the dispensing history and then separately updates medicine stock. A network failure between those writes can leave history and stock inconsistent.

The customer pilot must implement stock-changing operations as database transactions, preferably through narrowly scoped authenticated RPCs or server-side functions that:
1. validate the caller's JWT, household membership, and Inventario entitlement;
2. verify all referenced medicine rows belong to the same household;
3. insert/update the history event and update stock in one transaction;
4. reject invalid quantities and return the committed stock state.

This applies to dispensing, fill registration/edit/deletion, purchase stock application/reversal, and physical stock counts. Do not rely on sequential browser writes for stock integrity.

## 5. Required authorization and RLS tests

Use two synthetic households (A and B), with separate users and separate medicine records.

- Anonymous user cannot read or write any inventory table.
- Household A can create/read/update/delete its own medicines and permitted history.
- Household A cannot select, insert, update, or delete Household B rows, including by forging household_id.
- A user without Inventario entitlement cannot access inventory data even if they are a household member.
- Removing a member immediately removes their data access.
- A purchase item cannot reference a medicine or purchase header from another household.
- A dispensing/fill/adjustment item cannot reference another household's medicine.
- Invalid or negative quantities are rejected.
- Concurrent stock changes do not lose updates.
- Event history and stock changes commit or roll back together.
- No PIN, browser storage value, or user-editable metadata grants authorization.

## 6. Migration and compatibility rules

- Do not point the customer pilot at the legacy family-care project.
- Do not alter `marbaquero/inventario-medicinas` production source or its current endpoint.
- Do not copy existing personal medication names, quantities, purchases, caregiver labels, or history into synthetic test tenants.
- Do not run a migration against the live customer control-plane project as an experiment.
- Build the customer version as a separate implementation using a shared authenticated data-access layer.
- Keep the current app available unchanged until the customer version passes acceptance testing.

## 7. Pilot acceptance checklist

- [ ] New household receives no personal seed data.
- [ ] Authenticated owner can create medicines and configure stock thresholds.
- [ ] Owner can record purchases, including unlinked historical item names.
- [ ] Purchase stock application and reversal are correct.
- [ ] Owner can record individual dispensing and see stock/history update together.
- [ ] Owner can create, edit, and delete weekly fills without double-deducting stock.
- [ ] Owner can perform physical stock count and see before/after audit history.
- [ ] Dashboard stock alerts and days-of-supply calculations match the current app's behavior.
- [ ] Household A cannot access Household B data through any table, RPC, or API path.
- [ ] Billing entitlement controls app access.
- [ ] Backup and restore are tested in the pilot environment.
- [ ] English and Spanish navigation and forms pass manual testing.

## 8. Open decisions before coding

- Confirm whether `dailyDose` may be fractional and how unit types beyond tablets are represented.
- Confirm whether stock is always integer and whether partial tablets/liquid quantities must be supported.
- Confirm whether customer purchases should default to adding stock (the current UI does) and how corrections are represented.
- Confirm whether `saved` is a discount amount or another purchase metric; preserve as a numeric field until clarified.
- Decide whether receipts are in scope for the first Inventario pilot. The inspected current main page stores a receipt reference but does not use a private receipt upload flow.
