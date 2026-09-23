# M7-T03 — Subscription & entitlement domain

**Starting SHA:** `430764f` — `feat(m7): add trusted center owner provisioning`  
**Scope:** Commercial plan, organization subscription, entitlement sync. No T04 access gating, no billing provider.  
**Verification:** `npm run verify` exit 0 (M7-T03 SQL 18/18, subscription smoke 6/6, Playwright 196/196, i18n 1891/1891).

## Schema

### `commercial_plan`

| Column | Notes |
|--------|--------|
| `code` | Unique stable identifier (`base` seeded) |
| `name` | Display name |
| `staff_limit` | ≥ 0; synced to runtime entitlement |
| `status` | `active` \| `archived` |

Migration seeds **`base`** with `staff_limit = 5`.

### `organization_subscription`

One row per organization (`UNIQUE (organization_id)`).

| Column | Notes |
|--------|--------|
| `commercial_plan_id` | FK → plan |
| `status` | `provisioning` \| `active` \| `suspended` \| `cancelled` |
| `activated_at` / `suspended_at` / `cancelled_at` | Lifecycle timestamps |

### `organization_entitlement` (extended)

- `commercial_plan_id`, `organization_subscription_id` (FKs for traceability)
- `staff_limit` remains **M6 runtime authority**
- Trigger `organization_entitlement_protect_commercial_fields` blocks direct changes unless `olli.trusted_entitlement_sync = true`

## Lifecycle matrix

| From \\ To | active | suspended | cancelled |
|------------|--------|-----------|-----------|
| **provisioning** | ✓ | — | ✓ |
| **active** | — | ✓ | ✓ |
| **suspended** | ✓ | — | ✓ |
| **cancelled** | ✗ (terminal) | ✗ | — |

Invalid transitions raise `invalid_subscription_transition`.

## Entitlement synchronization

`_m7_sync_entitlement_from_subscription(org_id)`:

- Reads current plan + subscription
- Updates `organization_entitlement.staff_limit` from plan for all statuses **except** `cancelled` (retains last-known limit)
- Updates plan/subscription FK columns on entitlement

Operator RPCs call sync after mutations.

## Backfill

Migration backfill runs when no org rows exist yet (empty DB at migrate time). **Dev/test fixture orgs** in `supabase/seed.sql` call `_m7_initialize_organization_subscription(..., 'active')` after INSERT. Rationale: seed centers are already operational; `active` preserves M1–M6 behavior (`staff_limit` 5 on org B/C; org A may remain at fixture headroom 24 via postgres superuser UPDATE).

## T02 provisioning interaction

`finalize_center_provisioning` (replaced in T03 migration, not T02 file) calls:

`_m7_initialize_organization_subscription(org_id, 'provisioning')`

after organization INSERT. Staff limit still **5** via base plan sync. Operator **`activate_organization_subscription`** moves to `active` (T04 may gate on status later).

T02 idempotency, Auth compensation, and single-transaction finalize graph preserved.

## Lower plan / over-use

Plan change may reduce `staff_limit` below `count_member_staff_seats`. Staff rows are **not** removed. M6 continues to block new seat consumption (`staff_seat_limit_exceeded`).

## Operator actions (service_role)

| RPC | Purpose |
|-----|---------|
| `activate_organization_subscription` | `provisioning` → `active` |
| `suspend_organization_subscription` | `active` → `suspended` |
| `reactivate_organization_subscription` | `suspended` → `active` |
| `cancel_organization_subscription` | `active`/`suspended`/`provisioning` → `cancelled` |
| `change_organization_commercial_plan` | Plan change + sync |
| `resync_organization_entitlement` | Repair sync |

## Owner read

`fetch_owner_commercial_status()` — **primary Owner only** (authenticated EXECUTE).

Returns plan code/name, subscription status, staff limit, seats used, lifecycle timestamps, and `organization_status` (operational, independent).

## Security

- No authenticated DML on `commercial_plan` or `organization_subscription`
- Owner/staff cannot execute operator RPCs
- Entitlement commercial fields cannot be updated by clients (trigger)

## Tests

| Suite | Path | Cases |
|-------|------|-------|
| SQL | `supabase/tests/m7_t03_subscription_entitlement_tests.sql` | 18 |
| Smoke | `scripts/subscription-commercial-smoke.mjs` | 6 |

## Migrations

Baseline 55 → **56** (`20260927100000_m7_t03_subscription_entitlement_domain.sql`).

## Deferred (T04+)

- Application-wide suspension/login/mutation gating
- Owner subscription UX (T06)
- Billing provider integration
