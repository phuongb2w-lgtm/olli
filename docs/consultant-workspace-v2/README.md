# Consultant Workspace V2

**Milestone:** Consultant (Tư vấn) operational grid redesign  
**Principle:** Simple. Fast. Efficient.

| Doc | Purpose |
|-----|---------|
| [01 — T01 audit](./01-t01-consultant-workspace-v2-audit.md) | Existing architecture, gaps, conflicts, risks |
| [02 — T01 design contract](./02-t01-consultant-workspace-v2-design-contract.md) | UX contract, source-of-truth map, workflows, RBAC, grid recommendation |
| [03 — Proposed implementation sequence](./03-t01-implementation-sequence.md) | Post-gate task breakdown |

**T01 status:** **CLOSED / PASS** — design gate finalized (documentation only; CW2-T02 not started).

### Canonical product locks (T01 finalize)

| Topic | Rule |
|-------|------|
| **Doanh số tháng** | Sum of **Accounting-confirmed payment/cash** attributable to the consultant — **not** approved `consultant_revenue_declaration`. Consultant sales ≠ accounting revenue recognition. No parallel sales/revenue ledger. |
| **Registration & code** | Potential → declaration (draft/submit) → Accounting confirms **actual payment** → authoritative registration → official `CCYYNNNN` → UX **Ghi danh**. Composed workflow must be idempotent (no double payment, registration, code, or sales). |
| **Code exhaustion** | Sequence `0001`–`9999` per `(org, consultant_code, birth year)`; at exhaustion **fail closed** — no reuse of visible `CCYYNNNN`, no silent format change. `CCYY0000` remains display-only. |
