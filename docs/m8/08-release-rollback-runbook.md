# M8 — Release & Rollback Runbook

**Status:** Draft for M8 implementation. Steps assume staging rehearsal before production.

## Pre-release gates (mandatory)

All must pass on release commit:

| Gate | Command / check |
|------|-----------------|
| Branch | `main` (or release tag) |
| Migrations | Count matches released tag (**58** at M8-T01 baseline unless release adds migrations); `npm run db:migrations:count` |
| Pre-deploy DB gate | `npm run db:production:predeploy-gate` (local); optional `OLLI_PREDEPLOY_INCLUDE_REMOTE=1` |
| Pre-deploy app gate | `npm run app:production:predeploy-gate`; optional `OLLI_APP_PREDEPLOY_INCLUDE_HOST_ENV=1` |
| Full local verify | `npm run verify` exit 0 |
| Secrets audit | `npm run test:env` (static audit + contract smokes + optional bundle scan) |
| Browser security headers / CSP | `npm run test:security` (M8-T06 contract smokes) |
| Types | `npm run test:types:stale` (local against matching schema) |
| No seed on target DB | Confirm production/staging has never applied `seed.sql` |
| Auth dashboard | Site URL + redirects + SMTP per [05 — Auth contract](./05-auth-domain-contract.md) and [13 — Auth/SMTP procedure](./13-auth-smtp-operator-procedure.md) |
| Env | [03 — Environment contract](./03-environment-secrets-contract.md) populated on host |

**Do not weaken** M0–M7 suites; production adds **additional** smokes (M8-T09), not replacements.

## Production migration sequence

1. Announce maintenance window if migration locks heavy tables (review migration SQL).
2. **Backup** — manual Supabase snapshot (even if daily backups exist).
3. Follow [11 — Supabase production operator procedure](./11-supabase-production-operator-procedure.md): link verify → migration status → dry-run → **`npm run db:production:migration-deploy`** from release tag.
4. **`npm run db:production:smoke`** on linked project (lint included in deploy script).
5. If types changed: regenerate `--linked`, commit already done in tag — verify hash.
6. Proceed to app deploy only if DB step succeeds.

## Application deploy sequence

1. **`npm run app:production:predeploy-gate`** on release SHA (includes `test:env`, lint, typecheck, build).
2. Set/build env vars on Vercel **Production** scope ([03 — Environment contract](./03-environment-secrets-contract.md)).
3. Deploy: Vercel production build from `main` (see [12 — App operator procedure](./12-application-deployment-operator-procedure.md)).
4. **`GET /api/health`** — confirm `gitSha` + `status: ok`.
5. **`OLLI_APP_BASE_URL=https://olli.riuda.click npm run app:production:smoke`**
6. Monitor error rate 30 minutes.

Legacy manual build (non-Vercel fallback):

1. Set env vars on host (no secret in build args logged publicly).
2. `npm ci` → `npm run build` → deploy artifact / `next start`.
3. Run post-deploy smokes (below).
4. Monitor error rate 30 minutes.

## Post-deploy smoke tests (production-specific)

Minimum manual or automated checklist:

| # | Check |
|---|--------|
| P-1 | `https://olli.riuda.click/login` loads (EN/VI) |
| P-2 | Known test center Owner sign-in → landing per M7 (`/onboarding` or `/`) |
| P-3 | `fetch_session_commercial_access` path — restricted center shows `/subscription-status` or `/commercial-access` |
| P-4 | Staff sign-in denied when subscription not active (fixture center) |
| P-5 | One read RPC (e.g. student list) and one denied cross-org attempt (API smoke pattern) |
| P-6 | Owner invite + staff invite + forgot-password emails received (SMTP) |

Reuse patterns from `scripts/api-security-smoke.mjs` against production URL with **non-seed** identities.

## Acceptance checklist (RIUDA sign-off)

- [ ] DNS + TLS valid
- [ ] Migrations at expected version
- [ ] No dev `@olli.local` users in Auth
- [ ] Operator can provision center + activate subscription
- [ ] Owner completes onboarding once
- [ ] `npm run verify` green on release SHA (pre-deploy)
- [ ] Rollback owner identified

## Rollback procedure

### Application-only regression (schema unchanged)

1. Redeploy previous known-good Next.js deployment artifact.
2. Re-run P-1, P-2 smokes.

### Bad migration applied

1. **Do not** deploy new app code if DB migration failed partially.
2. Restore DB from snapshot (see [06 — Backup](./06-backup-recovery-contract.md)).
3. Hold app at previous version until root cause migration fixed forward.

### Bad data / operator error

- Subscription: use M7 operator RPCs (`suspend`, `reactivate`) — **not** ad-hoc DELETE.
- Provisioning: idempotency keys documented in M7-T02; do not duplicate org manually.

## Regression protection (continuous)

| Suite | When |
|-------|------|
| `npm run verify` | Every release candidate locally / CI when parity added |
| `npm run db:verify` | Schema-changing PRs |
| Playwright 216 | Pre-release |
| i18n 1953 keys | Pre-release |
| M7 commercial E2E | Pre-release |
