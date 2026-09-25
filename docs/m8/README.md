# M8 — Production Readiness & Release Architecture

**Milestone:** M8 — Safe, repeatable production deployment  
**Status:** In progress (T02 Supabase pipeline implemented; T03 app hosting contract implemented; cloud + live hosting acceptance pending RIUDA credentials)

M7 closed with a **commercially ready application** verified entirely against **local Supabase + dev fixtures**. M8 does not change M1–M7 domain semantics; it defines and implements the path to **`https://olli.riuda.click`** (or equivalent staging) backed by a **hosted Supabase production project**.

## Documents

| Doc | Purpose |
|-----|---------|
| [01 — T01 audit & design gate](./01-m8-t01-production-readiness-audit-design.md) | Baseline, findings, gap register, T01 verdict |
| [02 — Target production architecture](./02-target-production-architecture.md) | Hosting, Supabase, boundaries, services |
| [03 — Environment & secrets contract](./03-environment-secrets-contract.md) | Variables, separation, leak rules |
| [04 — Database deployment contract](./04-database-deployment-migration-contract.md) | Migrations, types, bootstrap, drift |
| [05 — Auth & domain contract](./05-auth-domain-contract.md) | DNS, HTTPS, redirects, RLS/service role |
| [06 — Backup & recovery contract](./06-backup-recovery-contract.md) | RPO/RTO, restore, safeguards |
| [07 — Observability contract](./07-observability-contract.md) | Errors, logs, health, monitoring minimum |
| [08 — Release & rollback runbook](./08-release-rollback-runbook.md) | Gates, sequence, smoke, rollback |
| [09 — Risk register](./09-risk-register.md) | Blocker / high / medium / low |
| [10 — Task roadmap (T02–closeout)](./10-m8-task-roadmap.md) | Implementation sequence after T01 |
| [11 — Supabase production operator procedure](./11-supabase-production-operator-procedure.md) | Link, migrate, drift, smoke (M8-T02) |
| [12 — Application deployment operator procedure](./12-application-deployment-operator-procedure.md) | Vercel deploy, env, smokes, rollback (M8-T03) |

## Authoritative upstream

- [M7 commercialization contract](../m7/06-m7-commercialization-milestone-contract.md)
- [M7 closeout](../m7/08-m7-t08-final-milestone-closeout.md)
- [M0 auth application flow](../m0/24-auth-application-flow.md)
- [M0 architecture baseline](../m0/30-architecture-baseline.md)
