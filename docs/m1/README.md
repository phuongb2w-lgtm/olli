# M1 — Student & Guardian Operations

**Milestone:** M1  
**Baseline:** M0 closed at `d356e1d`  
**Task:** M1-T01 — design and readiness (no CRUD implementation)

---

## Purpose

M1 establishes the operational master record for people served by a language center: **Student**, **Guardian**, and the **StudentGuardian** relationship. This folder locks product and data contracts before production CRUD work begins.

M1 is **not** admissions CRM, LMS, enrollment workflow, or guardian portal access.

---

## Documents

| # | Document | Contents |
|---|----------|----------|
| 01 | [Student & Guardian Product Contract](./01-student-guardian-product-contract.md) | Scope, boundaries, bilingual terms, accessibility/responsive standards |
| 02 | [Existing Schema Audit](./02-existing-schema-audit.md) | Physical model vs M0 logical model vs generated types; drift report |
| 03 | [Student Field Contract](./03-student-field-contract.md) | Field classification, name model, student code, lifecycle, DOB |
| 04 | [Guardian & Relationship Contract](./04-guardian-relationship-contract.md) | Guardian fields, relationship types, primary/billing contact, duplicate/phone/email policy |
| 05 | [Student List & Search Contract](./05-student-list-search-contract.md) | List columns, search, filters, sort, pagination |
| 06 | [Student & Guardian Workflows](./06-student-guardian-workflows.md) | Create/edit flows, validation, errors, audit, Server Action architecture |
| 07 | [M1 Data Gap Analysis](./07-m1-data-gap-analysis.md) | Data-gap matrix, schema change recommendations, M1-T02+ task breakdown |

---

## M0 References

Do not duplicate M0 foundation docs. Canonical sources:

- [M0 canonical domain model](../m0/07-canonical-domain-model.md) — Student, Guardian, StudentGuardian entities
- [M0 physical data model](../m0/13-physical-data-model.md) — table inventory, naming
- [M0 permission model](../m0/19-permission-model.md) — 34 permission codes
- [M0 RLS policy matrix](../m0/20-rls-policy-matrix.md) — access control posture
- [M0 status code registry](../m0/31-status-code-registry.md) — machine statuses (M1 clarifies Student lifecycle semantics)
- [M0 auth application flow](../m0/24-auth-application-flow.md) — identity and org resolution

---

## M1-T01 Completion Gates

- [x] M0 baseline remains 80/80 PASS
- [x] Actual Student schema audited
- [x] Actual Guardian schema audited
- [x] StudentGuardian schema audited
- [x] Required vs optional Student fields defined
- [x] Required vs optional Guardian fields defined
- [x] Lifecycle semantics defined
- [x] Guardian reuse semantics defined
- [x] Relationship type strategy defined
- [x] Primary-contact strategy decided
- [x] Duplicate strategy defined
- [x] List columns defined
- [x] Search contract defined
- [x] Filters/sort/pagination defined
- [x] Create/edit workflows defined
- [x] Authorization mapped to existing permissions
- [x] Bilingual terminology defined
- [x] Data-gap matrix complete
- [x] No unreviewed schema migration created
- [x] No Student CRUD implemented
- [x] Next M1 tasks proposed

---

## Recommended Next Step

**Stop for product/data review** before M1-T02. See [07-m1-data-gap-analysis.md](./07-m1-data-gap-analysis.md) for proposed task breakdown and required schema decisions.
