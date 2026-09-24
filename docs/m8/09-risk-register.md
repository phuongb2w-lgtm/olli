# M8 — Risk Register

Each row: **current behavior → production risk → remediation → proposed task → affected layers**.

Legend: **S** schema, **P** product code, **I** infrastructure, **D** docs/runbook

---

## Blocker

| ID | Current behavior | Production risk | Remediation | Task | Layers |
|----|------------------|-----------------|-------------|------|--------|
| **B-01** | No hosting/deploy config in repository | Application cannot ship | Select host; add deploy pipeline + env injection | M8-T03 | I, D |
| **B-02** | No linked Supabase production project documented | No authoritative DB/Auth | Create project; `db push` 58 migrations; lint | M8-T02 | I, D |
| **B-03** | Center provision creates Auth user without password; no reset UI | Owner cannot log in after provision | Invite + SMTP or reset flow or operator password SOP | M8-T04 | P, D, I |
| **B-04** | Staff provisioning defaults to email invite; local disables via env | Staff never receive credentials if SMTP missing | Configure Supabase SMTP; verify invite redirect | M8-T04 | I, D |
| **B-05** | Subscription activate/suspend only in test smokes, no operator CLI doc | Centers stuck in `provisioning` | Operator script/runbook wrapping service_role RPCs | M8-T08 | D, P |

---

## High

| ID | Current behavior | Production risk | Remediation | Task | Layers |
|----|------------------|-----------------|-------------|------|--------|
| **H-01** | `foundation-ci.yml` ≠ full `npm run verify` | Regressions merge undetected | Extend CI or mandatory pre-release verify | M8-T09 | I, D |
| **H-02** | No health endpoint / external uptime | Outages unnoticed | `/health` + monitor | M8-T07 | P, I |
| **H-03** | No security headers in `next.config.ts` | Clickjacking, MIME sniffing | Add baseline headers / CSP report-only first | M8-T06 | P |
| **H-04** | No backup/restore drill | Unknown RTO; migration fear | Staging restore exercise | M8-T10 | D, I |
| **H-05** | Auth Site URL localhost in local config only — easy to misconfigure cloud | Redirect loops / auth failure | Production checklist + staging validation | M8-T03, M8-T04 | D, I |
| **H-06** | `createAdminClient` in Server Actions for provisioning | Service role on app server — correct but high impact if leaked | Keep server-only; rotate key procedure; audit imports | M8-T05 | P, D |

---

## Medium

| ID | Current behavior | Production risk | Remediation | Task | Layers |
|----|------------------|-----------------|-------------|------|--------|
| **M-01** | Playwright uses `OLLI_STAFF_PROVISION_USE_INVITE=false` | None in prod if env correct | Document production must **not** set false | M8-T05 | D |
| **M-02** | `test:env` bundle grep uses Windows-fragile shell | Weaker leak detection on some dev machines | Harden script cross-platform | M8-T05 | P |
| **M-03** | No rate limiting on login Server Action | Credential stuffing | Host WAF or Supabase rate limits | M8-T06 | I, P |
| **M-04** | No dependency audit in verify | CVE drift | Add `npm audit` gate or Dependabot policy | M8-T06 | I |
| **M-05** | Storage disabled — no file uploads | Future feature surprise | Keep disabled until designed | — | D |
| **M-06** | Long verify (~30–45 min) | Release friction | Parallel CI jobs; keep full gate pre-release | M8-T09 | I |
| **M-07** | Operator must manually set Owner password (documented M7-T02) | Support load | Productize invite or reset | M8-T04 | P |

---

## Low

| ID | Current behavior | Production risk | Remediation | Task | Layers |
|----|------------------|-----------------|-------------|------|--------|
| **L-01** | README verify counts outdated (80 vs 216 Playwright) | Onboarding confusion | Update README in docs pass | M8-T12 | D |
| **L-02** | Security inventory doc stale (M0 table counts) | Review noise | Regenerate optional | M8-T12 | D |
| **L-03** | `enable_signup = false` — no self-serve | Expected for B2B | Document | M8-T04 | D |
| **L-04** | Single region Supabase | Latency for distant users | Accept for MVP | — | D |
| **L-05** | No staging hostname yet | Test in prod risk | Staging DNS in T03 | M8-T03 | I |

---

## Explicit non-risks (M7 closed)

- Commercial enforcement, seat limits, provisioning idempotency — **implemented and verified**.
- Payment/checkout absence — **intentional deferral**, not a deployment blocker.
- Dev seed dependency for product — **false**; production uses migrations + operator provision.
