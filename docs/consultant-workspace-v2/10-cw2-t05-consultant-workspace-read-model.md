# CW2-T05 — Consultant workspace read model

**Migration:** `20260930106000_cw2_t05_consultant_workspace_read_model.sql`  
**Tests:** `supabase/tests/cw2_t05_consultant_workspace_read_model_tests.sql` (42 scenarios)  
**TypeScript:** `src/lib/consultant-workspace/portfolio-read-model.ts`

## RPC contract

- **`list_consultant_workspace_portfolio(...)`** — authoritative read (SECURITY DEFINER, side-effect free).
- **`list_consultant_workspace_grid(...)`** — alias (SECURITY INVOKER wrapper).

Parameters: `p_filters`, `p_sort_field`, `p_sort_direction`, `p_limit`, keyset cursor (`p_cursor_workspace_sequence`, `p_cursor_portfolio_entry_id`), `p_include_hidden`.

Returns JSON: `{ rows, next_cursor, has_more }`.

Requires **`consultant_workspace.read`**. Target consultant defaults to **`current_app_user_id()`**; another consultant requires **`report.executive.read`** or primary owner.

## Row source & deduplication

One grid row = one **`consultant_portfolio_entry`** for `(organization, consultant)`. Lead→Student conversion must update the same entry (preserve STT); the read model never joins lead and student as two rows for one identity.

## STT

**`workspace_sequence`** from `consultant_portfolio_entry` — not `ROW_NUMBER()`. Default sort: **workspace_sequence DESC**. Filtering/sorting does not renumber.

## Lifecycle status (derived)

Precedence:

1. No `student_id` → **Tiềm năng** (`tiem_nang`)
2. `student.status = graduated` → **Tốt nghiệp**
3. `student.status = active` + active enrollment → **Đang học**
4. Official CW2 student code → **Ghi danh**
5. Else **Tiềm năng**

No mutable `workspace_status` column.

## Student code

- **Official:** `student.student_code` when `_cw2_is_official_student_code`.
- **Provisional display:** `CCYY0000` via `_cw2_provisional_student_code_display` — never persisted; `student_code_is_provisional = true`. Omitted when DOB or consultant code missing.

## Guardian

Primary **`student_guardian.is_primary_contact`** → `guardian` name/phone. Null when none.

## Finance (M2)

Per **selected enrollment** (see below): `net_tuition_amount`, sum **posted** `payment_allocation`, sum **`charge_balance.outstanding_balance`** (charges `open` or `partially_paid`). Not derived from declaration amounts.

## Enrollment context

**Latest relevant enrollment:** active/pending enrollment with active financial terms, prefer `active` status, then latest `start_date`. Exposes `enrollment_id` and `enrollment_financial_terms_id` for Payment Drawer (T08+).

## Tuition/payment display state

Deterministic codes: `dong_phi`, `cho_xac_nhan`, `coc_phi`, `mot_phan`, `full_phi`.

- **Chờ xác nhận:** `cw2_payment` declaration `pending`.
- **Full phí:** outstanding = 0.
- **Cọc phí:** active terms `payment_plan_mode = deposit_remainder` + paid &gt; 0 + outstanding &gt; 0 (M2 plan mode — not guessed from amount alone).
- **Một phần:** paid &gt; 0, outstanding &gt; 0, not deposit mode.
- **Đóng phí:** outstanding &gt; 0, no paid, not pending.

Legacy **`legacy_m5`** declarations are ignored for CW2 tuition state.

## Declarations

Precedence among **`cw2_payment`**: pending &gt; draft &gt; returned &gt; approved &gt; rejected; then `updated_at`.

## Hidden rows & custom fields

- **`consultant_grid_hidden_row`:** omitted unless `p_include_hidden`; scoped to viewing consultant only.
- **Custom fields:** JSON array on row from owner’s `consultant_custom_field_definition` / `_value` for subject.

## Capabilities (hints only)

`can_edit_contact`, `can_open_payment_declaration`, `can_submit_declaration`, `can_add_payment` (always false for consultant), `can_open_student_details`.

## Performance

Set-based SQL with LATERAL joins; index use on `consultant_portfolio_entry (organization_id, consultant_user_id, workspace_sequence DESC)`.

## Deferred

Excel grid UI, TanStack, drawers, month header — **CW2-T06+ not started**.
