# M0-T03 — Database Indexes

**Date:** 2026-09-14

Indexes added for documented access patterns. PostgreSQL does not auto-index FK columns.

---

## People

| Table | Index | Purpose |
|-------|-------|---------|
| `app_user` | `(organization_id)` | Tenant listing |
| `app_user` | `(organization_id) WHERE status = 'active'` | Active users |
| `student` | `(organization_id)` | Tenant listing |
| `student` | `(organization_id, status) WHERE status = 'active'` | Active students |
| `guardian` | `(organization_id)` | Tenant listing |
| `guardian` | `(organization_id) WHERE status = 'active'` | Active guardians |
| `student_guardian` | `(organization_id, student_id)` | Guardians by student |
| `student_guardian` | `(organization_id, guardian_id)` | Students by guardian |
| `teacher` | `(organization_id)` | Tenant listing |
| `teacher` | `(organization_id) WHERE status = 'active'` | Active teachers |

---

## Academic Operations

| Table | Index | Purpose |
|-------|-------|---------|
| `class` | `(organization_id, course_id)` | Classes by course |
| `class` | `(organization_id, status)` | Active/completed classes |
| `class_schedule` | `(organization_id, class_id)` | Schedules by class |
| `enrollment` | `(organization_id, student_id, status, start_date)` | Student enrollment history |
| `enrollment` | `(organization_id, class_id, status, start_date)` | Class roster / timeline |
| `class_teacher_assignment` | `(organization_id, class_id)` | Teacher assignments |
| `teaching_session` | `(organization_id, class_id, scheduled_start_at)` | Sessions by class/time |
| `teaching_session` | `(organization_id, teacher_id)` | Sessions by teacher |
| `attendance` | `(teaching_session_id)` | Roll call by session |
| `attendance` | `(organization_id, enrollment_id)` | Attendance by enrollment |

---

## Learning Evidence

| Table | Index | Purpose |
|-------|-------|---------|
| `assessment` | `(organization_id, class_id)` | Assessments by class |
| `assessment_result` | `(organization_id, enrollment_id)` | Results by enrollment |
| `teacher_observation` | `(organization_id, enrollment_id, observed_at)` | Observations timeline |
| `observation_rating` | `(teacher_observation_id)` | Ratings by observation |
| `progress_evaluation` | `(organization_id, enrollment_id, evaluated_at)` | Progress timeline |

---

## Finance

| Table | Index | Purpose |
|-------|-------|---------|
| `tuition_plan` | `(organization_id, course_id, class_id, effective_from)` | Price lookup |
| `charge` | `(organization_id, enrollment_id)` | Charges by enrollment |
| `charge` | `(organization_id, guardian_id, due_date)` | Receivables by payer |
| `charge` | `(organization_id, status)` | Open charges |
| `financial_adjustment` | `(organization_id, charge_id)` | Adjustments by charge |
| `payment` | `(organization_id, guardian_id, paid_at)` | Payments by payer/date |
| `payment_allocation` | `(organization_id, charge_id)` | Allocations by charge |
| `payment_allocation` | `(payment_id)` | Allocations by payment |
| `cost_group` | `(organization_id)` | Cost groups by org |
| `expense_category` | `(organization_id, cost_group_id)` | Categories by group |
| `expense` | `(organization_id, incurred_date)` | Expenses by date |
| `expense` | `(organization_id, expense_category_id)` | Expenses by category |
| `expense` | `(organization_id, cost_group_id)` | Expenses by group snapshot |

---

## Not Indexed (Intentionally)

- Every FK column — only indexed where query patterns justify
- Derived/computed fields — none stored
- Full-text on comments — deferred to application search needs

---

## Future Index Candidates (M0-T04+)

- Partial index on `charge` WHERE status IN (`open`, `partially_paid`) for aging reports
- Composite `(organization_id, incurred_date, cost_group_id)` on expense for P&L queries
- Materialized views for dashboard KPIs if query latency requires
