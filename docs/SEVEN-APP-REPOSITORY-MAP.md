# Seven-app repository and data map

This map separates catalog labels from actual code locations. It is based on repository source inspection; it is not a claim that every repo is currently deployed at a particular URL.

| Central app key | Catalog label | Source location found | Data/API surface observed |
|---|---|---|---|
| `pagos` | Pagos | `Pago-Cuidadoras/index.html` | Legacy `kv_store` key/value API |
| `inventario` | Inventario | `inventario-medicinas/index.html` | Legacy `kv_store` key/value API |
| `gastos_admin` | Gastos Admin | `Gastos-de-mama-admin/index.html` | Legacy `movimientos` REST API |
| `gastos_mama` | Gastos Mamá | `Gastos-de-mama-original/index.html` | Legacy `movimientos` REST API |
| `rosita` | Rosita | `reporte-rosita/index.html` | Legacy `reportes_aracely` table |
| `historial` | Historial | `reporte-rosita/dashboard.html`, `Consolidado-30dias-Fixed.html` | Legacy `reportes_aracely`, legacy consolidated-report queries also probe `reportes` |
| `medico` | Médico | `reporte-rosita/reporte-medico.html` | Legacy `reportes_aracely` table |

Related source in `reporte-rosita`:
- `sesion-cognitiva.html` reads/writes `sesiones_cognitivas`.
- `dashboard.html` includes the reports dashboard and links to cognitive-session history.
- `config.js` sets the legacy project URL and publishable key; it also contains a client-side admin PIN. That PIN is not an authorization boundary and must not be relied on for customer security.
- `Reporte-Diario-Rosita` is an older/smaller sibling repo. Its deployed role is not confirmed.

## Legacy database observed

Project `ywegbbdnphbbqiimqhqf` contains:
- `movimientos` — 194 rows
- `kv_store` — 9 rows
- `reportes` — 1 row
- `reportes_aracely` — 118 rows
- `sesiones_cognitivas` — 8 rows

RLS is enabled, but current policies allow broad anonymous operations on these tables. This is a known multi-tenant release blocker. Existing owner/family apps and records remain unchanged while a separate tenant-aware data path is designed and tested.

## Open verification items

1. Confirm the deployed URL and current production source for each catalog app.
2. Identify the authoritative app version where duplicate/older repos exist.
3. Inspect storage buckets and all remaining data flows, including receipt uploads and Drive integrations.
4. Confirm whether the optimized Gastos Admin artifact is used in production; it is not counted as a separate catalog app.
5. Build synthetic tenant fixtures and prove cross-household reads/writes are denied before enabling customer data.
