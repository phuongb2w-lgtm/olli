# M8-T01 — Production Readiness Audit & Release Architecture Gate

**Milestone:** M8 — Production Readiness & Release Architecture  
**Task:** M8-T01 — Audit & design gate (**no production implementation**)  
**Baseline:** `main` @ `5c6bdb4858d4bfe94f292d15eb8e731038406508`  
**Migrations:** 58  
**M7:** CLOSED / PASS ([closeout](../m7/08-m7-t08-final-milestone-closeout.md))  
**Trusted product verification (baseline):** Playwright 216/216, i18n 1953/1953, `npm run verify` exit 0

T01 adds **documentation only**. No schema, product, or infrastructure changes.

---

## A. Repository baseline

| Item | Value |
|------|--------|
| **SHA** | `5c6bdb4858d4bfe94f292d15eb8e731038406508` |
| **Branch** | `main` |
| **Working tree** | Clean at T01 closeout |
| **Migrations** | 58 files under `supabase/migrations/` |

### T01 verification performed

| Check | Result |
|-------|--------|
| Branch / SHA / migration count | Confirmed via git |
| Code & config inspection | Deployment, env, auth, DB, security surfaces (see sections B–L) |
| `npm run test:env` | PASS (T01 closeout) |
| Full `npm run verify` | **Not re-run in T01** — M7-T08 baseline trusted per M7-T01 precedent; **mandatory before M8-T12** |

---

## B. Current production readiness assessment

### Ready (no M8 code change required to preserve)

| Area | Evidence |
|------|----------|
| **Domain model & RLS** | 58 migrations; full `db:verify` chain in `scripts/supabase-verify.ps1` |
| **Commercial layer (M7)** | Provisioning, subscription, access enforcement, Owner UX — contract [06](../m7/06-m7-commercialization-milestone-contract.md) |
| **Secrets discipline** | `server-only` admin client; `test:env` guards client bundles |
| **Operator center onboarding path** | `scripts/provision-customer-center.mjs` + `src/lib/center-provisioning/orchestrate.ts` |
| **Staff provisioning** | Server Action + invite/createUser split (`OLLI_STAFF_PROVISION_USE_INVITE`) |
| **Local reproducibility** | `supabase start`, `npm run verify`, documented bootstrap [README](../../README.md) |

### Not ready (expected — M8 scope)

| Area | Gap summary |
|------|-------------|
| **Hosting** | No Vercel/Docker/IaC; app runs only via local/CI `next start` |
| **Supabase Cloud** | `project_id = olli-local` only; no linked production ref in repo |
| **Domain / Auth URLs** | Localhost in `supabase/config.toml`; production `olli.riuda.click` not wired |
| **Owner first login** | Auth user created without password; no reset UI (M0 deferral + M7-T02 note) |
| **SMTP** | Inbucket locally; production mail unset |
| **Observability** | No health check, APM, or structured logging |
| **Security headers** | Empty `next.config.ts` beyond next-intl |
| **Operator subscription CLI** | RPCs exist; only smoke tests demonstrate usage |
| **Backup/restore** | Supabase platform feature only — no Olli runbook |
| **CI parity** | `foundation-ci.yml` runs M0 SQL subset + 8 Playwright scenarios vs full verify |

**Summary:** The **product** is commercially and technically verified **in local/staging-equivalent fixtures**. **Production deployment** is undefined — by design until M8 implementation.

---

## C. Target production architecture

See **[02 — Target production architecture](./02-target-production-architecture.md)**.

**Decision summary:** Single Next.js 16 app + Supabase Cloud Postgres/Auth/PostgREST; RIUDA operates service_role provisioning and subscription lifecycle; center staff use password auth and RLS-scoped JWT.

---

## D. Contract documents (T01 deliverables)

| # | Deliverable | Document |
|---|-------------|----------|
| 3 | Environment & secrets | [03-environment-secrets-contract.md](./03-environment-secrets-contract.md) |
| 4 | Database deployment | [04-database-deployment-migration-contract.md](./04-database-deployment-migration-contract.md) |
| 5 | Auth & domain | [05-auth-domain-contract.md](./05-auth-domain-contract.md) |
| 6 | Backup & recovery | [06-backup-recovery-contract.md](./06-backup-recovery-contract.md) |
| 7 | Observability | [07-observability-contract.md](./07-observability-contract.md) |
| 8 | Release & rollback | [08-release-rollback-runbook.md](./08-release-rollback-runbook.md) |
| 9 | Risk register | [09-risk-register.md](./09-risk-register.md) |
| 10 | Task roadmap | [10-m8-task-roadmap.md](./10-m8-task-roadmap.md) |

---

## E. Audit by area (minimum 12)

### 1. Deployment architecture

| Topic | Finding |
|-------|---------|
| Frontend/runtime | Next.js 16 App Router; `npm run build` / `start`; no host manifest |
| Supabase | Local Docker stack; production = separate Cloud project (T02) |
| Topology | Browser → Next (RSC/Actions) → Supabase Auth + PostgREST; no BFF beyond Next |
| Boundaries | User JWT via SSR cookies; service role only in `admin.ts` orchestration paths |
| Required services | App host, Supabase Cloud, DNS, SMTP |

### 2. Domain and routing

| Topic | Finding |
|-------|---------|
| Intended domain | `olli.riuda.click` (per M8 charter) |
| DNS | Not configured in repo — RIUDA operator (T03/T04) |
| HTTPS | Required; assumed at app host |
| Auth redirects | Must set Site URL + allowlist to production origin ([05](./05-auth-domain-contract.md)) |
| Origins | `NEXT_PUBLIC_SUPABASE_URL` must match linked project |

### 3. Environment and secrets

Full inventory in [03](./03-environment-secrets-contract.md). Application runtime uses **three** production variables minimum (2 public + secret). Local-only: `supabase status`, Playwright env, Postgres docker scripts.

### 4. Database production lifecycle

[04](./04-database-deployment-migration-contract.md): apply 58 migrations in order; reference data in migrations; **never** `seed.sql`; types regenerated after schema change; failure stops deploy.

### 5. Authentication and authorization

- Production auth: email/password sign-in only in UI.
- RLS + M7 commercial gate unchanged.
- Service role: center/staff provisioning orchestration, operator subscription RPCs.
- Owner/staff boundaries per M7 contract.
- **Blockers:** Owner password path, SMTP (B-03, B-04).

### 6. Backup / recovery

[06](./06-backup-recovery-contract.md): rely on Supabase backups + stateless app rollback; drill deferred to T10.

### 7. Observability

[07](./07-observability-contract.md): greenfield for M8-T07.

### 8. Security hardening

| Topic | Current | Target task |
|-------|---------|-------------|
| Headers / CSP | None in Next config | M8-T06 |
| Cookies | Supabase SSR + locale `lax` | Verify `Secure` on HTTPS (T04) |
| CORS | Supabase-managed | Confirm project settings |
| Error leakage | Coarse auth errors | Maintain in hardening |
| Rate limits | None app-side | M8-T06 / WAF |
| Dependency audit | Not in verify | M8-T06 |

### 9. Release procedure

[08](./08-release-rollback-runbook.md): pre-release = full `npm run verify`; migrate DB before app; post-deploy smokes P-1–P-6.

### 10. Operational ownership

| Action | RIUDA / operator (service_role) | Primary Owner | Staff |
|--------|----------------------------------|---------------|-------|
| Create center + Owner | `provision-customer-center.mjs` | — | — |
| Activate / suspend subscription | RPC via service_role | — | — |
| Complete center setup | — | `complete_center_setup()` | — |
| Provision staff | — | UI → Server Action | — |
| Sign in | — | Yes | Yes (if commercially active) |
| Plan change | `change_organization_commercial_plan` RPC | — | — |
| DNS / TLS / Supabase dashboard | RIUDA | — | — |
| Deploy app / migrations | RIUDA | — | — |

### 11. Existing technical assumptions (localhost / dev)

| Assumption | Location | Production impact |
|------------|----------|-------------------|
| API URL `127.0.0.1:54421` | `.env.example`, `config.toml` | Replace with Cloud URL |
| Dev auth users + passwords | `seed-auth-users.mjs`, `seed.sql` | Must not exist in prod Auth |
| Staff invite off in tests | `playwright-webserver.mjs` | Prod must use invites + SMTP |
| Center Owner `createUser` confirmed, no password | `center-provisioning/orchestrate.ts` | Operator/password policy required |
| Fixed UUID fixtures | `seed.sql` | Tests only |
| Docker container name `supabase_db_olli-local` | verify scripts | Local only |
| `enable_signup = false` | config.toml | Match in Cloud |

No mock/dev behavior found that **must** ship for product correctness except explicit test env flags.

### 12. Regression protection

| Gate | Status |
|------|--------|
| `npm run db:verify` | Mandatory for schema changes |
| `npm run verify` | Mandatory pre-release (all M0–M7 smokes + 216 Playwright + i18n + env + lint + typecheck + build) |
| Production smokes | To add M8-T09 — **additive** |
| Weaken verify | **Forbidden** |

---

## F. Gap table (representative)

| Current behavior | Production risk | Remediation | Task | Affected |
|------------------|-----------------|-------------|------|----------|
| No cloud Supabase | No DB | Create + push migrations | T02 | I, D |
| No app host | Unreachable | Deploy staging/prod | T03 | I |
| Owner without password | Cannot login | Invite/reset/SOP | T04 | P, I, D |
| No SMTP | Invites fail | Configure Auth mail | T04 | I |
| No subscription CLI | Stuck provisioning | Operator script | T08 | P, D |
| CI < verify | Miss regressions | CI policy | T09 | I |
| No health/metrics | Silent outage | Health + monitor | T07 | P, I |

Full list: [09 — Risk register](./09-risk-register.md).

---

## G. M8 task breakdown

See **[10 — Task roadmap](./10-m8-task-roadmap.md)** (T02–T12).

---

## H. GO / NO-GO recommendation

| Question | Verdict |
|----------|---------|
| **Begin M8-T02 implementation?** | **GO** — Audit complete; blockers classified; target architecture and contracts written; no prerequisite schema hotfix. |
| **Production cutover / customer traffic?** | **NO-GO** until B-01–B-05 cleared and T11 acceptance met. |

**Rationale:** Same pattern as M7-T01: the codebase is **fit for the next milestone’s work**; production rollout is explicitly **not** ready until infrastructure and auth/mail gaps close.

---

## I. T01 exit criteria

| Criterion | Status |
|-----------|--------|
| Audit complete (12 areas) | **PASS** |
| Target architecture unambiguous | **PASS** ([02](./02-target-production-architecture.md)) |
| Blockers classified | **PASS** ([09](./09-risk-register.md)) |
| M8 roadmap written | **PASS** ([10](./10-m8-task-roadmap.md)) |
| No accidental product/schema change | **PASS** (docs only) |
| Migration count still 58 | **PASS** (unchanged) |
| Final baseline SHA | `5c6bdb4858d4bfe94f292d15eb8e731038406508` |

**Closeout note:** T01 deliverables live under `docs/m8/`. Commit them on `main` to satisfy “repository clean” for milestone bookkeeping; product/schema SHA remains unchanged aside from documentation.

---

## J. T01 status

**M8-T01 — CLOSED / PASS** (audit evidence and roadmap complete; implementation begins at M8-T02).
