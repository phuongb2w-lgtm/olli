# CW2-T07 — Payment Declaration Drawer & Consultant Draft/Submit

## Scope

Consultant-facing **payment declaration** from the T06 portfolio grid. Ends at **submit → pending (`Chờ xác nhận`)**. No Accounting review UI (T08+). No direct M2 `record_payment`.

## Semantics

| Concept | Meaning |
|---------|---------|
| Consultant declaration | Consultant reports that guardian paid an amount and requests Accounting confirmation |
| Payment | Authoritative M2 posted payment — only via `confirm_consultant_payment_declaration` (T04) |
| Promotion / discount field | Declaration **context only** (`promotion_context`); does not mutate `enrollment_financial_terms` or charges |

## Backend (reuse T04)

- `save_consultant_payment_declaration_draft(..., p_promotion_context)` — draft/returned edit; finance validation via `_cw2_validate_declaration_finance_state`
- `submit_consultant_payment_declaration` — pending; server-side outstanding check (not browser snapshot)
- `refresh_cw2_payment_declaration_finance` — authoritative M2 snapshot for drawer
- `get_cw2_payment_declaration_drawer` — declaration + finance for reopen
- Portfolio capabilities: `_cw2_portfolio_declaration_capabilities` — `can_open_payment_declaration`, `can_create_payment_declaration`, `can_edit_payment_declaration`, `can_submit_declaration`; **`can_add_payment` stays false** for consultants

Migrations: `20260930107000_cw2_t07_payment_declaration_drawer.sql`, `20260930107100_cw2_t07_portfolio_declaration_capabilities.sql`.

## UI

- Grid action: **Khai báo khoản nộp** / **Declare payment** (`declare-payment-action`)
- `PaymentDeclarationDrawer`: read-only student/course/total/confirmed/outstanding; editable amount, promotion context, note; **Lưu nháp** / **Gửi xác nhận**
- Server actions: `src/app/actions/consultant-payment-declaration.ts`
- VND input: `src/lib/consultant-workspace/vnd-input.ts`

## Eligibility (UX + server)

- Outstanding > 0 and no conflicting **pending** on same `enrollment_financial_terms_id` → create/continue draft
- Existing **draft/returned** → reopen/edit
- **Pending** → read-only inspect; grid `cho_xac_nhan`
- **Full phí** → no new declaration
- Missing guardian → draft may work; submit blocked with clear message

## Security

Consultant cannot confirm, record payment, allocate official code, or convert lead on submit. SQL: `supabase/tests/cw2_t07_payment_declaration_drawer_tests.sql` (32). E2E: `tests/e2e/consultant-payment-declaration.spec.ts`.

## T08 handoff

Monthly sales header consumes **Accounting-confirmed attributed cash** only; pending/draft declarations do not count.
