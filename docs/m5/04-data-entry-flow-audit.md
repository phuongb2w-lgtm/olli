# M5-T01 — Data-Entry Flow Audit

Principle: **Enter data where the real-world event occurs.** Other modules consume canonical state.

## Admissions (lead → student)

| Step | Entry point | Duplicate? |
|------|-------------|------------|
| Lead intake | CRM lead forms / RPCs | No |
| Activities, trials | CRM workflow RPCs | No |
| Conversion | `convert_lead` RPC → student/guardian/enrollment | **Clean** — single conversion path |

Finance is not auto-created at conversion (by design).

## Consultant revenue declaration → accountant approval

| Step | Entry point | Status |
|------|-------------|--------|
| Declare | `declare_consultant_revenue` RPC | **Foundation added T01** |
| Review | `review_consultant_revenue_declaration` RPC | Approve / reject / return |
| Canonical ledger | `payment` / recognition (future linkage on approve) | Declarations ≠ booked until approved |

No duplicate entry: consultant declares once; accountant reviews same record.

## Student → enrollment → finance

| Step | Entry point | Duplicate? |
|------|-------------|------------|
| Student profile | Academic / CRM conversion | Single identity |
| Enrollment | Enrollment forms / RPCs | Separate step, not duplicate |
| Financial terms | M2 enrollment finance | Explicit terms — not re-entering student |

## Schedule → teaching session

| Step | Entry point | Duplicate? |
|------|-------------|------------|
| Timetable pattern | `class_schedule` | Once |
| Materialized session | Generation / operations RPCs | Derived or mutated — **clean** |
| Reschedule / cancel | Session operation RPCs | Single mutation + history |

## Teacher attendance → academic review

| Step | Entry point | Duplicate? |
|------|-------------|------------|
| Teacher marks attendance | Session execution actions | Single record |
| Academic Ops confirm | **Not implemented** | **Gap:** no confirmation state; not duplicate entry |
| Reporting | Reads `attendance` | Consumes teacher entry |

## Teacher scores → academic review

Same pattern as attendance. Finalization trigger protects finalized results; no Academic Ops confirmation layer yet.

## Teacher comments → translation / review

Teacher enters `teacher_observation`. No translation/review workflow in application. **Gap for future explicit confirmation**, not duplicate entry.

## Follow-up work (post-T01)

1. Academic Operations confirmation/translation workflow design when required for quality metrics.
2. Consultant revenue approval UI (Accountant: Revenue Awaiting Review).
3. Link approved declarations to payment recording without re-entry.
