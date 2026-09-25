# M8 — Application Deployment Operator Procedure (M8-T03)

**Canonical production URL:** `https://olli.riuda.click`  
**Hosting target:** [Vercel](https://vercel.com) (Next.js 16 native adapter) — see [`vercel.json`](../../vercel.json)  
**Database / Auth:** Supabase Cloud — [11 — Supabase operator procedure](./11-supabase-production-operator-procedure.md)

This procedure covers **application hosting only**. Schema apply remains **`npm run db:production:*`** (M8-T02). DNS cutover and Supabase Auth dashboard mail settings are **M8-T04**.

---

## 1. Prerequisites

| Item | Requirement |
|------|-------------|
| Git release | `main` at known SHA; working tree clean |
| Local gates | `npm run app:production:predeploy-gate` |
| DB gates | `npm run db:production:predeploy-gate` (+ remote when linked) |
| Vercel project | Linked to RIUDA GitHub repo; **Production** env scoped secrets |
| Domain | `olli.riuda.click` assigned to **Production** deployment (T04 validates TLS) |
| Node | **22.x** (see [`.nvmrc`](../../.nvmrc), CI, `package.json` `engines`) |

---

## 2. Production environment variables (Vercel)

Configure under **Project → Settings → Environment Variables**. Scope secrets to **Production** only unless noted.

| Variable | Scope | Required |
|----------|-------|----------|
| `NEXT_PUBLIC_SUPABASE_URL` | Production (+ Preview if staging DB) | Yes |
| `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` | Production (+ Preview if staging DB) | Yes |
| `SUPABASE_SECRET_KEY` | Production (+ Preview if staging DB) | Yes |
| `NEXT_PUBLIC_OLLI_CANONICAL_APP_ORIGIN` | Production | Yes — `https://olli.riuda.click` |
| `OLLI_SUPABASE_PROJECT_REF` | Production | Yes — must match Supabase URL |
| `OLLI_DEPLOYMENT_TIER` | Production | Recommended — `production` |
| `OLLI_PRODUCTION_SUPABASE_PROJECT_REF` | Preview | Recommended — blocks preview → prod DB |
| `OLLI_STAFF_PROVISION_USE_INVITE` | Production | Omit or `true` |
| `OLLI_HEALTH_CHECK_SUPABASE` | Production | Optional — `1` enables dependency ping in `/api/health` |

**Never** set `SUPABASE_SECRET_KEY` or `OLLI_CONFIRM_PRODUCTION_DEPLOY` on Preview if Preview uses a shared machine — Preview must use a **staging Supabase project**, not production.

**Operator CLI:** [17 — Operator runbook](./17-operator-tooling-runbook.md) — `olli-operator.mjs` / `provision-customer-center.mjs` against Cloud Supabase requires `OLLI_CONFIRM_PRODUCTION_OPERATOR_ACTION=yes` (see [03 — Environment contract](./03-environment-secrets-contract.md)).

Verify from an operator workstation with secrets loaded:

```bash
npm run app:production:env-check
```

---

## 3. Supabase Auth dashboard checklist (production project)

Configure **before** first Owner/staff login on production (full mail/DNS in M8-T04):

| Setting | Value |
|---------|--------|
| **Site URL** | `https://olli.riuda.click` |
| **Redirect URLs** | `https://olli.riuda.click/**` (confirm glob syntax in Supabase UI) |
| **Enable signup** | Off |
| **JWT expiry** | Align with product session UX (local default 3600s) |

Do **not** copy `http://127.0.0.1:54421` from local `supabase/config.toml`.

Staff `inviteUserByEmail` redirects use Supabase Site URL — preview hostnames must **not** be set as Site URL on the production Auth project.

---

## 4. Release sequence (application)

1. Identify release SHA on `main`; tag or record `OLLI_RELEASE_GIT_SHA`.
2. Run **`npm run verify`** on that SHA locally (mandatory release gate).
3. Run **`npm run db:production:predeploy-gate`**; apply DB migrations per [11](./11-supabase-production-operator-procedure.md) if schema changed.
4. Run **`npm run app:production:predeploy-gate`**  
   Optional hosted env: `OLLI_APP_PREDEPLOY_INCLUDE_HOST_ENV=1 npm run app:production:predeploy-gate`
5. Deploy via Vercel:
   - **Normal path:** push to `main` → Production deployment from [`vercel.json`](../../vercel.json) (`npm ci` → `npm run build`).
   - **Manual:** Vercel Dashboard → Deploy → select SHA.
6. Confirm deployment metadata: `GET https://olli.riuda.click/api/health` → `gitSha`, `status: ok`.
7. Run production-safe smokes:

```bash
OLLI_APP_BASE_URL=https://olli.riuda.click npm run app:production:smoke
```

8. Record deployed SHA + operator initials (spreadsheet / runbook log until M8-T08 tooling).

---

## 5. Preview / staging safety

| Risk | Mitigation |
|------|------------|
| Preview uses production Supabase | Set **`OLLI_PRODUCTION_SUPABASE_PROJECT_REF`** on Preview; env-check fails if preview URL ref matches |
| Preview becomes Auth Site URL | Keep Site URL on canonical production origin only |
| Production service role on Preview | Scope Vercel secrets: Production ≠ Preview |
| Destructive smokes | **`app:production:smoke`** is read-only; do **not** run Playwright/`seed.sql` against production |

Recommended: **`olli-staging.riuda.click`** Preview/Staging project + dedicated staging Supabase (see [02 — Architecture](./02-target-production-architecture.md)).

To disable automatic Preview deployments: Vercel → Git → uncheck “Preview” for branches, or restrict deploy hooks to `main` only.

---

## 6. Health & version identification

| Endpoint | Purpose |
|----------|---------|
| `GET /api/health` | Liveness + safe deployment identity (`gitSha`, `tier`, `canonicalOrigin`) |

- Returns **503** with `status: degraded` when public Supabase env is missing/invalid or optional Supabase ping fails.
- Does **not** return secrets, tokens, or user data.
- Excluded from session proxy matcher for cheap monitoring.

---

## 7. Rollback (application-only)

When DB schema unchanged and regression is app-only:

1. Vercel → Deployments → previous **Production** deployment → **Promote to Production**.
2. Re-run **`npm run app:production:smoke`** against `OLLI_APP_BASE_URL`.
3. If bad migration was applied, **do not** roll back app alone — follow [08 — Runbook](./08-release-rollback-runbook.md) DB restore path.

---

## 8. Build contract (reproducible)

```bash
npm ci
npm run build
npm run start   # local smoke of production server binary
```

Build embeds `OLLI_GIT_SHA` / `VERCEL_GIT_COMMIT_SHA` for `/api/health`. Production runtime validates cloud Supabase env when `VERCEL_ENV=production` or `OLLI_DEPLOYMENT_TIER=production` (`src/instrumentation.ts`).

---

## 9. Live acceptance status

Repository implementation can be **COMPLETE** while **live hosting acceptance** remains **PENDING** until RIUDA:

- Creates Vercel project + secrets
- Assigns `olli.riuda.click`
- Runs §4 steps 6–7 successfully against production

Do not claim live production PASS without evidence from §6–7.
