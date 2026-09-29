# CW2-T09 — Student details & controlled consultant editing

## Route

`/consultant/portfolio/[portfolioEntryId]` — browser loads detail via `get_consultant_portfolio_entry_detail` after a server permission gate; RPC resolves portfolio entry → consultant → lead/student (no client Student ID trust).

Optional query: `?return=/consultant?month=YYYY-MM`, `?edit=1`.

## Field classes

| Class | Examples | Consultant UI |
|-------|----------|---------------|
| A — Immutable | Official Student Code, lifecycle status, finance, payments, STT | Read-only |
| B — Canonical editable | Names, DOB, primary guardian contact | `save_consultant_portfolio_profile` with `consultant_workspace.update` |
| C — Personal | `consultant_custom_field_*` | `save_consultant_portfolio_custom_fields` with `consultant_custom_field.manage` |

## Student Code / DOB

Official `CCYYNNNN` remains immutable (DB trigger). DOB may be corrected via profile save; code is not regenerated.

## Finance

Read-only summary from T05 helpers. Declaration via existing T07 drawer only.

## Hidden rows

Direct URL still loads detail; `is_hidden` shown; grid hide preference unchanged.

## RPCs

- `get_consultant_portfolio_entry_detail(uuid)`
- `save_consultant_portfolio_profile(...)`
- `save_consultant_portfolio_custom_fields(uuid, jsonb array)`

All scope-checked via `_cw2_assert_portfolio_entry_access`.

## Debt

- Secondary guardian display not expanded (M1 model supports many; UI shows primary only).
- Optimistic concurrency via optional `p_expected_subject_updated_at` on profile save only.
