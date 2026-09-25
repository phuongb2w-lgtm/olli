# M8 — Environment & Secrets Contract

**Applies to:** local dev, CI, staging, production  
**Enforcement today:** `npm run test:env` (`env-secrets-audit.mjs` + `env-contract-smoke.mjs`), startup `assertProductionAppEnv()` (production + preview tiers), M0-T06 rules  
**Rotation / leak:** [14 — Secret rotation & incident procedure](./14-secret-rotation-incident-procedure.md)

## Variable inventory

| Variable | Exposure | Required when | Purpose |
|----------|----------|---------------|---------|
| `NEXT_PUBLIC_SUPABASE_URL` | **Public** (browser bundle) | App runtime (all envs) | Supabase project URL (Auth + REST) |
| `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` | **Public** | App runtime (all envs) | Anon/publishable key for user-scoped clients |
| `SUPABASE_SECRET_KEY` | **Server-only** | Server Actions using `createAdminClient()`, operator scripts | Service role — Auth Admin + bypass RLS for trusted orchestration |
| `OLLI_STAFF_PROVISION_USE_INVITE` | Server-only | Optional; default invite **on** in production | `"false"` forces `createUser` (local/Playwright only) |
| `OLLI_CENTER_PROVISION_USE_INVITE` | Server-only | Optional; default invite **on** in production | `"false"` forces `createUser` without setup email (local smoke only) |
| `PLAYWRIGHT_*` | CI/local test only | Playwright | Port, base URL, browser path — **never production** |
| `POSTGRES_*` | Scripts only | `scripts/db-verify.ps1` generic Postgres path | Not used by Next.js app |
| `DOCKER_VERIFY_PORT` | Scripts only | Generic DB verify | Local Docker Postgres |
| `CI` | CI | GitHub Actions | Playwright retries / forbidOnly |
| `OLLI_SUPABASE_PROJECT_REF` | Operator-only | Cloud DB deploy / verify scripts | Must match `<ref>` in `NEXT_PUBLIC_SUPABASE_URL` |
| `OLLI_EXPECTED_MIGRATION_COUNT` | Operator-only | Pre-deploy gate | Defaults to current repo migration file count |
| `OLLI_RELEASE_GIT_SHA` | Operator-only | Pre-deploy gate | Optional pin to release commit |
| `OLLI_CONFIRM_PRODUCTION_DEPLOY` | Operator-only | **`db:production:migration-deploy` only** | Must be `yes` to apply Cloud migrations |
| `OLLI_CONFIRM_PRODUCTION_OPERATOR_ACTION` | Operator-only | `olli-operator.mjs` / `provision-customer-center.mjs` mutations against Cloud URL | Must be `yes` before mutating production Supabase via operator CLI |
| `OLLI_CONFIRM_SUBSCRIPTION_ACTION` | Operator-only | `olli-operator.mjs subscription *` | Must equal `activate`, `suspend`, `reactivate`, or `cancel` |
| `OLLI_CONFIRM_ORGANIZATION_ID` | Operator-only | Subscription mutations (recommended) | Must match resolved `--organization-id` when set |
| `OLLI_ALLOW_PREVIEW_PRODUCTION_SUPABASE` | Operator-only | Preview env-check override | `1` only with documented risk — default **deny** preview → production Supabase ref |
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

## Deployment tier model (authoritative)

| Tier | How inferred | Runtime validation |
|------|----------------|-------------------|
| **development** | Local `next dev`, or `OLLI_DEPLOYMENT_TIER=development` | No hosted fail-closed gate |
| **test / CI** | GitHub Actions + local Supabase; no production secrets | `test:env` only; Foundation CI uses `supabase status` |
| **preview** | `VERCEL_ENV=preview` or `OLLI_DEPLOYMENT_TIER=preview` | `validateHostedRuntimeEnv` — Cloud URL, no localhost canonical; **deny** production Supabase ref when `OLLI_PRODUCTION_SUPABASE_PROJECT_REF` set |
| **production** | `VERCEL_ENV=production` or `OLLI_DEPLOYMENT_TIER=production` | HTTPS canonical origin; required `OLLI_SUPABASE_PROJECT_REF`; Cloud Supabase URL; no `VERCEL_ENV=preview` masquerade |

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
OLLI_CENTER_PROVISION_USE_INVITE=true # default; omit = Owner invite email path
```

SMTP credentials for Supabase Auth email live **only** in the Supabase Dashboard (not application env). See [13 — Auth & SMTP procedure](./13-auth-smtp-operator-procedure.md).

## Leak verification (mandatory gates)

| Gate | Command / check |
|------|-----------------|
| Static audit | `npm run test:env` |
| Contract tests | `scripts/env-contract-smoke.mjs` (hosted tier fail-closed rules) |
| Build bundle scan | `test:env` walks `.next/static` for `service_role` when build exists |
| Repo pattern scan | `test:env` scans tracked tree for JWT / `sbp_` / postgres URL patterns (current tree; not full history) |
| Admin module | `src/lib/supabase/admin.ts` must keep `import "server-only"` |
| Pre-release | Production build on CI with `test:env` after `npm run build` |

## Service role usage (audit M8-T05)

| Location | Scope | Notes |
|----------|-------|-------|
| `src/lib/supabase/admin.ts` | App server runtime | **server-only**; used by staff/center provisioning Server Actions |
| `scripts/*-smoke.mjs`, `provision-customer-center.mjs` | Local CI / operator | Accept `supabase status` `SECRET_KEY` alias locally only |
| `scripts/db:production:*`, `app:production:*` | Operator | Requires explicit Cloud URL + confirmation gates |

User-scoped flows should continue using JWT + RLS; service role is not a substitute in product paths.

## Logging / errors

- Operator scripts print **names** of missing variables, never values (`app:production:env-check`, production gates).
- `/api/health` exposes tier, git SHA, canonical origin, and public env **status** — not `SUPABASE_SECRET_KEY`.
- Startup validation throws descriptive errors without dumping `process.env`.

## Gaps (remaining)

| Gap | Remediation task |
|-----|------------------|
| Remote smokes not wired in CI | M8-T09 — optional workflow job with secrets |
