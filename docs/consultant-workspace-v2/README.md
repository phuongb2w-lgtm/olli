# Consultant Workspace V2

**Milestone:** Consultant (Tư vấn) operational grid redesign  
**Principle:** Simple. Fast. Efficient.

| Doc | Purpose |
|-----|---------|
| [01 — T01 audit](./01-t01-consultant-workspace-v2-audit.md) | Existing architecture, gaps, conflicts, risks |
| [02 — T01 design contract](./02-t01-consultant-workspace-v2-design-contract.md) | UX contract, source-of-truth map, workflows, RBAC, grid recommendation |
| [03 — Proposed implementation sequence](./03-t01-implementation-sequence.md) | Post-gate task breakdown |
| [04 — CW2-T02 implementation](./04-cw2-t02-domain-schema-foundations.md) | Schema foundations closeout |
| [05 — CW2-T02.1 bootstrap](./05-cw2-t02-1-student-sequence-bootstrap.md) | Legacy student / sequence bootstrap audit |

**T01 status:** **CLOSED / PASS** — design gate finalized (documentation only).  
**T01.1:** **CLOSED / PASS** — center-wide `NNNN` sequence semantics corrected (docs only).  
**T02 status:** **CLOSED / PASS** after T02.1 acceptance (migrations 60–62, SQL tests, full verify). CW2-T03 **not started**.

### Canonical product locks (T01 finalize)

| Topic | Rule |
|-------|------|
| **Doanh số tháng** | Sum of **Accounting-confirmed payment/cash** attributable to the consultant — **not** approved `consultant_revenue_declaration`. Consultant sales ≠ accounting revenue recognition. No parallel sales/revenue ledger. |
| **Registration & code** | Potential → declaration (draft/submit) → Accounting confirms **actual payment** → authoritative registration → official `CCYYNNNN` → UX **Ghi danh**. Composed workflow must be idempotent (no double payment, registration, code, or sales). |
| **Student code `NNNN`** | **Organization-wide** center sequence only (`org → 0001…9999`). **Not** scoped by consultant or birth year. Official code = `CC` + `YY` + next center sequence (e.g. `02170037`, then `05150038`, then `02180039`). |
| **Code exhaustion** | When center reaches **`9999`** allocated sequences: **fail closed** — no rollover, reuse, or format change. `CCYY0000` provisional display remains non-persisted. |
