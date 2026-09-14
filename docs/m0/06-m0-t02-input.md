# M0-T01 — Proposed Input for M0-T02 (Relational Modelling)

**Date:** 2026-09-14  
**Prerequisite:** Cost B two-group structure confirmed by stakeholder

M0-T02 should produce **detailed relational models** (ER diagram, table definitions, keys, constraints) for the entity set below. M0-T02 should **not** implement UI or application code.

---

## Modelling Order (Recommended)

### Phase A — Spine (model first)

These entities form the tenant and identity backbone. Almost every other table references them.

| # | Entity | Priority | Notes |
|---|--------|----------|-------|
| 1 | Organization | P0 | Tenant root |
| 2 | User | P0 | Auth identity |
| 3 | Role | P0 | Stable codes |
| 4 | Permission | P0 | Stable codes |
| 5 | UserRole | P0 | Effective-dated assignment |
| 6 | Student | P0 | Core people |
| 7 | Guardian | P0 | Core people |
| 8 | StudentGuardian | P0 | Relationship + type codes |
| 9 | Teacher | P0 | Core people; optional user_id |

### Phase B — Academic core

| # | Entity | Priority | Notes |
|---|--------|----------|-------|
| 10 | Course | P0 | Catalog |
| 11 | Class | P0 | Operational instance |
| 12 | Enrollment | P0 | **Critical history semantics** |
| 13 | ClassTeacherAssignment | P0 | Effective-dated |
| 14 | TeachingSession | P0 | Event with teacher context |
| 15 | Attendance | P0 | Per session per student |

### Phase C — Finance foundation

| # | Entity | Priority | Notes |
|---|--------|----------|-------|
| 16 | FinancialPeriod | P0 | Reporting window |
| 17 | CostGroup | P0 | **Exactly two rows per org** |
| 18 | ExpenseCategory | P0 | FK to CostGroup |
| 19 | TuitionPlan | P0 | Effective-dated pricing |
| 20 | Charge | P0 | Immutable fee lines |
| 21 | Receivable | P1 | Invoice header |
| 22 | InvoiceLine | P1 | Links receivable to charges |
| 23 | Payment | P1 | Immutable |
| 24 | PaymentAllocation | P1 | Apply payment to receivable |
| 25 | DiscountAdjustment | P1 | Corrections/discounts |
| 26 | Expense | P1 | With category + optional teacher/class FK |

### Phase D — Learning evidence (M0-T02 if time; else M0-T03)

| # | Entity | Priority | Notes |
|---|--------|----------|-------|
| 27 | Assessment | P1 | Event tied to class |
| 28 | AssessmentResult | P1 | Per student |
| 29 | TeacherObservation | P2 | Qualitative evidence |
| 30 | ProgressEvaluation | P2 | Periodic summary |

### Phase E — Configuration (can parallel Phase A)

| # | Entity | Priority | Notes |
|---|--------|----------|-------|
| 31 | LocalePreference | P1 | User/org default locale |
| 32 | OrganizationSettings | P1 | Key-value or typed settings table |

---

## Exact Entity Set for M0-T02 (Minimum Lock)

**Enter detailed relational modelling in M0-T02 for these 26 entities:**

1. Organization  
2. User  
3. Role  
4. Permission  
5. UserRole  
6. Student  
7. Guardian  
8. StudentGuardian  
9. Teacher  
10. Course  
11. Class  
12. Enrollment  
13. ClassTeacherAssignment  
14. TeachingSession  
15. Attendance  
16. FinancialPeriod  
17. CostGroup  
18. ExpenseCategory  
19. TuitionPlan  
20. Charge  
21. Receivable  
22. InvoiceLine  
23. Payment  
24. PaymentAllocation  
25. DiscountAdjustment  
26. Expense  

**Defer to M0-T03 if M0-T02 capacity limited:** Assessment, AssessmentResult, TeacherObservation, ProgressEvaluation, LocalePreference, OrganizationSettings.

---

## M0-T02 Deliverable Expectations

For each entity in the minimum lock set, M0-T02 should define:

- [ ] Table name and columns with types  
- [ ] Primary key (prefer UUID or bigint — decide in M0-T02)  
- [ ] Foreign keys and ON DELETE rules (restrict for FT, soft for MD)  
- [ ] Unique constraints (e.g. one open enrollment per student-class if business rule confirms)  
- [ ] Status enums as check constraints or lookup tables (codes, not labels)  
- [ ] Effective date columns where specified  
- [ ] `created_at`, `updated_at`, `created_by`, `updated_by` columns  
- [ ] Index plan for common joins (enrollment by student, session by class, expense by period)  
- [ ] Explicit note on immutability rules for financial and attendance records  

M0-T02 should also produce:

- [ ] ER diagram covering all 26 entities  
- [ ] Cost B constraint documentation (two CostGroup per organization)  
- [ ] i18n boundary note (which columns are codes vs translatable display)  
- [ ] List of computed values **not** stored as columns  

---

## Schema Rules to Enforce in M0-T02

1. Every business table includes `organization_id` (except global Permission if shared).  
2. No translated labels in domain identifier columns.  
3. Enrollment period is immutable — status changes via lifecycle, not by rewriting dates.  
4. Charge.amount is set at creation from TuitionPlan version — not live-looked-up.  
5. Expense stores reference to CostGroup (directly or via denormalized snapshot on post).  
6. CostGroup.code ∈ {`operating`, `teacher_direct`} — enforce or seed exactly two per org.  
7. Soft delete via `archived_at` or `status = inactive` — no hard delete on referenced MD/FT.  

---

## Out of Scope for M0-T02

- UI pages or forms  
- API endpoint design (optional sketch only)  
- Migration scripts to production  
- Seed data beyond reference codes  
- Materialized reporting views  
- Full audit_log table (document FK targets only)

---

## Decision Points for M0-T02 Kickoff

Before starting M0-T02, confirm:

1. ✅ Cost B group definitions and initial ExpenseCategory list  
2. ✅ Single-tenant vs multi-tenant (recommend multi-tenant-ready schema)  
3. ✅ Primary key strategy (UUID recommended for distributed future)  
4. ✅ Database engine (PostgreSQL recommended for reporting and constraints)  
5. ⬜ Enrollment uniqueness rules (one active enrollment per class per student?)  
6. ⬜ Default currency and timezone for Organization  
