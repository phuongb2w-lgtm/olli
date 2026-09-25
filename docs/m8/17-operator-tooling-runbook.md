# M8 — Operator Tooling & Runbooks (M8-T08)

**Purpose:** Trusted RIUDA workflows for center onboarding and commercial subscription lifecycle **without ad-hoc Supabase Dashboard SQL**.

**Scope:** CLI orchestration only — reuses M6/M7 authoritative RPCs and existing provisioning orchestration. No billing gateway, no Owner/staff self-service mutations, no new product UI.

**Related:** [03 — Environment & secrets](./03-environment-secrets-contract.md), [11 — Supabase production procedure](./11-supabase-production-operator-procedure.md), [13 — Auth & SMTP](./13-auth-smtp-operator-procedure.md), [08 — Release runbook](./08-release-rollback-runbook.md)

---

## 1. Prerequisites

| Requirement | Notes |
|-------------|--------|
| Release SHA checked out | Same commit that passed `npm run verify` |
| `SUPABASE_SECRET_KEY` | **Server/operator only** — service role; never in client or git |
| `NEXT_PUBLIC_SUPABASE_URL` | Target Supabase project (local or Cloud) |
| SMTP + Auth (production) | Owner invite email — [13](./13-auth-smtp-operator-procedure.md) |
| Migrations applied | Expected count **59** (no T08 schema change) |

**Local development:** Scripts may auto-load `npx supabase status -o env` when keys are unset (CI/local only). **Production operators must export secrets explicitly.**

---

## 2. Safety model

### Production Cloud mutations

Before any **mutating** command against `https://<ref>.supabase.co`:

```bash
export OLLI_SUPABASE_PROJECT_REF="<ref>"
export OLLI_CONFIRM_PRODUCTION_OPERATOR_ACTION=yes
```

### Subscription lifecycle confirmation

Every subscription mutation requires an explicit action pin:

```bash
export OLLI_CONFIRM_SUBSCRIPTION_ACTION=activate   # or suspend | reactivate | cancel
export OLLI_CONFIRM_ORGANIZATION_ID="<organization-uuid>"   # strongly recommended for suspend/cancel
```

**Read-only** `status` does **not** require production confirmation (still requires service role).

### Never log or commit

- Service role key, access tokens, SMTP passwords, invite/reset links with secrets

---

## 3. CLI entry points

Unified CLI:

```bash
node scripts/olli-operator.mjs <command> [flags]
```

Legacy alias (provision only):

```bash
node scripts/provision-customer-center.mjs --org-name "..." --owner-email "..." --owner-name "..."
```

npm shortcuts:

```bash
npm run operator:provision -- --org-name "..." --owner-email "..." --owner-name "..."
npm run operator:status -- --organization-id <uuid>
npm run operator:subscription -- activate --organization-id <uuid>
```

---

## 4. Provision a center

Creates organization graph, Primary Owner, commercial subscription in **`provisioning`**, CRM/reference seeding via canonical RPC path.

```bash
node scripts/olli-operator.mjs provision \
  --org-name "Example Language Center" \
  --owner-email "owner@customer.example" \
  --owner-name "Primary Owner Name" \
  --idempotency-key "customer-example-2026-001" \
  --locale vi
```

**Expected success JSON:** `organizationId`, `ownerAppUserId`, `authUserId`, `requestId`, `resumed` (on retry).

**Retry:** Re-run with the **same** `--idempotency-key` after partial failure (Auth created but finalize failed, etc.). Do not invent parallel provisioning state.

**Post-provision verification:**

1. `status` — subscription `provisioning`, Primary Owner present, `staff_limit` synced from base plan.
2. Owner receives invite (production SMTP) or uses local Auth user when `OLLI_CENTER_PROVISION_USE_INVITE=false` (local only).
3. After Owner onboarding (product UI), operator **activates** subscription (below).

---

## 5. Inspect commercial status (read-only)

By UUID (preferred):

```bash
node scripts/olli-operator.mjs status --organization-id "<uuid>"
```

By exact organization name (rejects ambiguous duplicates):

```bash
node scripts/olli-operator.mjs status --organization-name "Example Language Center"
```

Output includes: organization status, subscription lifecycle, plan code, staff limit / seats used / remaining, Primary Owner summary, recent provisioning request rows.

---

## 6. Activate subscription

Moves **`provisioning` → `active`** (M7 operator RPC `activate_organization_subscription`).

```bash
export OLLI_CONFIRM_SUBSCRIPTION_ACTION=activate
export OLLI_CONFIRM_ORGANIZATION_ID="<uuid>"
node scripts/olli-operator.mjs subscription activate --organization-id "<uuid>"
```

**Invalid transitions** (e.g. activate when already `active`) return explicit RPC errors — do not mask.

---

## 7. Suspend subscription

Moves **`active` → `suspended`**. Restricts commercial access per M7-T04.

```bash
export OLLI_CONFIRM_PRODUCTION_OPERATOR_ACTION=yes   # Cloud only
export OLLI_CONFIRM_SUBSCRIPTION_ACTION=suspend
export OLLI_CONFIRM_ORGANIZATION_ID="<uuid>"
node scripts/olli-operator.mjs subscription suspend --organization-id "<uuid>"
```

---

## 8. Reactivate subscription

Moves **`suspended` → `active`**.

```bash
export OLLI_CONFIRM_SUBSCRIPTION_ACTION=reactivate
export OLLI_CONFIRM_ORGANIZATION_ID="<uuid>"
node scripts/olli-operator.mjs subscription reactivate --organization-id "<uuid>"
```

Cannot reactivate from **`cancelled`** (terminal).

---

## 9. Cancel subscription

Moves to **`cancelled`** (terminal in M7). **Irreversible** via product/operator lifecycle.

```bash
export OLLI_CONFIRM_SUBSCRIPTION_ACTION=cancel
export OLLI_CONFIRM_ORGANIZATION_ID="<uuid>"
node scripts/olli-operator.mjs subscription cancel --organization-id "<uuid>"
```

CLI prints an explicit terminal-state warning before executing.

---

## 10. Lifecycle rules (summary)

| From | To | Operator command |
|------|-----|------------------|
| `provisioning` | `active` | `subscription activate` |
| `active` | `suspended` | `subscription suspend` |
| `active` | `cancelled` | `subscription cancel` |
| `suspended` | `active` | `subscription reactivate` |
| `suspended` | `cancelled` | `subscription cancel` |
| `provisioning` | `cancelled` | `subscription cancel` |
| `cancelled` | *any* | **Denied** |

Plan changes and entitlement resync remain available via existing service_role RPCs (`change_organization_commercial_plan`, `resync_organization_entitlement`) — not exposed in T08 CLI; use only when documented in M7 operator procedures or future tooling.

---

## 11. Troubleshooting

| Symptom | Likely cause | Action |
|---------|----------------|--------|
| `Refusing operator mutation against Supabase Cloud` | Missing `OLLI_CONFIRM_PRODUCTION_OPERATOR_ACTION=yes` | Set confirm env after verifying project ref |
| `ambiguous_organization_name` | Duplicate org names | Use `--organization-id` |
| `OLLI_CONFIRM_SUBSCRIPTION_ACTION` error | Action pin missing/wrong | Set env to exact action name |
| `subscription transition` / assert errors | Invalid M7 transition | Run `status`; align action to current state |
| `identity_conflict` on provision | Email already in Auth | Resolve Auth user conflict; do not duplicate org |
| Owner cannot sign in | SMTP/Site URL | [13 — Auth & SMTP](./13-auth-smtp-operator-procedure.md) |

**Emergency / debug:** Dashboard SQL may be used for **read-only** investigation. **Do not** bypass RPCs for routine subscription mutations — use CLI to preserve entitlement sync and audit consistency.

---

## 12. Verification (repository)

```bash
npm run test:operator
```

Full release gate still requires:

```bash
npm run verify
```

---

## 13. Repository acceptance vs live operations

| Layer | T08 status |
|-------|------------|
| Repository tooling + runbook | **Addressed** when `test:operator` and `verify` pass |
| Live RIUDA production drill | **Pending** until exercised on Cloud Supabase + production app |

**B-05:** Addressed at repository scope — live verification pending.
