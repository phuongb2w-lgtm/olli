# M8 — Backup & Recovery Contract

**Scope:** Supabase Cloud PostgreSQL (includes Auth schema managed by Supabase). Application host is stateless.

## Backup strategy (target)

| Asset | Method | Owner |
|-------|--------|-------|
| **Database** | Supabase automated daily backups (plan-dependent) + optional manual snapshot before migration | RIUDA / operator |
| **Auth users** | Included in Postgres backup | Supabase |
| **Application** | Git tags + deploy host rollback | RIUDA |
| **Secrets** | Host + Supabase vault; documented recovery in password manager | RIUDA |

## RPO / RTO assumptions (initial — confirm with Supabase plan)

| Metric | Target assumption | Notes |
|--------|-------------------|-------|
| **RPO** | ≤ 24 hours (daily backup tier) or ≤ 1 hour if PITR enabled | **Must confirm** Supabase subscription tier in M8-T02 |
| **RTO** | 4–8 hours for full restore + migration re-verify | Depends on operator availability |
| **App-only rollback** | Minutes | Redeploy previous Next.js artifact; DB unchanged |

## Restore procedure (outline)

1. **Declare incident** — app corrupt vs DB corrupt vs bad migration.
2. **Stop writes** — disable deploy hooks; optionally set `organization.status = inactive` for all orgs via break-glass SQL only if app cannot be stopped cleanly (last resort).
3. **Database restore** — Supabase Dashboard → restore to new project or point-in-time (per plan).
4. **Re-link** — update `NEXT_PUBLIC_*` and `SUPABASE_SECRET_KEY` on app host if project ref changes.
5. **Schema verification** — migration version matches git tag; run staging smokes (M8-T09).
6. **Recovery verification** — Primary Owner login, `fetch_session_commercial_access`, one read + one guarded mutation smoke per org sample.

Document exact Dashboard clicks in M8-T10 after first staging restore drill.

## Destructive-operation safeguards

| Operation | Rule |
|-----------|------|
| `supabase db reset` | **Local/CI only** |
| `seed.sql` on remote | **Forbidden** |
| `deleteUser` compensation (provisioning) | Application code only on failed finalize — not operator routine |
| `cancel_organization_subscription` | Operator RPC — irreversible terminal state (M7); require two-person review or runbook checkbox |
| Drop migration history | **Forbidden** without architecture review |

## Gap (T01)

No in-repo restore drill, no documented backup tier, no break-glass runbook — **M8-T10**.
