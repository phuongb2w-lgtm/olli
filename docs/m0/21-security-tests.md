# M0-T04 — Security Tests

**Date:** 2026-09-14

Executable suite: `supabase/tests/m0_security_tests.sql`  
Runner: `scripts/supabase-verify.ps1` (after local Supabase start, reset, dev seed)

**Target:** 30 / 30 PASS alongside M0-T03 integrity 25 / 25 PASS.

---

## Why Not Superuser?

Tests simulate Supabase request roles:

```sql
SET LOCAL ROLE authenticated;  -- or anon
PERFORM set_config('request.jwt.claim.sub', '<auth.users.id>', true);
PERFORM set_config('request.jwt.claims', json_build_object('sub', ..., 'role', 'authenticated')::text, true);
```

This drives `auth.uid()` the same way PostgREST/Supabase API does. Running as `postgres` would bypass RLS and prove nothing.

Bootstrap steps inside tests use `_sec_as_super()` (postgres role) only to set up rows invisible to the subject under test.

---

## Scenario Catalog

| # | Category | Scenario |
|---|----------|----------|
| 1 | Authentication | Auth user resolves to correct `app_user` / org |
| 2 | Authentication | Unmapped auth user has no operational access |
| 3 | Authentication | Removed auth mapping blocks access; `app_user` preserved |
| 4–6 | Anonymous | Cannot read student, finance, or mutate |
| 7 | Tenant | Org A admin reads permitted Org A data |
| 8–11 | Tenant | Org A cannot read Org B student/class/charge/expense |
| 12–13 | Tenant | Org A cannot insert/update rows into Org B |
| 14–15 | Permissions | Reader can read; non-writer cannot create student |
| 16–17 | Permissions | Finance reader reads; non-writer cannot create charge |
| 18–19 | Permissions | Observation writer creates; staff without permission denied |
| 20–21 | Privilege | Self role assign / permission grant denied |
| 22–24 | Privilege | Cross-org role edit denied; permission mutate denied; self org change denied |
| 25–29 | Historical | Finalized result, completed session, charge amount, cross-org allocation, expense group mismatch |
| 30 | Identity | Disabled / inactive `app_user` denied |

---

## Assertion Notes

- **RLS silent deny:** Some UPDATE attempts affect 0 rows without raising an exception. Tests 22–23 use `GET DIAGNOSTICS … ROW_COUNT = 0` as PASS.
- **RLS policy violation:** INSERT/UPDATE with failing `WITH CHECK` raises an exception — caught as PASS for tests 12–13, 20–21, 25–29.
- **Anon access:** SELECT/INSERT under `anon` may raise `insufficient_privilege` — tests 4–6 catch that as PASS.

---

## Running

```powershell
# Full stack (recommended gate)
powershell -ExecutionPolicy Bypass -File scripts/supabase-verify.ps1

# Or via npm
npm run db:verify:supabase
```

Prerequisites: Docker Desktop, `npm install`, no port conflict on Olli Supabase ports (54421–54424 in `supabase/config.toml`).

Generic PostgreSQL integrity (no Auth/RLS):

```powershell
npm run db:verify:postgres
```

---

## Dev Fixtures Required

Security tests depend on `supabase/seed.sql` identities. **Never deploy dev seed to production.**

Reference data (permissions, indicators) comes from migrations and is production-safe.
