# M0 — Status Code Registry

**Purpose:** Application/documentation contract for stable machine statuses and type codes.  
**Source of truth:** PostgreSQL CHECK constraints and reference tables in migrations — this document does not duplicate DB enforcement.

For each entry: **code**, **domain**, **meaning**, **mutable lifecycle?**, **user-facing?**, **translation namespace**.

---

## Organization

| Code | Domain | Meaning | Mutable? | User-facing? | Translation namespace |
|------|--------|---------|----------|--------------|----------------------|
| `active` | organization | Organization is operational | yes | yes | `status.organization.active` |
| `inactive` | organization | Organization suspended/archived | yes | yes | `status.organization.inactive` |

---

## App User

| Code | Domain | Meaning | Mutable? | User-facing? | Translation namespace |
|------|--------|---------|----------|--------------|----------------------|
| `active` | app_user | User may sign in and operate | yes (admin) | yes | `status.appUser.active` |
| `inactive` | app_user | User disabled | yes (admin) | yes | `status.appUser.inactive` |
| `locked` | app_user | User locked pending review | yes (admin) | yes | `status.appUser.locked` |

---

## Role & User Role

| Code | Domain | Meaning | Mutable? | User-facing? | Translation namespace |
|------|--------|---------|----------|--------------|----------------------|
| `active` | role | Role assignable | yes | rarely | `status.role.active` |
| `inactive` | role | Role retired | yes | rarely | `status.role.inactive` |
| `active` | user_role | Assignment currently effective | yes | rarely | `status.userRole.active` |
| `ended` | user_role | Assignment ended | yes | rarely | `status.userRole.ended` |

---

## Student

| Code | Domain | Meaning | Mutable? | User-facing? | Translation namespace |
|------|--------|---------|----------|--------------|----------------------|
| `prospect` | student | Lead / not yet enrolled | yes | yes | `status.student.prospect` |
| `active` | student | Currently enrolled participant | yes | yes | `status.student.active` |
| `inactive` | student | Temporarily inactive | yes | yes | `status.student.inactive` |
| `graduated` | student | Completed program | yes | yes | `status.student.graduated` |
| `withdrawn` | student | Left before completion | yes | yes | `status.student.withdrawn` |

---

## Guardian

| Code | Domain | Meaning | Mutable? | User-facing? | Translation namespace |
|------|--------|---------|----------|--------------|----------------------|
| `active` | guardian | Active contact | yes | yes | `status.guardian.active` |
| `inactive` | guardian | Retired contact | yes | yes | `status.guardian.inactive` |

---

## Student–Guardian Relationship

| Code | Domain | Meaning | Mutable? | User-facing? | Translation namespace |
|------|--------|---------|----------|--------------|----------------------|
| `active` | student_guardian | Link active | yes | yes | `status.studentGuardian.active` |
| `ended` | student_guardian | Link ended | yes | yes | `status.studentGuardian.ended` |

**Relationship type codes:** `mother`, `father`, `guardian`, `other` → `relationship.studentGuardian.*`

---

## Teacher

| Code | Domain | Meaning | Mutable? | User-facing? | Translation namespace |
|------|--------|---------|----------|--------------|----------------------|
| `active` | teacher | Teaching | yes | yes | `status.teacher.active` |
| `inactive` | teacher | Not currently teaching | yes | yes | `status.teacher.inactive` |
| `on_leave` | teacher | Temporary leave | yes | yes | `status.teacher.onLeave` |
| `terminated` | teacher | Employment ended | yes | yes | `status.teacher.terminated` |

---

## Course & Class

| Code | Domain | Meaning | Mutable? | User-facing? | Translation namespace |
|------|--------|---------|----------|--------------|----------------------|
| `active` | course | Offered | yes | yes | `status.course.active` |
| `inactive` | course | Not offered | yes | yes | `status.course.inactive` |
| `archived` | course | Historical only | yes | yes | `status.course.archived` |
| `planned` | class | Scheduled, not started | yes | yes | `status.class.planned` |
| `active` | class | In progress | yes | yes | `status.class.active` |
| `completed` | class | Finished | yes | yes | `status.class.completed` |
| `cancelled` | class | Cancelled before completion | yes | yes | `status.class.cancelled` |

---

## Class Schedule & Teacher Assignment

| Code | Domain | Meaning | Mutable? | User-facing? | Translation namespace |
|------|--------|---------|----------|--------------|----------------------|
| `active` | class_schedule | Schedule slot active | yes | yes | `status.classSchedule.active` |
| `ended` | class_schedule | Schedule slot ended | yes | yes | `status.classSchedule.ended` |
| `active` | class_teacher_assignment | Teacher assigned | yes | yes | `status.classTeacherAssignment.active` |
| `ended` | class_teacher_assignment | Assignment ended | yes | yes | `status.classTeacherAssignment.ended` |

**Weekday codes:** `mon`–`sun` → `weekday.*`  
**Assignment role codes:** `primary`, `assistant` → `classTeacherRole.*`

---

## Enrollment

| Code | Domain | Meaning | Mutable? | User-facing? | Translation namespace |
|------|--------|---------|----------|--------------|----------------------|
| `pending` | enrollment | Awaiting start | yes | yes | `status.enrollment.pending` |
| `active` | enrollment | Currently enrolled | yes | yes | `status.enrollment.active` |
| `transferred` | enrollment | Moved to another class | yes | yes | `status.enrollment.transferred` |
| `withdrawn` | enrollment | Left class | yes | yes | `status.enrollment.withdrawn` |
| `completed` | enrollment | Finished class | yes | yes | `status.enrollment.completed` |

---

## Teaching Session

| Code | Domain | Meaning | Mutable? | User-facing? | Translation namespace |
|------|--------|---------|----------|--------------|----------------------|
| `scheduled` | teaching_session | Planned session | yes | yes | `status.teachingSession.scheduled` |
| `in_progress` | teaching_session | Session underway | yes | yes | `status.teachingSession.inProgress` |
| `completed` | teaching_session | Session finished | yes | yes | `status.teachingSession.completed` |
| `cancelled` | teaching_session | Session cancelled | yes | yes | `status.teachingSession.cancelled` |

---

## Attendance

| Code | Domain | Meaning | Mutable? | User-facing? | Translation namespace |
|------|--------|---------|----------|--------------|----------------------|
| `present` | attendance | Student attended | yes | yes | `status.attendance.present` |
| `absent` | attendance | Student absent | yes | yes | `status.attendance.absent` |
| `late` | attendance | Arrived late | yes | yes | `status.attendance.late` |
| `excused` | attendance | Excused absence | yes | yes | `status.attendance.excused` |

---

## Assessment & Results

| Code | Domain | Meaning | Mutable? | User-facing? | Translation namespace |
|------|--------|---------|----------|--------------|----------------------|
| `draft` | assessment | Not yet open | yes | yes | `status.assessment.draft` |
| `open` | assessment | Accepting results | yes | yes | `status.assessment.open` |
| `closed` | assessment | No new results | yes | yes | `status.assessment.closed` |
| `draft` | assessment_result | Provisional result | yes | yes | `status.assessmentResult.draft` |
| `finalized` | assessment_result | Locked result | limited | yes | `status.assessmentResult.finalized` |
| `corrected` | assessment_result | Corrected after finalize | append-only | yes | `status.assessmentResult.corrected` |

---

## Teacher Observation

| Code | Domain | Meaning | Mutable? | User-facing? | Translation namespace |
|------|--------|---------|----------|--------------|----------------------|
| `draft` | teacher_observation | In progress | yes | yes | `status.teacherObservation.draft` |
| `recorded` | teacher_observation | Recorded observation | limited | yes | `status.teacherObservation.recorded` |
| `void` | teacher_observation | Voided observation | yes | yes | `status.teacherObservation.void` |

**Rating codes:** `low`, `medium`, `high` → `observationRating.*`

---

## Progress Evaluation

| Code | Domain | Meaning | Mutable? | User-facing? | Translation namespace |
|------|--------|---------|----------|--------------|----------------------|
| `draft` | progress_evaluation | Draft evaluation | yes | yes | `status.progressEvaluation.draft` |
| `finalized` | progress_evaluation | Final evaluation | limited | yes | `status.progressEvaluation.finalized` |

**Progress level codes:** `below_expectation`, `on_track`, `above_expectation` → `progressLevel.*`  
**Improvement codes:** `declined`, `stable`, `improved`, `significantly_improved` → `improvement.*`

---

## Finance — Tuition & Charges

| Code | Domain | Meaning | Mutable? | User-facing? | Translation namespace |
|------|--------|---------|----------|--------------|----------------------|
| `active` | tuition_plan | Plan available | yes | yes | `status.tuitionPlan.active` |
| `inactive` | tuition_plan | Plan unavailable | yes | yes | `status.tuitionPlan.inactive` |
| `archived` | tuition_plan | Historical plan | yes | yes | `status.tuitionPlan.archived` |
| `open` | charge | Outstanding debt | yes | yes | `status.charge.open` |
| `partially_paid` | charge | Partially settled | derived | yes | `status.charge.partiallyPaid` |
| `paid` | charge | Fully settled | derived | yes | `status.charge.paid` |
| `void` | charge | Charge voided | yes | yes | `status.charge.void` |

---

## Finance — Adjustments & Payments

| Code | Domain | Meaning | Mutable? | User-facing? | Translation namespace |
|------|--------|---------|----------|--------------|----------------------|
| `posted` | financial_adjustment | Adjustment applied | append-only | yes | `status.financialAdjustment.posted` |
| `void` | financial_adjustment | Adjustment voided | yes | yes | `status.financialAdjustment.void` |
| `posted` | payment | Payment recorded | append-only | yes | `status.payment.posted` |
| `void` | payment | Payment voided | yes | yes | `status.payment.void` |

**Adjustment type codes:** `discount`, `waiver`, `correction`, `reversal` → `adjustmentType.*`

---

## Finance — Cost & Expense

| Code | Domain | Meaning | Mutable? | User-facing? | Translation namespace |
|------|--------|---------|----------|--------------|----------------------|
| `active` | cost_group | Cost group active | yes | yes | `status.costGroup.active` |
| `inactive` | cost_group | Cost group inactive | yes | yes | `status.costGroup.inactive` |
| `active` | expense_category | Category active | yes | yes | `status.expenseCategory.active` |
| `inactive` | expense_category | Category inactive | yes | yes | `status.expenseCategory.inactive` |
| `archived` | expense_category | Category archived | yes | yes | `status.expenseCategory.archived` |
| `posted` | expense | Expense recorded | append-only | yes | `status.expense.posted` |
| `void` | expense | Expense voided | yes | yes | `status.expense.void` |

---

## Locale Codes

| Code | Domain | Meaning | Mutable? | User-facing? | Translation namespace |
|------|--------|---------|----------|--------------|----------------------|
| `vi` | locale | Vietnamese presentation | yes (self) | yes | `common.vietnamese` |
| `en` | locale | English presentation | yes (self) | yes | `common.english` |

---

## Conventions

- **User-facing** statuses require entries under `status.<domain>.<code>` when surfaced in UI.
- **Validation errors** use `validation.*` namespace (see `messages/*.json`).
- **Navigation** uses `shell.*` namespace.
- Percentage formatting reserved for future modules via `formatPercentage()` helper pattern.
