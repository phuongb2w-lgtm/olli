# M1-T06 — Enrollment & Class Roster Implementation

**Task:** M1-T06  
**Baseline:** M1-T05 at `98dcaa5`  
**Permissions:** `enrollment.read`, `enrollment.create`, `enrollment.update`

---

## Existing Enrollment Schema (M0 — unchanged core)

| Column | Type | Notes |
|--------|------|-------|
| `student_id`, `class_id` | uuid | Composite FKs with `organization_id` |
| `start_date` | date NOT NULL | |
| `end_date` | date | Nullable while ongoing |
| `status` | text | `pending`, `active`, `transferred`, `withdrawn`, `completed` |
| Audit | | `created_by`, `updated_by` (+ FK in M1-T06 migration) |

**Overlap invariant (preserved):** `enrollment_no_overlap` EXCLUDE on `(organization_id, student_id, class_id, daterange)` WHERE status IN (`pending`, `active`).

No `UNIQUE(student_id, class_id)` — historical re-enrollment allowed.

---

## Migration

`20260914141100_m1_t06_enrollment_audit_transfer.sql`:

1. Audit FK constraints on `enrollment`
2. `transfer_enrollment()` RPC — **SECURITY INVOKER**, single transaction: source → `transferred` + end date; insert destination enrollment

---

## Enrollment Lifecycle

| Status | Meaning |
|--------|---------|
| `pending` | Prepared, not yet active participation |
| `active` | Currently participating |
| `transferred` | Ended due to move to another class |
| `withdrawn` | Left before normal completion |
| `completed` | Finished participation |

Student lifecycle is never mutated by enrollment operations.

---

## Create / Re-enroll

- Initial statuses: `pending` or `active` only
- Closed class rejects new enrollment
- Class status rules: `planned` → `pending` only; `trial`/`active` → `pending` or `active`
- Capacity: operational count (`pending`/`active`) must not exceed positive `class.capacity`; null capacity = unlimited
- Overlap conflicts return friendly `overlap_conflict` (Postgres `23P01`)
- Re-enroll after terminal status creates **new** enrollment row

---

## Transfer

1. Source enrollment → `transferred` + `end_date`
2. **New** destination enrollment inserted (source `class_id` never changes)
3. Atomic via `transfer_enrollment` RPC
4. Destination capacity and org validated inside RPC

---

## Class Roster

Route: `/classes/[id]/roster`

Derived from `enrollment` joined to `student`. Default filter: operational (`pending`/`active`). Server-side search by student name/code before pagination.

---

## Student History

Route: `/students/[id]/enrollments`

All enrollments for student, newest first. Each enrollment = one row (no collapsing).

Enroll routes:
- `/classes/[id]/roster/enroll`
- `/students/[id]/enrollments/enroll`

---

## Boundaries (not implemented)

- No `Student.current_class_id`
- No Attendance, TeachingSession, ClassSchedule CRUD
- No finance/tuition mutations
- No rewriting `class_id` on existing enrollment (use Transfer)

---

## Tests

- `scripts/enrollment-smoke.mjs` — 55 cases (EN-1 … EN-55)
- `tests/e2e/enrollment-roster.spec.ts` — 4 browser cases

---

## Deviations

None.

---

## Recommended M1-T07

**Teacher + Room + recurring ClassSchedule + TeachingSession generation**
