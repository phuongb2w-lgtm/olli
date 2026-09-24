# M7 — Commercialization milestone contract

Authoritative integration reference for M7-T02 through M7-T07. Implementation detail remains in task-specific docs; this file defines **state, routing, and responsibility boundaries**.

## Layered model

| Layer | Authority | Purpose |
|-------|-----------|---------|
| **Organization** | `organization.status`, profile fields, `setup_completed_at` | Operational org identity; setup completion is Owner first-use only |
| **Subscription** | `organization_subscription.status` | Commercial lifecycle: `provisioning`, `active`, `suspended`, `cancelled` |
| **Entitlement** | `organization_entitlement.staff_limit` (+ plan sync) | Runtime seat cap for M6 enforcement |
| **Seat usage** | `count_member_staff_seats(org_id)` | Authoritative consumed seats (M6) |
| **RBAC** | `has_permission()` | Domain permissions; gated by commercial entitlement for normal use |
| **Session UX** | `fetch_session_commercial_access()` | Login/layout routing hints (not authorization) |

Billing, checkout, invoices, and payment providers are **explicitly deferred** (see [README](./README.md)).

## Subscription lifecycle (operator-driven)

| Status | Normal app use (`allows_normal_use`) | Owner onboarding (`requires_center_setup`) | Staff sign-in |
|--------|--------------------------------------|--------------------------------------------|---------------|
| **provisioning** | No | Yes, if Primary Owner and `setup_completed_at` IS NULL | No (commercial gate) |
| **active** | Yes | Yes, if setup incomplete | Yes (RBAC) |
| **suspended** | No | No (commercial blocks setup RPC) | No |
| **cancelled** | No | No | No |

Operator transitions use **service_role** RPCs (`activate_organization_subscription`, `suspend_organization_subscription`, `reactivate_organization_subscription`, `cancel_organization_subscription`). Authenticated Owners cannot mutate subscription rows.

## Owner first-use setup

- **Incomplete:** `setup_completed_at IS NULL` and subscription allows owner setup (`provisioning` or `active`).
- **Gate:** `requires_center_setup()` → session field `requires_center_setup`.
- **Complete:** `complete_center_setup()` sets `setup_completed_at` once; repeats raise `setup_already_complete`.
- **Not** a general settings editor; long-term org profile edits remain deferred.

## Authenticated landing (UX only)

Central helper: `resolveAuthenticatedLandingPath()` / `sessionRequiresOnboardingRedirect()`.

| Session shape | Landing |
|---------------|---------|
| `requires_center_setup` | `/onboarding` |
| Else `!allows_normal_use` + Primary Owner | `/subscription-status` |
| Else `!allows_normal_use` + staff | `/commercial-access` |
| Else | `/` (protected AppShell) |

Restricted layout redirects Primary Owners with pending setup away from `/subscription-status` and similar surfaces until onboarding completes.

## Owner commercial read

- **Route (entitled):** `/subscription` (protected shell, `center_account.manage`).
- **Route (restricted):** `/subscription-status` (restricted shell).
- **RPC:** `fetch_owner_commercial_status()` — plan, subscription status, `staff_limit`, `staff_seats_used` (from entitlement + `count_member_staff_seats`).

## Center provisioning entry state (T02)

`finalize_center_provisioning` creates:

- Active organization row (`setup_completed_at` NULL for new centers).
- Primary Owner + center_manager role assignment.
- `organization_subscription` in **provisioning**.
- Entitlement bootstrap (`staff_limit` = 5) via subscription sync.

Existing production/dev fixture orgs from seed/backfill receive `setup_completed_at` so they **do not** re-enter onboarding.

## Security invariants

- UI routing ≠ authorization; mutations enforce commercial + RBAC in DB/RPC/RLS.
- `has_permission()` and `is_primary_owner()` require commercial **active** subscription for normal use.
- Operational Primary Owner reads (commercial status, onboarding RPCs) use `is_operational_primary_owner()` where applicable.
- No authenticated EXECUTE on operator subscription mutation RPCs.

## Verification map

| Task | Primary proof |
|------|----------------|
| T02 | `m7_t02_center_provisioning_tests.sql`, `test:center-provisioning` |
| T03 | `m7_t03_subscription_entitlement_tests.sql`, `test:subscription-commercial` |
| T04 | `m7_t04_commercial_access_tests.sql`, `test:commercial-access`, commercial E2E |
| T05 | `m7_t05_owner_subscription_status_ux_tests.sql`, subscription E2E |
| T06 | `m7_t06_owner_onboarding_center_setup_tests.sql`, onboarding E2E |
| T07 | `m7_t07_commercialization_integration_tests.sql`, integration E2E, full `npm run verify` |

## Deferred (post-M7)

Payment gateway, checkout, public pricing, invoices, recurring billing, Owner self-service plan purchase, operator console UI, full `/settings` organization profile module.
