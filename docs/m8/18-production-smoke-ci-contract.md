# M8-T09 — Production smoke & CI alignment

**Task:** M8-T09  
**Baseline SHA:** `90a7576f25a1345c9e16c4032f75c5db7322dae3`  
**Scope:** Repository acceptance — smoke gates, CI parity with release contracts, live procedure documentation (no live PASS from CI alone).

## Purpose

Prove the repository stays **deployable** and that M8 security, rate-limit, operator, and environment gates cannot silently disappear from release verification. Add a **small** critical route smoke suite without duplicating the full Playwright acceptance matrix.

## Architecture

```text
Focused gates (test:smoke:static, test:smoke)
        ↓
npm run verify  (full release gate — unchanged authority)
        ↓
GitHub Actions foundation-ci.yml (orchestration, not a second policy)
        ↓
Operator live smokes (post-deploy only)
```

| Layer | Command | When |
|-------|---------|------|
| Static repository smoke | `npm run test:smoke:static` | Every verify; CI after DB reset |
| Critical app smoke | `npm run test:smoke` | Pre-release spot-check; optional local |
| Full acceptance | `npm run verify` | Mandatory release candidate |
| Deployed host (read-only) | `OLLI_APP_BASE_URL=… npm run app:production:smoke` | After Vercel deploy |
| Supabase Cloud | `npm run db:production:smoke` | After linked migration deploy |

**Composition guards:** `scripts/lib/verify-gate-contract.mjs` and `scripts/lib/ci-workflow-contract.mjs` fail if mandatory commands are removed from `package.json#verify` or `.github/workflows/foundation-ci.yml`.

## Critical Playwright smoke (`test:smoke`)

Config: `playwright.smoke.config.ts`  
Spec: `tests/e2e/m8-production-critical-smoke.spec.ts`

| Scenario | Contract proved |
|----------|-----------------|
| Login entry + unauthenticated `/` redirect | Auth boundary wired |
| Owner + staff workspace shell | RBAC session + org resolution |
| `/users` Owner workspace; staff denied | Primary Owner invariant |
| `/subscription` Owner | M7 commercial UX surface |
| `/operations` daily view | Representative operational workspace |
| `/executive` overview | Representative reporting route |
| Active Owner leaves `/onboarding` | Onboarding gate (completed org) |
| Suspended Owner → `/subscription-status` | Commercial restriction path |

Does **not** replace domain acceptance specs under `tests/e2e/`.

## CI (`foundation-ci.yml`)

| Step | Notes |
|------|--------|
| Node **22**, `npm ci` | Matches `.nvmrc` / deploy docs |
| `supabase start` + `db reset` + SQL suites | Same as local `db:verify:supabase` intent |
| M8 gates | `test:env`, `test:security`, `test:rate-limit`, `test:operator`, `test:auth-redirect`, `test:smoke:static` |
| Build | `npm run build` (production path — not dev server alone) |
| Playwright | Full `test:app` against `next start` |

**Failure classification**

| Symptom | Likely class |
|---------|----------------|
| `supabase start` / Docker errors | Infrastructure / harness |
| `db reset` timeout | Infrastructure or migration SQL |
| `test:security` / static smokes | Product contract regression |
| Playwright auth timeout | Product or GoTrue load (investigate; no global retry inflation) |
| `npm run build` failure | Production build regression |

CI never runs operator **mutations** against production, never loads production secrets into workflow YAML, and never calls `OLLI_CONFIRM_PRODUCTION_*` pins.

## Local vs full verify

| Check | Requires Docker/Supabase |
|-------|---------------------------|
| `test:smoke:static` | No |
| `test:smoke` | Yes (Playwright webServer + local Supabase) |
| `npm run verify` | Yes |

## Live production smoke (pending until deploy)

Repository PASS does **not** imply production PASS.

### Application URL (`https://olli.riuda.click`)

```bash
OLLI_APP_BASE_URL=https://olli.riuda.click npm run app:production:smoke
```

Confirms health, login, unauthenticated redirect, static probe — **read-only**.

### Security headers (M8-T06)

After deploy, from an operator workstation:

```bash
curl -sI "https://olli.riuda.click/login"
```

Verify presence of: `Content-Security-Policy`, `X-Content-Type-Options: nosniff`, `Referrer-Policy`, `Permissions-Policy`, and on production tier `Strict-Transport-Security`. CSP must **not** list localhost / 127.0.0.1 dev origins.

### Rate limiting (M8-T07)

Do **not** run abusive load tests in CI. Post-deploy: a **small** number of intentional 429 responses on auth-adjacent routes using a designated test identity, confirming limiter activation and stable JSON error shape (see [16 — Rate limit contract](./16-rate-limit-abuse-contract.md)). Multi-instance / edge behavior remains a live gate.

### Operator tooling (M8-T08)

Live drill is **human-driven** ([17 — Operator runbook](./17-operator-tooling-runbook.md)):

1. `npm run operator:status -- --organization-id <test-org>` (read-only)
2. Provision **dedicated test center** only when approved
3. Subscription lifecycle mutations only with explicit `OLLI_CONFIRM_*` pins on a **non-customer** org

CI and repository smokes use local Supabase fixtures only.

## Database / migration contract

- Inventory: `npm run db:migrations:count` / `scripts/lib/migration-inventory.mjs`
- Optional release pin: `OLLI_EXPECTED_MIGRATION_COUNT` (see [03 — Environment contract](./03-environment-secrets-contract.md))
- T09 adds **no** migration

## Evidence for repository PASS

- `npm run test:smoke` PASS
- `npm run test:smoke:static` PASS (included in verify)
- M8 gates in verify: `test:env`, `test:security`, `test:rate-limit`, `test:operator`, `test:auth-redirect`
- `npm run verify` exit `0`
- `git diff --check` clean

## Evidence still required for production PASS

- Vercel production deploy + `/api/health` `gitSha`
- `app:production:smoke` on canonical URL
- Header spot-check, SMTP, Auth Site URL, DNS/TLS
- Supabase Cloud migration smoke
- Operator live drill on designated test org
- Rate-limit / WAF live behavior
