# M8 — Backup & Recovery Contract

**Scope:** Supabase Cloud PostgreSQL (includes Auth schema managed by Supabase). Application host is stateless.

**Operational runbook (M8-T10):** [19 — Backup, restore & DR drill](./19-backup-restore-dr-runbook.md)

## Rebuild vs restore

| | Rebuild | Restore |
|---|---------|---------|
| **Mechanism** | `supabase db reset` + migrations (+ local `seed.sql` only in dev) | Supabase backup / PITR / logical `pg_dump` restore |
| **Customer data** | Not recovered | Must be recovered |
| **Proves** | Schema reproducibility | Business continuity |

Repository acceptance uses a **local synthetic restore rehearsal** (`npm run test:recovery`); it does not replace a hosted production restore drill.

## Backup strategy (target)

| Asset | Method | Owner |
|-------|--------|-------|
| **Database** | Supabase automated daily backups (plan-dependent) + optional manual snapshot before migration | RIUDA / operator |
| **Auth users** | Included in Postgres backup when using platform restore; coordinate Auth drift per runbook §Auth | Supabase / RIUDA |
| **Application** | Git tags + deploy host rollback | RIUDA |
| **Secrets** | Host + Supabase vault; documented recovery in password manager | RIUDA |

## RPO / RTO (operational targets — confirm on Cloud plan)

| Metric | Target assumption | Notes |
|--------|-------------------|-------|
| **RPO** | ≤ 24 hours (daily backup tier) or ≤ 1 hour if PITR enabled | **Must confirm** Supabase subscription tier — not proven in repo |
| **RTO** | 4–8 hours for full restore + migration re-verify | **Pending** timed staging drill |
| **App-only rollback** | Minutes | Redeploy previous Next.js artifact; DB unchanged |

## Restore procedure (outline)

1. **Declare incident** — app corrupt vs DB corrupt vs bad migration vs operator error ([19 — Decision tree](./19-backup-restore-dr-runbook.md)).
2. **Stop writes** — disable deploy hooks; use operator/domain containment before break-glass SQL.
3. **Database restore** — Supabase Dashboard → restore to new project or point-in-time (per plan).
4. **Re-link** — update `NEXT_PUBLIC_*` and `SUPABASE_SECRET_KEY` on app host if project ref changes.
5. **Schema verification** — migration version matches git tag; run staging smokes (M8-T09).
6. **Recovery verification** — Primary Owner login, `fetch_session_commercial_access`, domain spot checks ([19 — Checklist](./19-backup-restore-dr-runbook.md)).

Exact Dashboard steps: record during first **staging restore drill** (live evidence pending).

## Destructive-operation safeguards

| Operation | Rule |
|-----------|------|
| `supabase db reset` | **Local/CI only** |
| `seed.sql` on remote | **Forbidden** |
| Repository restore drill default target | **Local isolated database only** |
| `deleteUser` compensation (provisioning) | Application code only on failed finalize — not operator routine |
| `cancel_organization_subscription` | Operator RPC — irreversible terminal state (M7); require runbook checkbox |
| Drop migration history | **Forbidden** without architecture review |
| Commit database dumps | **Forbidden** |

## Repository tooling (M8-T10)

| Command | Role |
|---------|------|
| `npm run backup:check` | Readiness static audit |
| `npm run restore:drill` | Local synthetic backup/restore rehearsal |
| `npm run test:recovery` | Release gate — guards + drill |

## Status

| Item | Repository | Live |
|------|------------|------|
| Recovery inventory & runbook | **Done (M8-T10)** | — |
| Local synthetic restore drill | **Done (M8-T10)** | — |
| Supabase backup tier / retention | Documented | **Pending verification** |
| Staging/production restore drill | — | **Pending (H-04 residual)** |
