# Consultant Workspace V2 — Proposed Implementation Sequence

**Prerequisite:** T01 audit/design **CLOSED / PASS** (canonical locks in [design contract](./02-t01-consultant-workspace-v2-design-contract.md))  
**Rule:** Small, independently verifiable tasks; preserve M1–M8 semantics; no parallel sources of truth; **consultant sales = attributed confirmed payment**, not declaration approvals; **code exhaustion fail-closed**.

| Task | Title | Primary deliverables | Acceptance (summary) |
|------|--------|----------------------|----------------------|
| **CW2-T02** | Domain & schema foundations | Consultant code profile; portfolio sequence; declaration extensions (`draft`, student/enrollment/course FKs); **payment→consultant attribution** bridge; grid preference/hidden-row tables; RLS + SQL tests | Migrations only; db tests green; no UI |
| **CW2-T03** | Student code allocator | Org-scoped **`student_sequence_counter`** (or equivalent); compose `CC+YY+NNNN`; row lock per org; immutability trigger; **fail closed at center sequence 9999**; idempotent on Accounting payment confirm | Parallel confirm → distinct `NNNN`; exhaustion error; no duplicate official codes |
| **CW2-T04** | Consultant grid read model | `list_consultant_workspace_grid` RPC + TS mapper; status + tuition label derivations | Consultant scope enforced; 4-status mapping fixtures |
| **CW2-T05** | Workspace shell & month header | `/crm/workspace` page; month nav; **`sum_consultant_attributed_payments`** (or equivalent read model over M2 payment/allocation); feature flag or nav swap | E2E: header excludes declarations-only; includes confirmed payment |
| **CW2-T06** | Grid UX (TanStack) | Virtualized grid; keyboard nav; column prefs; hide/restore row | Playwright: edit cell, tab order, hide row |
| **CW2-T07** | Inline editing & custom fields | EAV CRUD; inline validators; uppercase display policy | Cannot edit immutable columns; RLS isolation |
| **CW2-T08** | Payment declaration drawer | Draft/submit RPCs; live remainder calc; course picker read-only catalog | Pending shows **Chờ xác nhận**; no `payment.record` for consultant |
| **CW2-T09** | Accounting confirmation composition | Idempotent **confirm payment + register + assign code + attribute sales**; return/reject paths; UI on finance surface | No double payment/code/sales under retry/concurrency |
| **CW2-T10** | Student lifecycle integration | Chi tiết links; scoped student read; align with locked registration-after-payment workflow | Consultant opens enrollments hub without full admin |
| **CW2-T11** | Performance & a11y hardening | Cursor pagination; 1k/10k load tests; grid a11y pass | p95 load budget documented |
| **CW2-T12** | Regression & acceptance | `npm run verify`; new acceptance SQL; E2E consultant workspace suite; closeout doc | Milestone PASS |

## Dependency sketch

```text
T02 → T03 → T04 → T05 → T06 → T07
              ↘ T08 → T09 → T10
T06,T07 → T11 → T12
```

## Suggested verification per task

- **T02–T04:** `supabase/tests/cw2_*` + `npm run db:verify`
- **T05–T10:** Playwright consultant persona + `test:crm` extension
- **T12:** full `npm run verify`

## Out of scope (carry forward)

- Replacing executive CRM analytics (`/crm/reports` manager view).
- Mobile-native app; offline grid.
- Automatic revenue recognition on declaration approve.
