# M1 — Academic Operations

**Milestone:** M1  
**Status:** **CLOSED** (M1-T11 acceptance at `8ed07f0` baseline)  
**Baseline:** M0 closed at `d356e1d`

---

## Purpose

M1 establishes end-to-end academic operations for a language center: people (Student, Guardian), structure (Course, Class), participation (Enrollment), delivery (TeachingSession), evidence (Attendance, Observation, Assessment), and reporting (live read models).

M1 is **not** finance, parent portal, PDF export, or admissions CRM.

---

## Documents

| # | Document | Contents |
|---|----------|----------|
| 01 | [Student & Guardian Product Contract](./01-student-guardian-product-contract.md) | Scope, boundaries, bilingual terms |
| 02 | [Existing Schema Audit](./02-existing-schema-audit.md) | Physical model vs M0 |
| 03 | [Student Field Contract](./03-student-field-contract.md) | Field classification, lifecycle |
| 04 | [Guardian & Relationship Contract](./04-guardian-relationship-contract.md) | Guardian fields, primary/billing |
| 05 | [Student List & Search Contract](./05-student-list-search-contract.md) | List, search, pagination |
| 06 | [Student & Guardian Workflows](./06-student-guardian-workflows.md) | Create/edit flows |
| 07 | [M1 Data Gap Analysis](./07-m1-data-gap-analysis.md) | Gap matrix, task breakdown |
| 08 | [M1-T02 Implementation](./08-m1-t02-implementation.md) | Student list |
| 09 | [M1-T03 Implementation](./09-m1-t03-implementation.md) | Student CRUD |
| 10 | [M1-T04 Implementation](./10-m1-t04-implementation.md) | Guardian relationships |
| 11 | [M1-T05 Implementation](./11-m1-t05-implementation.md) | Course/Class |
| 12 | [M1-T06 Implementation](./12-m1-t06-implementation.md) | Enrollment, transfer |
| 13 | [M1-T07 Implementation](./13-m1-t07-implementation.md) | Teaching operations |
| 14 | [M1-T08 Implementation](./14-m1-t08-implementation.md) | Attendance, observations |
| 15 | [M1-T09 Implementation](./15-m1-t09-implementation.md) | Assessments, progress |
| 16 | [M1-T10 Implementation](./16-m1-t10-implementation.md) | Academic reporting |
| 17 | [M1 Acceptance Closeout](./17-m1-acceptance-closeout.md) | **Final acceptance, architecture audit, M1 CLOSED** |

---

## Task status (T01–T11)

| Task | Description | Status |
|------|-------------|--------|
| T01 | Design & readiness | CLOSED |
| T02 | Student list | CLOSED |
| T03 | Student CRUD | CLOSED |
| T04 | Guardian relationships | CLOSED |
| T05 | Course/Class | CLOSED |
| T06 | Enrollment/roster/transfer | CLOSED |
| T07 | Teaching operations | CLOSED |
| T08 | Session execution | CLOSED |
| T09 | Assessments | CLOSED |
| T10 | Academic reporting | CLOSED |
| T11 | Acceptance & closeout | CLOSED |

---

## M0 References

- [M0 canonical domain model](../m0/07-canonical-domain-model.md)
- [M0 physical data model](../m0/13-physical-data-model.md)
- [M0 permission model](../m0/19-permission-model.md)
- [M0 RLS policy matrix](../m0/20-rls-policy-matrix.md)

---

## Next step

**M2 Finance/Cost Foundation** — see [17-m1-acceptance-closeout.md](./17-m1-acceptance-closeout.md) §16 for deferred scope. Do not begin M2 until explicitly requested.
