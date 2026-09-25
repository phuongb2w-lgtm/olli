# M8 — Risk Register

Each row: **current behavior → production risk → remediation → proposed task → affected layers**.

Legend: **S** schema, **P** product code, **I** infrastructure, **D** docs/runbook

---

## Blocker

| ID | Current behavior | Production risk | Remediation | Task | Layers |
|----|------------------|-----------------|-------------|------|--------|
| **B-01** | ~~No hosting/deploy config in repository~~ | Application cannot ship | **Addressed M8-T03** — Vercel contract, gates, `/api/health`, [12 — Procedure](./12-application-deployment-operator-procedure.md) | **M8-T03 done (live pending)** | I, D |
| **B-02** | ~~No linked Supabase production project documented~~ | No authoritative DB/Auth until RIUDA runs Cloud acceptance | Repo workflow: [11 — Operator procedure](./11-supabase-production-operator-procedure.md); **`npm run db:production:*`** | **M8-T02 done (cloud pending)** | I, D |
| **B-03** | ~~Center provision creates Auth user without password; no reset UI~~ | Owner cannot log in after provision | **Addressed M8-T04 (repo):** Owner `inviteUserByEmail` + `/forgot-password` / `/update-password`; live SMTP pending | **M8-T04 done (live pending)** | P, D, I |
| **B-04** | Staff invite requires SMTP + redirect allowlist | Staff never receive credentials if SMTP missing | **Addressed M8-T04 (repo):** `redirectTo` callback; configure Supabase SMTP | **M8-T04 done (live pending)** | I, D |
| **B-05** | Subscription activate/suspend only in test smokes, no operator CLI doc | Centers stuck in `provisioning` | Operator script/runbook wrapping service_role RPCs | M8-T08 | D, P |

---

## High

| ID | Current behavior | Production risk | Remediation | Task | Layers |
|----|------------------|-----------------|-------------|------|--------|
| **H-01** | `foundation-ci.yml` ≠ full `npm run verify` | Regressions merge undetected | Extend CI or mandatory pre-release verify | M8-T09 | I, D |
| **H-02** | ~~No health endpoint / external uptime~~ | Outages unnoticed | **`GET /api/health`** (M8-T03); external monitor wiring M8-T07 | M8-T07 | P, I |
| **H-03** | ~~No CSP / incomplete headers~~ | XSS, clickjacking, MIME sniffing | **Addressed M8-T06 (repo):** enforced CSP + centralized headers ([15](./15-security-headers-csp-contract.md)); live header spot-check pending deploy | **M8-T06 done (live pending)** | P, D |
| **H-04** | No backup/restore drill | Unknown RTO; migration fear | Staging restore exercise | M8-T10 | D, I |
| **H-05** | Auth Site URL localhost in local config only — easy to misconfigure cloud | Redirect loops / auth failure | Production checklist + staging validation | M8-T03, M8-T04 | D, I |
| **H-06** | `createAdminClient` in Server Actions for provisioning | Service role on app server — correct but high impact if leaked | **Addressed M8-T05 (repo):** server-only + rotation SOP + import audit | **M8-T05 done** | P, D |

---

## Medium

| ID | Current behavior | Production risk | Remediation | Task | Layers |
|----|------------------|-----------------|-------------|------|--------|
| **M-01** | Playwright uses `OLLI_STAFF_PROVISION_USE_INVITE=false` | None in prod if env correct | **Addressed M8-T05** — `.env.example` documents production default | **M8-T05** | D |
| **M-02** | ~~`test:env` bundle grep uses Windows-fragile shell~~ | Weaker leak detection on some dev machines | **Addressed M8-T05** — Node file walk of `.next/static` | **M8-T05 done** | P |
| **M-03** | ~~No app-side rate limiting on auth / invite / Owner admin surfaces~~ | Credential stuffing, email amplification | **Addressed M8-T07 (repo):** Postgres-backed limits ([16](./16-rate-limit-abuse-contract.md)); live edge/WAF exercise pending | **M8-T07 done (live pending)** | P, S, D |
| **M-04** | No dependency audit in verify | CVE drift | Add `npm audit` gate or Dependabot policy | M8-T06 | I |
| **M-05** | Storage disabled — no file uploads | Future feature surprise | Keep disabled until designed | — | D |
| **M-06** | Long verify (~30–45 min) | Release friction | Parallel CI jobs; keep full gate pre-release | M8-T09 | I |
| **M-07** | ~~Operator must manually set Owner password (documented M7-T02)~~ | Support load | **Addressed M8-T04** — Owner invite email path | **M8-T04** | P |

---

## Low

| ID | Current behavior | Production risk | Remediation | Task | Layers |
|----|------------------|-----------------|-------------|------|--------|
| **L-01** | README verify counts outdated (80 vs 216 Playwright) | Onboarding confusion | Update README in docs pass | M8-T12 | D |
| **L-02** | Security inventory doc stale (M0 table counts) | Review noise | Regenerate optional | M8-T12 | D |
| **L-03** | `enable_signup = false` — no self-serve | Expected for B2B | Document | M8-T04 | D |
| **L-04** | Single region Supabase | Latency for distant users | Accept for MVP | — | D |
| **L-05** | Staging hostname optional | Test in prod risk | Documented staging pattern in [12](./12-application-deployment-operator-procedure.md) §5 | **M8-T03 docs** | I |

---

## Explicit non-risks (M7 closed)

- Commercial enforcement, seat limits, provisioning idempotency — **implemented and verified**.
- Payment/checkout absence — **intentional deferral**, not a deployment blocker.
- Dev seed dependency for product — **false**; production uses migrations + operator provision.
