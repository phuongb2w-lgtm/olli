# M7-T02 — Trusted center + primary Owner provisioning

**Task:** M7-T02  
**Starting SHA:** `a5f2f53` — `docs(m7): add commercial readiness audit and design gate`  
**Scope:** Identity and center provisioning only (no subscription/plan tables, no onboarding UX).  
**Verification:** `npm run verify` exit 0 (M7-T02 SQL 7/7, center provisioning smoke 7/7, Playwright 196/196, i18n 1891/1891).

## Architecture

### Database (authoritative org graph)

Migration `20260926100000_m7_t02_trusted_center_owner_provisioning.sql`:

| Object | Role |
|--------|------|
| `center_provisioning_request` | Durable idempotency + cross-system state (`pending_auth` → `auth_created` → `completed`) |
| `begin_center_provisioning(...)` | **service_role** — register intent; **no organization row yet** |
| `record_center_provisioning_auth_created(...)` | **service_role** — bind Auth UID after GoTrue create |
| `finalize_center_provisioning(...)` | **service_role** — single transaction: INSERT `organization` (existing triggers), Owner `app_user`, `set_primary_owner_for_organization`, `_m7_assign_center_manager_to_primary_owner` |
| `mark_center_provisioning_*` | Compensation / reconciliation markers |

Internal `_m7_assign_center_manager_to_primary_owner` resolves the canonical template by `canonical_code = 'center_manager'` (no hardcoded role UUIDs).

RLS: `center_provisioning_request` has **no** authenticated policies; EXECUTE on provisioning RPCs is **service_role only**.

### Trusted server orchestration

| Module | Use |
|--------|-----|
| `src/lib/center-provisioning/orchestrate.ts` | Server-only Auth Admin + RPC sequence (Next.js boundary) |
| `scripts/lib/center-provisioning-orchestrate.mjs` | Same sequence for CLI/smoke (mirrors TS) |
| `scripts/provision-customer-center.mjs` | Operator CLI |
| `scripts/center-provisioning-smoke.mjs` | Integration smoke in `npm run verify` |

Auth correlation metadata: `olli_center_provisioning_request_id` (`CENTER_PROVISIONING_METADATA_KEY`).

### Auth / DB transaction boundary

PostgreSQL cannot include GoTrue user creation in the same transaction as `finalize_center_provisioning`.

**Order:**

1. `begin_center_provisioning` — no center row.
2. Auth Admin `createUser` (invite disabled; email confirmed for operator provisioning).
3. `record_center_provisioning_auth_created`.
4. `finalize_center_provisioning` — all application rows in **one DB transaction**.

**Before Auth exists:** failure leaves no `organization` (only a `pending_auth` request row, deletable).

**After Auth, before finalize succeeds:** orchestration attempts `auth.admin.deleteUser` when this request created the Auth user; marks `compensated` or `reconciliation_required`.

**After finalize succeeds:** retries with the same idempotency key return the completed graph (`outcome: completed` / `resume`).

### Idempotency model

- **Key:** global unique `idempotency_key` on `center_provisioning_request`.
- **Fingerprint:** SHA-256 of org name, normalized owner email, display name, locales, timezone, currency.
- Same key + different payload → `idempotency_conflict`.
- Same key + same payload → resume from current status (no duplicate org).
- Completed owner email cannot start a **different** key (`owner_email_already_provisioned`).

### Operator interface

```bash
node scripts/provision-customer-center.mjs \
  --idempotency-key "customer-2026-001" \
  --org-name "Example Language Center" \
  --owner-email "owner@customer.example" \
  --owner-name "Center Owner"
```

Structured JSON stdout: `organizationId`, `ownerAppUserId`, `authUserId`, `requestId` (no secrets).

Requires `SUPABASE_SECRET_KEY` and `NEXT_PUBLIC_SUPABASE_URL` (or local `supabase status -o env`).

### Post-provision invariants

- Existing org INSERT triggers unchanged (cost groups, CRM reference, `organization_entitlement`, canonical roles).
- `staff_limit = 5`, primary Owner set, Owner holds active `center_manager` `user_role`.
- No `commercial_plan` / `organization_subscription` (T03).
- No `setup_completed_at` (T05).
- Authenticated clients still **cannot** INSERT `organization`.

## Database invariants

- `app_user.auth_user_id` remains globally UNIQUE.
- Primary Owner assignment uses existing `set_primary_owner_for_organization`.
- Owner role assignment fails closed if `center_manager` template missing (`canonical_role_missing`).

## Tests

| Suite | Path | Cases |
|-------|------|-------|
| SQL | `supabase/tests/m7_t02_center_provisioning_tests.sql` | 7 — auth denial, idempotency, finalize graph, identity conflict, retry |
| Integration | `scripts/center-provisioning-smoke.mjs` | 7 — Owner/staff/anon denial, full orchestration, idempotency, entitlement/role |

Wired in `scripts/supabase-verify.ps1` and `npm run test:center-provisioning`.

## Migrations

Baseline: 54 → **55** (`20260926100000_m7_t02_trusted_center_owner_provisioning.sql`).

## Seed integration

`supabase/seed.sql` retains fixed UUID fixtures for M1–M6 regression stability. New customer centers in dev/production should use `provision-customer-center.mjs` (or orchestrate module). Documented parallel path; seed not rewritten in T02 to avoid widespread fixture churn.

## Known limitations

- Operator must set initial Auth password / invite flow outside this task (M0 deferred product auth flows).
- Orphan `center_provisioning_request` rows may remain after failed Auth steps; operators can retry with the same idempotency key.
- Subscription enforcement and Owner onboarding UX deferred to T03–T05.
