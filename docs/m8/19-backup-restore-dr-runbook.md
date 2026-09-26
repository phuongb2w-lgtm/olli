# M8-T10 — Backup, restore & migration failure drill

**Task:** M8-T10  
**Baseline SHA:** `16ed7bdca78591a9cb42b791ca989aa2a51b5379`  
**Scope:** Repository acceptance — recovery inventory, RPO/RTO targets, secure backup handling, local synthetic restore rehearsal, operator runbooks. **Hosted production restore drill remains separately pending.**

## Purpose

Prove Olli can **recover customer data**, not merely recreate an empty environment from migrations. A passing `supabase db reset` proves **rebuild** reproducibility; it does **not** prove production **restore**.

## Rebuild vs restore

| Mode | Inputs | Recovers customer data? |
|------|--------|-------------------------|
| **Rebuild** | Git migrations, reference migration data, env config, operator provision | **No** — empty org shell only |
| **Restore** | Logical/physical backup or Supabase platform restore | **Yes** — must preserve referential integrity and history |

## Recovery inventory

| Category | Examples | Recovery source | Notes |
|----------|----------|-----------------|-------|
| **Database schema** | tables, RLS, RPCs, triggers, grants | Git migrations | Authoritative in repo; verify with `npm run db:verify` |
| **Reference data** | permissions, cost domains, lead source templates | migrations (`reference_data`) | Not in `seed.sql` on production |
| **Organization / customer data** | centers, students, guardians, classes | **Backup / PITR** | Must restore from captured state |
| **Membership / Primary Owner** | `app_user`, `user_role`, `organization_entitlement.primary_app_user_id` | Backup | Owner invariant must survive restore |
| **Commercial state** | `organization_subscription`, entitlements, staff limits | Backup | Historical truth; do not replay lifecycle RPCs on restore |
| **Finance truth** | charges, payments, allocations, revenue recognition | Backup | Event/history semantics preserved |
| **CRM / admissions history** | leads, activities, conversion events | Backup | Not disposable reporting cache |
| **Academic data** | attendance, assessments, observations, review state | Backup | Coherence required post-restore |
| **Teaching operations** | sessions, schedules, change history | Backup | Canonical operational timeline |
| **Executive / reporting** | SQL views & RPC aggregates | **Derived from source tables** | Recompute after restore by using app; source tables are authoritative |
| **Auth identities** | `auth.users`, refresh tokens, MFA | Supabase Auth + Postgres backup tier | DB-only restore may diverge from Auth dashboard state — see §Auth |
| **Rate-limit buckets** | `app_rate_limit_bucket` | **Ephemeral** | Safe to omit or purge; rebuild on traffic ([16 — Rate limit](./16-rate-limit-abuse-contract.md)) |
| **Application host** | Next.js artifact | Vercel rollback / redeploy | Stateless |
| **Secrets** | service role, SMTP, env | Host + password manager | Not in dumps |

## RPO / RTO (operational targets — not proven SLA)

| Metric | Initial target | Evidence |
|--------|----------------|----------|
| **RPO** | ≤ 24 h if daily backups only; ≤ 1 h if PITR enabled on production plan | **Pending** — confirm Supabase plan in Cloud project |
| **RTO** | 4–8 h for full DB restore + verification smokes | **Pending** — staging/production timed drill |
| **App-only rollback** | Minutes | Redeploy previous Vercel build; DB unchanged |

Until a hosted restore completes, treat these as **operational targets**, not contractual SLA.

## Backup strategy (layers)

1. **Supabase-managed backups** — daily (plan-dependent); optional PITR — operator verifies in Dashboard (**live evidence pending**).
2. **Pre-risk manual snapshot** — before migration deploy ([08 — Release runbook](./08-release-rollback-runbook.md)).
3. **Logical export** — `pg_dump` of `public` + `supabase_migrations` for break-glass copies (encrypted storage only).
4. **Schema/migration repository** — rebuild path only; not a substitute for customer backup.

## Secure backup handling

- Never commit real dumps (`*.pgdump`, production `*.sql.gz`) to git.
- Never log dump contents or credentials in CI.
- Store exports encrypted; restrict to RIUDA break-glass roles; define retention/deletion with customer-data policy.
- Repository tests use **synthetic** fixture org `M8-T10 DR Fixture Org` only.

## Repository tooling

| Command | Purpose |
|---------|---------|
| `npm run backup:check` | Static readiness + optional local stack probe |
| `npm run restore:drill` | Local synthetic export → isolated DB → restore → semantic verify |
| `npm run test:recovery` | T10 gate (static guards + drill when Supabase local is running) |

**Production guards:** recovery scripts refuse Supabase Cloud URLs by default. Destructive Cloud restore requires `OLLI_CONFIRM_PRODUCTION_RESTORE=yes` and `OLLI_SUPABASE_PROJECT_REF` pin — **human incident only**, not CI.

## Local restore rehearsal flow

```text
seeded local postgres (verify fixture state)
        ↓
apply supabase/tests/m8_t10_recovery_fixture.sql (idempotent)
        ↓
pg_dump public + supabase_migrations (schema + data)
        ↓
CREATE DATABASE olli_m8_t10_recovery (isolated)
        ↓
restore schema + data
        ↓
supabase/tests/m8_t10_recovery_verify.sql
        ↓
DROP DATABASE olli_m8_t10_recovery
```

## Production recovery procedure (operator)

1. **Detect & classify** — app bug vs operator error vs migration vs broad DB loss (decision tree below).
2. **Contain** — stop deploys; disable writes if needed (maintenance / subscription suspend — prefer domain tools over ad-hoc DELETE).
3. **Choose recovery source** — PITR > latest backup > logical export; smallest scope that restores integrity.
4. **Restore** — Supabase Dashboard / support workflow per plan (**document exact clicks after first staging drill**).
5. **Re-link** — if project ref changes, update Vercel env ([03 — Environment contract](./03-environment-secrets-contract.md)).
6. **Verify** — migration count matches release tag; `npm run db:production:smoke`; commercial + RLS spot checks; P-1–P-6 smokes ([18 — Smoke](./18-production-smoke-ci-contract.md)).
7. **Reopen** — monitor 30 minutes; record incident timeline and evidence.

## Auth considerations

- Application rows reference `auth_user_id` on `app_user`. Postgres backup includes `auth` schema when using platform restore; logical dumps must include Auth policy per Supabase guidance.
- **DB restored, Auth ahead:** users created after backup point may exist in Auth without app rows — disable or reconcile manually via Admin API.
- **Auth ahead, DB restored:** users missing from Auth cannot sign in — re-invite / password recovery per [13 — Auth/SMTP](./13-auth-smtp-operator-procedure.md).
- Do not manually edit `auth.*` tables unless following Supabase-supported procedures.

## Commercial state after restore

Restore reproduces **historical** subscription rows. Do not call `activate` / `cancel` RPCs to “fix” restored data unless operators intentionally change post-incident state. **`cancelled` remains terminal** (M7).

## Rate-limit buckets

`app_rate_limit_bucket` holds hashed keys and counters — defensive ephemeral state. Excluding or purging after restore is acceptable; limits repopulate on next requests.

## Disaster scenarios

| Scenario | Detection | Smallest recovery | Full restore threshold |
|----------|-----------|-------------------|------------------------|
| **A — accidental mutation/deletion** | user report, audit | domain RPC / operator CLI ([17](./17-operator-tooling-runbook.md)) | row-level restore or PITR if widespread |
| **B — bad migration** | deploy smoke failure, errors | forward-fix migration if safe | snapshot restore if data damaged |
| **C — operator mistake** | operator audit | subscription/suspend/reactivate CLI | restore if irreversible SQL bypass |
| **D — app bug corrupts bounded records** | monitoring, support | targeted SQL fix + verification | backup if corruption spread |
| **E — broader DB loss** | health checks, Supabase incident | platform restore | mandatory |

## Bad migration response

1. Stop application deploys immediately.
2. Capture manual snapshot if still possible.
3. Assess: failed mid-migration vs partial data damage.
4. **Git revert ≠ DB rollback** — redeploying old app code does not undo schema.
5. Prefer **forward-fix** migration after review; restore from snapshot if production data corrupted.
6. Re-run `npm run db:production:smoke` and release gates on fixed forward path.

## Operator mistake recovery (prefer domain tools)

| Mistake | Tool |
|---------|------|
| Wrong center suspended | `olli-operator.mjs subscription reactivate` |
| Wrong subscription action | documented RPC via operator CLI |
| Partial provisioning | idempotency keys / finalize flow (M7-T02) |

Use database restore only when domain-level correction cannot restore integrity.

## Verification checklist (post-restore)

- [ ] Migration version matches release tag (**59** at T10 closeout)
- [ ] RLS enabled on tenant tables
- [ ] Primary Owner mapping per org sample
- [ ] Subscription + entitlement rows match expected historical state
- [ ] Representative Finance, CRM, Academic, Teaching rows readable
- [ ] Cross-org isolation spot check
- [ ] Owner/staff auth sign-in (live)
- [ ] `npm run verify` on release SHA (pre-reopen)

## Live / platform evidence still required

- Supabase backup retention and PITR availability on production plan
- Real backup creation audit
- Staging or production restore drill with timed RTO
- Auth + SMTP behavior after restore
- Vercel production env re-link if project ref changes

**Repository T10 verdict:** DR procedure and tooling ready; **hosted production recovery verification pending**.
