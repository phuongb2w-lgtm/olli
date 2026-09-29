# CW2-T06 — Consultant portfolio workspace UI

**Route:** `/consultant` (alias redirect: `/crm/workspace` → `/consultant`)  
**Primary component:** `src/components/consultant-workspace/consultant-portfolio-workspace.tsx`  
**Data:** T05 `list_consultant_workspace_portfolio` via server action (no client-side domain recompute)

## Dependencies

- `@tanstack/react-table` — column visibility, sizing, table state
- `@tanstack/react-virtual` — row virtualization for loaded pages

## Architecture

| Layer | Responsibility |
|--------|----------------|
| `consultant/page.tsx` | Permission gate, load grid preferences + optional course list |
| `app/actions/consultant-workspace.ts` | Hide/restore row, persist `consultant_workspace_preference` |
| `fetch-portfolio.ts` + browser client | T05 RPC read (authoritative rows; no client-side domain logic) |
| `consultant-portfolio-workspace.tsx` | Filters, sort, keyset load-more, keyboard nav, grid UI |

## Deferred (T07+)

- Payment declaration drawer
- Inline canonical field editing
- Custom-field definition editor
- Month sales header

## Payment semantics

`can_add_payment` from T05 remains **false** for consultants (no M2 `record_payment` UI). Declaration affordance is indicated via capability hints only; drawer not wired in T06.

## Preferences

Column width/visibility persisted in `consultant_workspace_preference.grid_preferences` (T02 table).

## Tests

`tests/e2e/consultant-workspace.spec.ts` — route, denial, grid behavior (mocked RPC), CRM regression.
