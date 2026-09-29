# CW2-T08 — Monthly consultant sales header

## Sales definition

Consultant **Doanh số của tháng** = sum of **posted** M2 `payment` cash linked through immutable `payment_consultant_attribution` for the signed-in consultant.

Not included: declaration amounts (draft/pending/returned/rejected/approved-without-payment), revenue recognition, enrollment tuition snapshots, charge balances, CRM conversion.

## Source of truth

- `payment` (`status = posted`, `paid_at` for period)
- `payment_consultant_attribution` (exactly one row per payment per org; `attributed_amount`)
- Accounting confirmation composition (CW2-T04) creates both

## Period semantics

- Local reporting month via `resolve_reporting_period(month_start, month_end)` (same as M5).
- Assignment uses `payment.paid_at` in UTC bounds, not declaration or attribution timestamps.

## RPC

`get_consultant_monthly_sales(p_period_month date)` → JSON:

- `sales_amount`, `payment_count`, `currency_code`
- `period`, `previous_period`, `comparison` (`kind`: increase | decrease | neutral | **new** when previous = 0 and current > 0; no infinite %)
- `navigation`: `can_go_next` false when selected month ≥ current org local month (future months disabled)

## Security

Server resolves org + `current_app_user_id()`; no client consultant impersonation parameter.

## UI

- `/consultant?month=YYYY-MM` (invalid query stripped / fallback to current month)
- Header above T06 grid; month navigation does not change portfolio scope or filters
- Loading / zero / error states distinct
- VI + EN strings under `consultantWorkspace.monthlySales`

## Verification

- `supabase/tests/cw2_t08_consultant_monthly_sales_tests.sql` (30)
- `tests/e2e/consultant-monthly-sales.spec.ts`

## Debt

- No automatic sales refresh after Accounting confirmation until user navigates or reloads (same class as portfolio stale row until refresh); acceptable for T08 operational header.
