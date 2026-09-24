# M8 — Supabase Cloud Production Operator Procedure (M8-T02)

**Scope:** Database/auth backend only — `https://<ref>.supabase.co`  
**Application URL (unchanged):** `https://olli.riuda.click`  
**Canonical schema:** `supabase/migrations/` (58 files at T02 baseline unless release adds migrations)

This document is the executable companion to [04 — Database deployment contract](./04-database-deployment-migration-contract.md) and [03 — Environment & secrets](./03-environment-secrets-contract.md).

## 1. Production project contract (repository-side)

| Value | Classification | Where stored |
|-------|----------------|--------------|
| Supabase **project ref** | Operator-only (not secret) | `OLLI_SUPABASE_PROJECT_REF`, Dashboard |
| **API URL** | Client-safe | `NEXT_PUBLIC_SUPABASE_URL` |
| **Publishable (anon) key** | Client-safe | `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` |
| **Service role secret** | Server-only | `SUPABASE_SECRET_KEY` on app host only |
| **Database password** | Operator-only | Supabase Dashboard / CLI link prompt — not in git |
| **Supabase CLI access token** | CI/CD-only | `SUPABASE_ACCESS_TOKEN` in CI secret store |
| **Linked CLI state** | Operator machine | `supabase/.temp/project-ref` (git-ignored via `supabase/.temp/`) |

Template: [`.env.production.example`](../../.env.production.example) (placeholders only).

**Never** put `SUPABASE_SECRET_KEY` or service-role JWTs in `NEXT_PUBLIC_*` variables.

## 2. Create Cloud project (once)

1. Supabase Dashboard → **New project** → region per RIUDA policy.
2. Postgres **15** (matches `[db] major_version = 15` in `supabase/config.toml`).
3. Record **project ref** and API URL (`https://<ref>.supabase.co`).
4. Copy **publishable** and **service_role** keys into host secret manager (not git).
5. Confirm backup tier / PITR (see [06 — Backup](./06-backup-recovery-contract.md)).

## 3. Link repository to the intended project

On an operator workstation with this repo checked out at the **release SHA**:

```powershell
cd D:\Olli
npx supabase login
# or: set SUPABASE_ACCESS_TOKEN for CI

$env:OLLI_SUPABASE_PROJECT_REF = "<project-ref>"
$env:NEXT_PUBLIC_SUPABASE_URL = "https://<project-ref>.supabase.co"
$env:NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY = "<publishable>"
$env:SUPABASE_SECRET_KEY = "<service-role>"

npx supabase link --project-ref $env:OLLI_SUPABASE_PROJECT_REF
npm run db:production:link-verify
```

**Identity rule:** `OLLI_SUPABASE_PROJECT_REF`, `NEXT_PUBLIC_SUPABASE_URL`, and `supabase/.temp/project-ref` must agree before any schema change.

## 4. Pre-deploy gates (mandatory)

Local/release verification on the **same commit** that will be deployed:

```powershell
$env:OLLI_EXPECTED_MIGRATION_COUNT = "58"
$env:OLLI_RELEASE_GIT_SHA = (git rev-parse HEAD)
npm run db:production:predeploy-gate
```

This runs (in order): clean tree check, migration count, `npm run test:env`, `npm run test:types:stale`, full `npm run db:verify` (local reset + seed + SQL suite).

When Cloud credentials are available on the same machine:

```powershell
$env:OLLI_PREDEPLOY_INCLUDE_REMOTE = "1"
npm run db:production:predeploy-gate
```

Additional release gates: `npm run lint`, `npm run typecheck`, `npm run build` (included in full `npm run verify`).

## 5. Migration deployment (normal path)

**Forbidden on production/staging:** `npm run db:reset`, `supabase db reset --linked`, `supabase db push --include-seed`, manual `seed.sql`, `npm run db:seed:auth`.

1. **Backup** — manual Supabase snapshot (even if daily backups exist).
2. **Inspect remote state:**

   ```powershell
   npm run db:production:migration-status
   ```

3. **Dry run:**

   ```powershell
   npm run db:production:migration-dry-run
   ```

4. **Apply** (requires explicit confirmation):

   ```powershell
   $env:OLLI_CONFIRM_PRODUCTION_DEPLOY = "yes"
   npm run db:production:migration-deploy
   ```

   Under the hood: `supabase db push --linked --yes` (no seed) then `supabase db lint --linked --fail-on error`.

5. **If schema changed on this release**, regenerate types from linked project, commit on release branch **before** tag (local dev gate remains `npm run db:types`):

   ```powershell
   npm run db:types:linked
   npm run test:types:stale
   ```

## 6. Production seed policy

| Category | Source | Production |
|----------|--------|------------|
| Schema | `supabase/migrations/*.sql` | Applied via `db push` |
| Reference data | Migrations (e.g. `20260914140100_reference_data.sql`, M7 `commercial_plan`) | Automatic with migrations |
| New customer centers | `scripts/provision-customer-center.mjs` | Operator after deploy |
| Local/test fixtures | `supabase/seed.sql`, `scripts/seed-auth-users.mjs` | **Never** |

Brand-new production database after full migration apply: permissions/indicators/plan rows exist; **no** organizations, **no** `@olli.local` Auth users until operator provisioning.

Local `[db.seed] enabled = false` in `supabase/config.toml` — seed is manual in dev via `scripts/supabase-verify.ps1` only.

## 7. Schema drift

Investigate (read-only):

```powershell
npm run db:production:drift-check
```

Uses `supabase db diff --linked` (migration shadow vs remote). Non-empty diff → **stop**; reconcile with a **new reviewed migration** or restore from backup — do not treat Dashboard SQL as the normal path.

## 8. Post-deploy production smoke (non-destructive)

```powershell
npm run db:production:smoke
```

Checks include: reference `permission` / `commercial_plan`, absence of dev fixture org UUID, RLS on core tables, migration history count, essential RPC registration.

Does **not** run `supabase/tests/*` against live customer data.

## 9. Rollback / failure policy

| Scenario | Action |
|----------|--------|
| Migration fails **before** completion | Stop. Do not deploy app. Fix forward migration or restore DB snapshot. |
| Migration succeeds, **app deploy fails** | Roll back app artifact only; DB unchanged. |
| Forward-compatible migration + bad app | Roll back app; DB stays at new schema if backward compatible. |
| Destructive migration / bad data | Restore from snapshot ([06 — Backup](./06-backup-recovery-contract.md)); forward fix after root cause. |
| Dashboard manual SQL drift | Incident; drift check → new migration or restore — never silent overwrite. |

There is **no** universal safe `supabase migration down` on production — default is **forward fix** or **restore**.

## 10. npm script reference

| Script | Risk |
|--------|------|
| `db:production:env-check` | Low — validates env |
| `db:production:link-verify` | Low — read remote migration list |
| `db:production:migration-status` | Low |
| `db:production:migration-dry-run` | Low |
| `db:production:drift-check` | Low — read-only |
| `db:production:smoke` | Low — read-only |
| `db:production:predeploy-gate` | Local destructive (`db:verify` reset) — **not** production |
| `db:production:migration-deploy` | **High** — schema change; requires `OLLI_CONFIRM_PRODUCTION_DEPLOY=yes` |

## 11. Cloud acceptance

Until RIUDA links a real Supabase Cloud project and runs link verify → push → smoke, treat T02 as **IMPLEMENTATION COMPLETE / CLOUD ACCEPTANCE PENDING** (see task report).
