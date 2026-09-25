# M8 — Environment & Secrets Contract

**Applies to:** local dev, CI, staging, production  
**Enforcement today:** `scripts/env-secrets-audit.mjs` (`npm run test:env`), M0-T06 rules

## Variable inventory

| Variable | Exposure | Required when | Purpose |
|----------|----------|---------------|---------|
| `NEXT_PUBLIC_SUPABASE_URL` | **Public** (browser bundle) | App runtime (all envs) | Supabase project URL (Auth + REST) |
| `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` | **Public** | App runtime (all envs) | Anon/publishable key for user-scoped clients |
| `SUPABASE_SECRET_KEY` | **Server-only** | Server Actions using `createAdminClient()`, operator scripts | Service role — Auth Admin + bypass RLS for trusted orchestration |
| `OLLI_STAFF_PROVISION_USE_INVITE` | Server-only | Optional; default invite **on** in production | `"false"` forces `createUser` (local/Playwright only) |
| `PLAYWRIGHT_*` | CI/local test only | Playwright | Port, base URL, browser path — **never production** |
| `POSTGRES_*` | Scripts only | `scripts/db-verify.ps1` generic Postgres path | Not used by Next.js app |
| `DOCKER_VERIFY_PORT` | Scripts only | Generic DB verify | Local Docker Postgres |
| `CI` | CI | GitHub Actions | Playwright retries / forbidOnly |
| `OLLI_SUPABASE_PROJECT_REF` | Operator-only | Cloud DB deploy / verify scripts | Must match `<ref>` in `NEXT_PUBLIC_SUPABASE_URL` |
| `OLLI_EXPECTED_MIGRATION_COUNT` | Operator-only | Pre-deploy gate | Defaults to current repo migration file count |
| `OLLI_RELEASE_GIT_SHA` | Operator-only | Pre-deploy gate | Optional pin to release commit |
| `OLLI_CONFIRM_PRODUCTION_DEPLOY` | Operator-only | **`db:production:migration-deploy` only** | Must be `yes` to apply Cloud migrations |
| `OLLI_PREDEPLOY_INCLUDE_REMOTE` | Operator-only | Pre-deploy gate | `1` = run Cloud env/link/status checks |
| `OLLI_APP_PREDEPLOY_INCLUDE_HOST_ENV` | Operator-only | App pre-deploy gate | `1` = run `app:production:env-check` |
| `OLLI_APP_BASE_URL` | Operator-only | Post-deploy smoke | Deployed origin, e.g. `https://olli.riuda.click` |
| `NEXT_PUBLIC_OLLI_CANONICAL_APP_ORIGIN` | **Public** | Production/staging app | Default `https://olli.riuda.click`; Auth Site URL must align |
| `OLLI_DEPLOYMENT_TIER` | Server-only | Runtime validation | `production` \| `preview` \| `development` (Vercel sets via `VERCEL_ENV` when omitted) |
| `OLLI_PRODUCTION_SUPABASE_PROJECT_REF` | Operator-only | Preview safety | Fail preview smokes/env-check if preview uses production Supabase ref |
| `OLLI_GIT_SHA` / `VERCEL_GIT_COMMIT_SHA` | Build/runtime | `/api/health` | Safe release identification (not a secret) |
| `OLLI_HEALTH_CHECK_SUPABASE` | Server-only | Health route | `1` = optional Supabase `/auth/v1/health` ping |
| `SUPABASE_ACCESS_TOKEN` | CI/CD-only | Non-interactive `supabase login` | Never in client bundle or git |

**Not canonical:** `NEXT_PUBLIC_SUPABASE_ANON_KEY` (use publishable key naming per M0-T05).

**Production template (M8-T02):** [`.env.production.example`](../../.env.production.example) — placeholders only; real values in host/CI secret store.

**Legacy script aliases:** Smokes accept `SECRET_KEY` from `supabase status -o env` when `SUPABASE_SECRET_KEY` unset — **production operators must set `SUPABASE_SECRET_KEY` explicitly** on the app host and in CI secrets for any remote smoke job.

## Classification rules

1. **Public (`NEXT_PUBLIC_*`)** — May appear in client bundles. Only Supabase URL + publishable key.
2. **Server-only** — `SUPABASE_SECRET_KEY` must never be referenced under `src/components`, `src/app` client components, or browser `client.ts`.
3. **Local-only assumptions** — `supabase status -o env`, fixed container name `supabase_db_olli-local`, dev passwords in `seed-auth-users.mjs`.
4. **Git** — `.env.local` ignored; `.env.example` placeholders only (audited).

## Environment separation

| Environment | Supabase | App env source | Seed / fixtures |
|-------------|----------|----------------|-----------------|
| **Local** | `supabase start` (`project_id = olli-local`) | `.env.local` from `.env.example` + `supabase status` | `seed-auth-users.mjs` + `supabase/seed.sql` — **never production** |
| **CI** | Ephemeral `supabase start` in workflow | `GITHUB_ENV` from `supabase status` | Same dev seed as local |
| **Staging** | Dedicated Supabase project | Host secret manager | **No** `seed.sql`; centers via `provision-customer-center.mjs` only |
| **Production** | Dedicated Supabase project | Host secret manager | **No** seed; reference data from migrations only |

## Production app host minimum

```
NEXT_PUBLIC_SUPABASE_URL=https://<ref>.supabase.co
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=<publishable>
NEXT_PUBLIC_OLLI_CANONICAL_APP_ORIGIN=https://olli.riuda.click
SUPABASE_SECRET_KEY=<service_role>   # server runtime only
OLLI_SUPABASE_PROJECT_REF=<ref>      # must match URL; required on production host
OLLI_STAFF_PROVISION_USE_INVITE=true # default; omit = invite path
```

## Leak verification (mandatory gates)

| Gate | Command / check |
|------|-----------------|
| Static audit | `npm run test:env` |
| Build bundle scan | `test:env` scans `.next/static` for `service_role` when build exists |
| Admin module | `src/lib/supabase/admin.ts` must keep `import "server-only"` |
| Pre-release | Production build on CI with `test:env` after `npm run build` |

## Gaps (T01)

| Gap | Remediation task |
|-----|------------------|
| `.env.example` omits `OLLI_STAFF_PROVISION_USE_INVITE` | M8-T05 — document in example with production default comment |
| ~~No staging/production env template file~~ | **Addressed M8-T02** — `.env.production.example`; further hardening in M8-T05 |
| Remote smokes not wired in CI | M8-T09 — optional workflow job with secrets |
