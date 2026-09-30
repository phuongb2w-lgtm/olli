# CW2-T09.1 — Supabase Auth readiness verification stabilization

## Problem

After `supabase db reset`, GoTrue may restart while Kong still accepts TCP then closes connections, or the admin API is not yet routable. The verify harness previously used a fixed 30s sleep and `seed-auth-users.mjs` polled via Supabase JS only, often surfacing `fetch failed` without actionable detail.

## Root cause (classification **B/C**)

- **B — Harness:** readiness did not match the actual dependency (Kong-routed `GET /auth/v1/admin/users` with service role).
- **C — Local timing:** `db reset` restarts Auth; Kong can briefly proxy poorly until Auth is healthy (sometimes requires one Kong+Auth container restart).

No product/schema change.

## Readiness contract (after T09.1)

1. `supabase start` after reset (unchanged).
2. Bounded poll (default 90 × 2s) of **`{API_URL}/auth/v1/admin/users?page=1&per_page=1`** with `Authorization` + `apikey` service role headers — same path as seeding.
3. On failure, **one** `docker restart` of `supabase_kong_olli-local` and `supabase_auth_olli-local`, then poll again.
4. `seed-auth-users.mjs` reuses the same waiter (idempotent user upserts unchanged).

Diagnostics log attempt count and failure reason (HTTP status or fetch cause code); secrets are never printed.

## Files

- `scripts/lib/local-supabase-auth-ready.mjs`
- `scripts/wait-local-supabase-auth-ready.mjs`
- `scripts/seed-auth-users.mjs`
- `scripts/supabase-verify.ps1`
