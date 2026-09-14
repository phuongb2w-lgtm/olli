# M0-T02 — Entity Relations & Cardinality

**Date:** 2026-09-14

Complete relationship reference for the canonical domain model. All FKs use UUID unless noted.

---

## Relationship Matrix

| From | To | Cardinality | FK location | Notes |
|------|-----|-------------|-------------|-------|
| Organization | User | 1:N | User.organization_id | Tenant boundary |
| Organization | Student, Guardian, Teacher, Course, Class, … | 1:N | *.organization_id | All tenant data |
| User | Role | N:M | UserRole | Effective-dated |
| Role | Permission | N:M | RolePermission | |
| Teacher | User | N:1 | Teacher.user_id (nullable) | Optional login link |
| Student | Guardian | N:M | StudentGuardian | Multiple guardians; shared guardians |
| Student | Class | N:M | Enrollment | **Temporal** bridge — not direct |
| Course | Class | 1:N | Class.course_id | |
| Class | ClassSchedule | 1:N | ClassSchedule.class_id | Planned recurrence |
| Class | Teacher | N:M | ClassTeacherAssignment | Effective-dated |
| Class | TeachingSession | 1:N | TeachingSession.class_id | |
| ClassSchedule | TeachingSession | 1:N | TeachingSession.class_schedule_id (nullable) | Optional lineage |
| Class | Enrollment | 1:N | Enrollment.class_id | |
| Enrollment | TeachingSession | N:M | via Attendance | Indirect |
| Enrollment | Attendance | 1:N | Attendance.enrollment_id | **Primary attendance context** |
| TeachingSession | Attendance | 1:N | Attendance.teaching_session_id | |
| TeachingSession | Teacher | N:1 | TeachingSession.teacher_id | **Session-specific, immutable** |
| Class | Assessment | 1:N | Assessment.class_id | |
| Assessment | AssessmentResult | 1:N | AssessmentResult.assessment_id | |
| Enrollment | AssessmentResult | 1:N | AssessmentResult.enrollment_id | |
| Enrollment | TeacherObservation | 1:N | TeacherObservation.enrollment_id | |
| TeacherObservation | ObservationRating | 1:N | ObservationRating.teacher_observation_id | |
| Enrollment | ProgressEvaluation | 1:N | ProgressEvaluation.enrollment_id | |
| TuitionPlan | Charge | 1:N | Charge.tuition_plan_id (nullable) | Reference only; amount snapshotted |
| Enrollment | Charge | 1:N | Charge.enrollment_id | |
| Guardian | Charge | 1:N | Charge.guardian_id | Billing contact |
| Charge | FinancialAdjustment | 1:N | FinancialAdjustment.charge_id | |
| Guardian | Payment | 1:N | Payment.guardian_id | Payer |
| Payment | Charge | N:M | PaymentAllocation | Partial / multi-charge |
| CostGroup | ExpenseCategory | 1:N | ExpenseCategory.cost_group_id | Exactly 2 groups per org |
| ExpenseCategory | Expense | 1:N | Expense.expense_category_id | |
| CostGroup | Expense | 1:N | Expense.cost_group_id | **Snapshot at post time** |
| Teacher | Expense | 1:N | Expense.teacher_id (optional) | Direct cost attribution |
| Class | Expense | 1:N | Expense.class_id (optional) | Optional attribution |

---

## User vs Teacher Relationship

```
User (authentication)          Teacher (business identity)
┌─────────────────┐           ┌─────────────────┐
│ id              │◄──────────│ user_id (null)  │
│ email           │  0..1     │ employee_code   │
│ preferred_locale│           │ given_name      │
└─────────────────┘           └─────────────────┘
        │                               │
        │ UserRole                      │ ClassTeacherAssignment
        ▼                               ▼ TeachingSession.teacher_id
     Role / Permission              Academic + cost domain
```

- Admin/accountant users: User exists, Teacher does not.
- Teacher with login: Teacher.user_id → User.
- Teacher without login: Teacher exists, user_id is null.

---

## Enrollment as Historical Bridge

```
Student ──< Enrollment >── Class
              │
              ├── start_date, end_date
              ├── status (active | transferred | withdrawn | completed)
              │
              ├──< Attendance
              ├──< AssessmentResult
              ├──< TeacherObservation
              ├──< ProgressEvaluation
              └──< Charge
```

**Current class query (derived, not stored):**

```sql
-- Conceptual: student's current classes
SELECT c.* FROM enrollment e
JOIN class c ON c.id = e.class_id
WHERE e.student_id = :student_id
  AND e.status = 'active'
  AND (e.end_date IS NULL OR e.end_date >= CURRENT_DATE);
```

---

## Enrollment Temporal Rules

| Rule | Implementation |
|------|----------------|
| No `current_class_id` on Student | Derived from active Enrollment |
| Transfer Class A → B | Close A: `status=transferred`, set `end_date`; create new Enrollment for B |
| Rejoin same class later | New Enrollment row with new `start_date` |
| Overlap prohibition | No two `active` enrollments for same `(student_id, class_id)` with overlapping dates |
| Historical integrity | Never UPDATE `class_id` on existing Enrollment |

**Suggested constraint (M0-T03):** exclusion constraint or application-enforced check on `(student_id, class_id, daterange(start_date, end_date))` where status IN (`pending`, `active`).

---

## ClassSchedule vs TeachingSession

```
Class
  │
  ├──< ClassSchedule (planned: Mon 18:00–20:00, effective Jan–Mar)
  │         │
  │         └── generates / links ──> TeachingSession (2026-01-06 18:00, teacher=T1, status=completed)
  │                                   TeachingSession (2026-01-13 18:00, teacher=T1, status=completed)
  │                                   TeachingSession (2026-02-03 18:00, teacher=T2, status=completed)
  │
  └──< ClassTeacherAssignment (T1: Jan–Feb, T2: Feb–Mar)
```

- **ClassSchedule** changes affect **future** session generation only.
- **TeachingSession** records what was scheduled and what occurred, with **session-level teacher_id**.

---

## Attendance Relationship Decision

**Primary FK: `enrollment_id`**

| Option | Verdict | Reason |
|--------|---------|--------|
| Attendance → Student only | Rejected | Loses class context if student transfers |
| Attendance → Enrollment + Session | **Accepted** | Enrollment anchors student-to-class period; session anchors event |
| Attendance counter on Student | Rejected | Derived aggregate |

**Uniqueness:** `UNIQUE(teaching_session_id, enrollment_id)`

**Validation rule:** Enrollment must belong to the same class as TeachingSession.class_id (application or DB check).

---

## Learning Evidence Anchoring

All learning evidence anchors to **Enrollment** (which implies Student + Class):

| Entity | Required FKs |
|--------|--------------|
| AssessmentResult | assessment_id, enrollment_id, student_id |
| TeacherObservation | enrollment_id, student_id, class_id, teacher_id |
| ProgressEvaluation | enrollment_id, student_id, class_id, teacher_id |

`student_id` duplicated for query convenience; enrollment is authoritative context.

---

## Finance Relationship Chain

```
TuitionPlan (effective-dated pricing)
       │
       ▼
    Charge ◄──── FinancialAdjustment (discount, waiver, correction, reversal)
       │
       ▼
PaymentAllocation ◄──── Payment
       │
       └── outstanding = charge.amount + Σ adjustments − Σ allocations
```

**No Receivable entity.** An "invoice" is a **derived presentation** grouping open charges for a guardian.

---

## Cost Architecture Relations

```
Organization
    └── CostGroup (group_slot: 1 | 2)     ← exactly two per org; labels pending
            └── ExpenseCategory
                    └── Expense
                            ├── expense_category_id  (current category reference)
                            └── cost_group_id        (snapshot at post — historical truth)
```

---

## Organization Scope Summary

| Entity | organization_id |
|--------|-----------------|
| All business entities | Required |
| Permission | Global catalog OR org-scoped (recommend org-scoped Role; Permission may be shared seed) |
| RolePermission, UserRole | Via parent |

---

## ON DELETE Policy (Logical — for M0-T03)

| Parent | Child | Policy |
|--------|-------|--------|
| Organization | Any | RESTRICT |
| Student, Guardian, Teacher | Enrollment, evidence, FT | RESTRICT (archive parent instead) |
| Class | Enrollment, Session | RESTRICT |
| Enrollment | Attendance, evidence | RESTRICT |
| Charge | PaymentAllocation, Adjustment | RESTRICT |
| Payment | PaymentAllocation | RESTRICT |
| CostGroup | ExpenseCategory | RESTRICT if categories exist |
