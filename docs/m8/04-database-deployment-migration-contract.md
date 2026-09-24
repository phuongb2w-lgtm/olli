# M8 — Database Deployment & Migration Contract

**Baseline (M8-T01):** 58 migration files in `supabase/migrations/` — **do not change count in T01**.

## Source of truth

- **Schema:** ordered SQL in `supabase/migrations/` (timestamp prefix order).
- **Types:** `types/database.generated.ts` — generated only (`npm run db:types`); verified by `npm run test:types:stale` against **local** Supabase.
- **Reference data safe for production:** embedded in migrations (e.g. 34 permissions, `commercial_plan` base row in M7-T03).
- **Never production:** `supabase/seed.sql`, `scripts/seed-auth-users.mjs`.

## Deployment order (production)

1. Create empty Supabase Cloud project (Postgres **15** to match `[db] major_version = 15`).
2. Link CLI: `supabase link --project-ref <ref>` (operator).
3. Apply migrations: `supabase db push` **or** `supabase migration up` per Supabase CLI policy — **same ordered set as local**.
4. Verify: `supabase db lint` on linked project (M8-T02 acceptance).
5. Regenerate types from **linked** project for release tag:  
   `supabase gen types typescript --linked > types/database.generated.ts`  
   Commit types only when schema changed; `test:types:stale` remains local-dev gate.
6. **Do not** run `supabase db reset` on production.

## Bootstrap data (production)

| Data | Source |
|------|--------|
| Permissions, indicators, `commercial_plan` (`base`) | Migrations |
| New customer center | `scripts/provision-customer-center.mjs` + `SUPABASE_SECRET_KEY` |
| Subscription activation | Operator `service_role` RPCs (`activate_organization_subscription`, etc.) |
| Dev org A/B/C fixtures | **Forbidden** |

## New organization triggers (automatic on INSERT)

Per M6/M7 docs — no manual SQL for cost groups, CRM reference catalogs, entitlement row, canonical roles; center provisioning RPC completes subscription graph.

## Migration failure handling

| Failure mode | Response |
|--------------|----------|
| Push fails mid-chain | **Stop deploy.** Do not run app against partial schema. Fix forward migration or restore DB snapshot (see backup contract). |
| Lint errors | Block release; fix SQL in new migration (avoid editing applied remote history). |
| Drift (manual Dashboard SQL) | Treat as incident; compare `supabase db diff` / pull; reconcile via new migration |

## Schema drift detection

| Method | When |
|--------|------|
| `npm run test:types:stale` | Dev/CI — local DB vs committed types |
| `supabase db lint` | Pre-push and CI |
| Optional M8-T10 | Scheduled `db diff` against production linked ref |

## Local vs production verification

| Suite | Local (`db:verify`) | Production |
|-------|---------------------|------------|
| Full SQL regression (~M0–M7) | `scripts/supabase-verify.ps1` after reset+seed | **Not** run with seed; use targeted smokes + optional subset on staging |
| `db:reset` | Dev/CI only | **Forbidden** |

## CI note (gap)

`.github/workflows/foundation-ci.yml` runs **subset** of SQL tests (M0 only) + partial Playwright — **not** full `npm run verify`. Production readiness requires keeping **full** `npm run verify` as developer/release gate until CI parity (M8-T09).
