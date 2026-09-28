# CW2-T04 — Accounting confirmation composition

**Migrations:** `20260930105000_cw2_t04_accounting_confirmation_composition.sql`, `20260930105100_cw2_t04_convert_lead_confirm_gate.sql`  
**Tests:** `supabase/tests/cw2_t04_accounting_confirmation_tests.sql` (42 scenarios)

## Lifecycle

| Status | Meaning |
|--------|---------|
| `draft` | Consultant-owned CW2 declaration (`workflow_kind = cw2_payment`) |
| `pending` | Submitted for Accounting (`submitted_at` set) |
| `approved` | Accounting confirmed — **authoritative M2 `payment` linked** via `approved_payment_id` |
| `rejected` / `returned` | No payment, no code, no attribution |

Legacy M5 `declare_consultant_revenue()` rows remain `workflow_kind = legacy_m5` and **cannot** use `confirm_consultant_payment_declaration`.

## Consultant RPCs

- **`save_consultant_payment_declaration_draft(...)`** — create/update own draft (`consultant_revenue.declare`).
- **`submit_consultant_payment_declaration(id)`** — `draft|returned → pending`; requires guardian, financial terms, student or lead.

## Accounting RPC

**`confirm_consultant_payment_declaration(declaration_id, paid_at?, method?, idempotency_key?)`**

Requires **`payment.record`** and **`consultant_revenue.review`**. Single transaction (SECURITY DEFINER for attribution insert):

1. Validate CW2 pending declaration + finance state (`_cw2_validate_declaration_finance_state`).
2. Optional **`convert_lead`** when `student_id` null (session `cw2.declaration_confirm`; see migration 051 permission gate).
3. **`record_payment`** with M2 allocations (idempotent key default `cw2-decl-confirm:{id}`).
4. **`payment_consultant_attribution`** (amount = payment cash; `attribution_recorded_at` = **`payment.paid_at`**).
5. **`allocate_official_student_code`** (T03) when no official code; legacy occupied codes skip allocation without failing payment.
6. Declaration → `approved` + `approved_payment_id`.

Idempotent replay when already approved with payment.

## Financial semantics

- Declaration ≠ payment ≠ consultant sales ≠ revenue recognition.
- Outstanding balance from M2 charges/`charge_balance`; partial payments supported.
- Monthly sales read model: **`sum_consultant_attributed_cash(consultant, start, end)`** filters on **`payment.paid_at`** in org timezone (not declaration date).

## Deferred

Consultant grid, payment drawer UI, monthly sales dashboard — **CW2-T05+ not started**.
