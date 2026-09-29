# CW2-T04.1 — Accountant confirmation & lead conversion scope

**Migrations:** `20260930105200_cw2_t04_1_accountant_confirm_convert_scope.sql`, `20260930105300_cw2_t04_1_confirm_scoped_lead_readiness.sql`  
**Tests:** `supabase/tests/cw2_t04_1_accountant_lead_first_tests.sql` (18 scenarios)  
**Regression:** T04 suite uses canonical **`accountant`** reviewer (not `center_manager`).

## Who may confirm

**`confirm_consultant_payment_declaration`** requires:

- `payment.record`
- `consultant_revenue.review`

The canonical **Accountant** role template includes both. **Center Manager is not required** for production Accounting confirmation.

Primary owner status is **not** required for confirmation; T04.1 fixtures use a dedicated accountant user without `lead.convert`.

## Lead-first conversion authority (Option A — narrow composition)

When a submitted pending `cw2_payment` declaration has `lead_id` and no `student_id`, confirmation sets session `cw2.declaration_confirm` and calls authoritative **`convert_lead()`**.

`convert_lead()` normally requires **`lead.convert`**. The CW2 gate (migrations 051 + 052) allows a **narrow bypass** only when **all** hold:

1. Session `cw2.declaration_confirm` = declaration UUID  
2. Caller has `payment.record` and `consultant_revenue.review`  
3. Matching declaration: same org, same `lead_id`, `workflow_kind = cw2_payment`, `status = pending`, **`submitted_at IS NOT NULL`**

The Accountant does **not** receive general-purpose **`lead.convert`**. Arbitrary `convert_lead()` calls outside an active valid CW2 confirmation still fail with `permission_denied`.

Draft, rejected, returned, and `legacy_m5` declarations do not satisfy the gate.

Identity readiness for conversion on this path uses **`_cw2_confirm_scoped_lead_identity_readiness()`** (SECURITY DEFINER, same declaration proof) so Accountants are not required to hold general **`lead.read`** for CRM browsing.

## Safety

- Global M3 conversion semantics are unchanged; only the permission prelude is extended.  
- Confirm-scoped conversion cannot target a different lead than the declaration’s `lead_id`.  
- No role-name checks; boundary is expressed via permissions + trusted session + declaration row proof.  
- **No new general CRM permission** was added to Accountant.

## Production behavior summary

| Action | Accountant |
|--------|------------|
| Confirm student-first CW2 declaration | Yes |
| Confirm lead-first CW2 declaration (incl. M3 convert) | Yes |
| Call `convert_lead()` outside CW2 confirm | No |
| `lead.convert` permission | No |

CW2-T05 (read models / UI) **not started**.
