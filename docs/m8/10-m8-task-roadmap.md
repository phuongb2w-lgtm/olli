# M8 — Task Roadmap (T02 → Closeout)

**Prerequisite:** M8-T01 audit **PASS** (this milestone gate).  
**Rule:** Preserve M1–M7 semantics; no billing/checkout scope; no staff-limit semantic changes.

| Task | Title | Primary deliverables | Acceptance |
|------|--------|----------------------|------------|
| **M8-T02** | Supabase production project & migration pipeline | **Done (repo):** [11 — Operator procedure](./11-supabase-production-operator-procedure.md), `db:production:*` scripts, `.env.production.example` | **Cloud acceptance:** 58 migrations applied; no seed; lint + smoke clean on linked project |
| **M8-T03** | Application hosting & deploy topology | **Done (repo):** Vercel, gates, `/api/health`, [12 — Procedure](./12-application-deployment-operator-procedure.md) | **Live acceptance:** production deploy + smokes on `olli.riuda.click` |
| **M8-T04** | Domain, TLS, Auth & mail | `olli.riuda.click` DNS; Supabase Site URL/redirects; SMTP; Owner first-login policy | Owner + staff auth paths work on staging |
| **M8-T05** | Environment & secrets hardening | `.env.production.example`; `OLLI_*` docs; cross-platform `test:env`; key rotation SOP | `test:env` pass; no secret in client bundle |
| **M8-T06** | Security hardening | Security headers; CSP baseline; abuse/rate-limit notes; audit dependency gate | Headers verified; login surface reviewed |
| **M8-T07** | Observability & health | Health route; structured server logging; uptime monitor hook | Alert on staging failure drill |
| **M8-T08** | Operator tooling & runbooks | CLI/scripts: `activate_organization_subscription`, suspend/reactivate/cancel; provision center doc | RIUDA can onboard center without Dashboard SQL |
| **M8-T09** | Production smoke & CI alignment | Remote smoke suite; optional CI job; **full verify** remains release gate | Staging smokes green; CI policy documented |
| **M8-T10** | Backup, restore & migration failure drill | Executed restore on staging; RPO/RTO recorded | Recovery checklist signed |
| **M8-T11** | Production cutover | Execute [08 — Runbook](./08-release-rollback-runbook.md) on production | P-1–P-6 smokes; first real center provision |
| **M8-T12** | M8 closeout | Acceptance matrix, README, final SHA, `npm run verify` | M8 CLOSED/PASS |

## Suggested dependency order

```
T02 ──┬──> T04 ──> T09 ──> T11
T03 ──┘      │
             v
      T05, T06, T07 (parallel after T03)
             │
T08 ─────────┴──> T11
T10 ────────────> T11 (before prod)
T12 after T11 verify
```

## Out of scope (carry forward)

Payment provider, checkout, operator commercial console UI, full `/settings` org profile, multi-region HA.
