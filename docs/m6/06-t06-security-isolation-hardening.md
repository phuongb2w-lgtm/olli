# M6-T06 — Security, RLS & organization-isolation hardening

Implementation closeout for the approved T06 design gate (post-T05 baseline `1de46894`).

## Scope delivered

- **`supabase/tests/m6_t06_security_isolation_tests.sql`** — 18 attack/regression scenarios (cross-org lifecycle, identity gate, executive owner-only invariant, service/internal EXECUTE denial, direct DML, entitlement isolation, SECURITY DEFINER `search_path` catalog check).
- **`scripts/supabase-verify.ps1`** — wires T06 suite with explicit **18/18** pass expectation.
- **Documentation alignment:** `docs/m0/18-auth-identity-model.md`, `docs/m0/20-rls-policy-matrix.md` (M6 identity/administration appendix).
- **No schema migration** — T05 implementation satisfied security requirements; T06 validates and documents.

## Explicitly not in T06

- Auth ban/disable/delete, Owner transfer, teacher sync, audit UI, RBAC redesign, duplicate `is_primary_owner()` on every executive RPC.
- Lifecycle reimplementation (T05).

## Regression

Full `npm run verify` including M0 security, M6-T02–T06 SQL suites, and Playwright `m6-users-administration` / `m6-staff-lifecycle`.

## Carried debt (non-blocking)

- Optional UX gate `can('center_account.manage')` on server actions (DB RPC remains authoritative).
- Auth-layer disable as defense-in-depth (deferred from T05).
- `user.read` catalog orphan (documented, not removed).
