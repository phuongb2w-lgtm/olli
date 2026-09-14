# M0-T03 — Database Constraints

**Date:** 2026-09-14

---

## Cross-Organization Integrity Pattern

**Pattern:** Composite unique + composite foreign keys on tenant-owned tables.

```sql
-- On child table:
UNIQUE (organization_id, id)

-- FK example:
FOREIGN KEY (organization_id, student_id)
  REFERENCES student (organization_id, id)
```

This prevents an enrollment in Org A from referencing a student in Org B even if UUIDs were guessed.

**Exceptions (single-column FK with org validation elsewhere):**
- `teacher.user_id` → `app_user(id)` + trigger `validate_teacher_user_org`
- `class_schedule_id`, `teaching_session_id` on optional links — SET NULL on delete; org consistency enforced by application/trigger where composite FK would null `organization_id` incorrectly

---

## Enrollment Overlap Protection

**Extension:** `btree_gist`

**Constraint:** Exclusion on `(organization_id, student_id, class_id, daterange)` for active periods:

```sql
EXCLUDE USING gist (
  organization_id WITH =,
  student_id WITH =,
  class_id WITH =,
  daterange(start_date, COALESCE(end_date, 'infinity'::date), '[)') WITH &&
) WHERE (status IN ('pending', 'active'))
```

| Status | Overlap check |
|--------|---------------|
| `pending`, `active` | Included — cannot overlap same student+class |
| `transferred`, `withdrawn`, `completed` | Excluded — historical periods may exist; rejoin allowed with new row |

Open-ended enrollments: `end_date IS NULL` → `infinity` upper bound.

---

## Attendance Integrity

| Constraint | Type |
|------------|------|
| `UNIQUE (teaching_session_id, enrollment_id)` | Unique |
| `validate_attendance_context()` trigger | Enrollment class must match session class; same org |

**No `student_id` column** — student derived via `enrollment → student`.

---

## TeachingSession Teacher Protection

| Rule | Mechanism |
|------|-----------|
| Session stores own `teacher_id` | Column on `teaching_session` |
| Completed session teacher immutable | Trigger `protect_completed_session_teacher` |

---

## AssessmentResult Integrity

| Constraint | Type |
|------------|------|
| `max_score > 0` | CHECK |
| `raw_score BETWEEN 0 AND max_score` | CHECK |
| Finalized score immutable | Trigger `protect_finalized_assessment_result` |
| `UNIQUE (assessment_id, enrollment_id)` | One result per student per assessment |

Normalized percentage: **not stored** — derive as `raw_score / max_score`.

---

## ObservationRating Integrity

| Constraint | Type |
|------------|------|
| `UNIQUE (teacher_observation_id, indicator_code)` | No duplicate indicators |
| `indicator_code` FK → `observation_indicator(code)` | Controlled domain |

---

## Finance Constraints

### Charge (sole debt source)

- `amount > 0` CHECK
- No `outstanding_balance` or `total_paid` columns
- Amount immutable after creation (application rule; adjustments separate)

### FinancialAdjustment

- `amount_delta <> 0` CHECK
- **Sign convention:** positive increases debt, negative decreases
- Types: `discount`, `waiver`, `correction`, `reversal`

### PaymentAllocation

- `amount > 0` CHECK
- Trigger `validate_payment_allocations`: `SUM(allocations) <= payment.amount`

### Outstanding balance (derived)

```text
charge.amount
+ SUM(financial_adjustment.amount_delta WHERE status='posted')
- SUM(payment_allocation.amount)
```

View: `charge_balance`

---

## Cost B Constraints

| Rule | Mechanism |
|------|-----------|
| Exactly 2 slots | `group_slot IN (1, 2)` + `UNIQUE(organization_id, group_slot)` |
| Auto-init on org create | Trigger `initialize_organization_cost_groups` |
| No guessed business codes | `code` column nullable |
| Category reparent blocked after use | Trigger `prevent_expense_category_reparent` |
| Expense group snapshot | `expense.cost_group_id` validated against category at insert |

---

## ON DELETE Policy Summary

| Relationship | Policy | Rationale |
|--------------|--------|-----------|
| Organization → any business data | RESTRICT | Never delete tenant with data |
| Student/Teacher/Class → Enrollment/Session | RESTRICT | History survives |
| Enrollment → Attendance/Evidence | RESTRICT | Historical records |
| Charge/Payment → Allocations/Adjustments | RESTRICT | Financial audit trail |
| Role → role_permission | CASCADE | Junction cleanup when role removed (role removal rare) |
| TeacherObservation → ObservationRating | CASCADE | Ratings are dependent detail |
| Optional user/schedule links | SET NULL (single-column FK only) | Preserve parent record |

**No CASCADE** on financial or historical academic chains.

---

## Status CHECK Constraints

All status fields use `text` + `CHECK` (not PostgreSQL ENUM) for migration flexibility. Values are stable machine codes — see migration file for complete lists.
