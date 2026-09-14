# M0-T05 — Decision Log

**Date:** 2026-09-14

## 1. Exposed object count (reconciled)

| Category | Count |
|----------|------:|
| Tables in `public` (exposed) | **31** |
| Views in `public` | **1** (`charge_balance`) |

**Breakdown:** 2 global reference tables (`permission`, `observation_indicator`) + 29 organization-scoped tables (including `organization`).

Prior M0-T03 header said "32" (off-by-one). M0-T04 "33 operational + 2 global" double-counted globals as additive.

## 2. charge_balance

- `ALTER VIEW … SET (security_invoker = true)` in `20260914140600_m0_t05_security_hardening.sql`
- `REVOKE ALL ON charge_balance FROM anon`
- `GRANT SELECT` remains for `authenticated`; underlying charge/payment/adjustment RLS applies
- Five dedicated tests in `supabase/tests/m0_charge_balance_tests.sql`
- **Not used in UI** until preflight passed

## 3. Helper RPC exposure

| Function | SECURITY | EXECUTE |
|----------|----------|---------|
| `current_app_user_id()` | DEFINER | `authenticated` only (RLS + server resolution) |
| `current_organization_id()` | DEFINER | `authenticated` only |
| `has_permission(text)` | DEFINER | `authenticated` (UX `can()` helper) |
| `is_active_app_user()` | DEFINER | `authenticated` |

`anon` EXECUTE revoked. Blanket `GRANT EXECUTE ON ALL FUNCTIONS` removed.

## 4. Auth fixture seeding

SQL `auth.users` inserts did not produce working GoTrue password login. Dev Auth users are created via **`scripts/seed-auth-users.mjs`** (admin API, fixed UUIDs) before domain `seed.sql`.

## 5. Publishable key terminology

Application and docs use **Publishable Key** / **Secret Key** (modern Supabase model).

## 6. Deferred to M0-T06+

- Student/teacher CRUD modules
- Dashboards and reports
- Persisting locale changes to `app_user.preferred_locale` (requires UX + policy review)
- `charge_balance` in finance UI
