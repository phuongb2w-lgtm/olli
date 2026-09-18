# M5-T01.1 — Semantic Boundaries

Locked distinctions for M5 reporting. Do not collapse these concepts in read models or KPIs.

## Teaching service states

| Concept | Meaning | Canonical evidence |
| -------- | -------- | ------------------- |
| **Projected** | Schedule occurrence not yet materialized as `teaching_session` | Operational calendar `entry_type = projected` |
| **Materialized** | Concrete `teaching_session` row exists | Row in `teaching_session`; includes `scheduled`, `in_progress`, `completed` |
| **Cancelled** | Session cancelled under M4 semantics | `teaching_session.status = cancelled`; suppresses projection |
| **Delivered** | Actual teaching service completed | `teaching_session.status = completed` (M1 session execution) |

**Critical rule:** A materialized session (`scheduled` or `in_progress`) is **not** delivered service.

M2 `class_delivered_session_count`, M4 workload `completed_session_count`, and M5 `count_delivered_teaching_sessions` all use `status = completed`.

Helpers: `teaching_session_is_delivered()`, `count_materialized_teaching_sessions()`, `count_delivered_teaching_sessions()`.

Application contract: `src/lib/reporting/teaching-service-states.ts`.

## Consultant / finance states

| Concept | Meaning | Canonical evidence |
| -------- | -------- | ------------------- |
| **Declared** | Consultant submitted revenue claim | `consultant_revenue_declaration` with `pending` or resubmitted after `returned` |
| **Approved declaration** | Accountant validated declaration | `status = approved`; **not** ledger revenue |
| **Cash collected** | Money recorded in books | Posted `payment` (`status = posted`) |
| **Recognized revenue** | Revenue recognition posted | `revenue_recognition_event` with `status = posted` |
| **Receivable** | Outstanding obligation | `charge_balance` view |

**Critical rules:**

1. `review_consultant_revenue_declaration(approve)` sets `status = approved` only — it does **not** create payment, charge, or recognition events.
2. `approved_payment_id` is optional linkage when bookkeeping records payment separately.
3. Pending and returned declarations are excluded from canonical financial KPIs.
4. Approved declarations are excluded from cash collected and recognized revenue unless canonical M2 evidence exists.

Helpers: `sum_pending_consultant_declarations()`, `sum_approved_consultant_declarations()`, `sum_canonical_cash_collected()`, `count_canonical_financial_revenue()`, `declaration_has_canonical_payment()`.

Application contract: `src/lib/reporting/consultant-revenue-semantics.ts`.
