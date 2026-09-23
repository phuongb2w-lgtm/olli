# M7-T04 — Commercial access enforcement

**Starting SHA:** `1984414` — `feat(m7): add subscription entitlement domain`  
**Scope:** Enforce `organization_subscription.status` across identity, routing, server actions, RPC, and RLS without weakening M1–M6 RBAC.  
**Deferred:** T05 onboarding UX, T06 polished subscription dashboard, billing provider.

## Access matrix (final)

| Subscription | Primary Owner | Staff | Normal domain mutation |
|--------------|---------------|-------|-------------------------|
| `provisioning` | Authenticated; restricted status surface | Restricted (no workspace) | Denied |
| `active` | Normal (RBAC) | Normal (RBAC) | Allowed (RBAC + RLS) |
| `suspended` | Authenticated; restricted status surface | Restricted | Denied |
| `cancelled` | Authenticated; restricted status surface | Restricted | Denied |

Non-active subscription does **not** deactivate Auth users, mutate staff lifecycle, or delete domain data.

## Database enforcement

| Primitive | Role |
|-----------|------|
| `organization_subscription_allows_normal_use(org_id)` | Authoritative: only `active` permits normal use; missing row fails closed |
| `is_organization_commercially_entitled()` | Current-center shorthand |
| `assert_organization_commercially_entitled()` | RPC guard; raises `commercial_access_restricted` |
| `is_operationally_active_app_user()` | M6 usable identity (org active, member) without commercial gate |
| `is_operational_primary_owner()` | Owner identity for commercial status read while restricted |
| `is_active_app_user()` | Operational **and** commercially entitled (RLS + RPC default) |
| `is_primary_owner()` | Operational owner **and** commercially entitled (product permissions) |
| `has_permission()` | Requires commercial entitlement before RBAC / owner-only branches |
| `fetch_session_commercial_access()` | Session routing contract (authenticated) |
| `fetch_owner_commercial_status()` | Owner read-only; uses operational owner check only |

Operator `service_role` subscription RPCs are unchanged and do not pass through the customer commercial gate.

`initialize_organization_access_foundation` ensures every organization has a subscription row: **provisioning** during `finalize_center_provisioning`, **active** when created by trusted postgres test/bootstrap paths, otherwise **provisioning**. Missing rows remain fail-closed for authenticated runtime.

`initialize_organization_access_foundation` ensures every organization has a subscription row: **provisioning** during `finalize_center_provisioning`, **active** when created by trusted postgres test/bootstrap paths, otherwise **provisioning**. Missing rows remain fail-closed for authenticated runtime.

## Application layer

| Area | Behavior |
|------|----------|
| `getIdentityState()` | Distinguishes `active` vs `commercially_restricted` (with subscription status + owner flag) |
| `(protected)/layout` | Redirects commercially restricted users out of AppShell |
| `(restricted)/subscription-status` | Minimal primary Owner surface |
| `(restricted)/commercial-access` | Staff restricted message |
| Server actions | `getCurrentAppUser()` returns null when not commercially active (fail closed) |

## Composition with `organization.status`

Normal use requires **both**:

1. M6 operational identity (`organization.status = active`, active member), and  
2. `organization_subscription.status = active`.

`organization.status = inactive` continues to null `current_app_user_id()` independently. When both block, operational inactivity wins first (no identity).

## Tests

| Suite | Path | Cases |
|-------|------|-------|
| SQL | `supabase/tests/m7_t04_commercial_access_tests.sql` | 20 |
| Smoke | `scripts/commercial-access-smoke.mjs` | 11 |
| Playwright | `tests/e2e/m7-commercial-access.spec.ts` | 4 |

## Migrations

Baseline **56** → **57** (`20260928100000_m7_t04_commercial_access_enforcement.sql`).
