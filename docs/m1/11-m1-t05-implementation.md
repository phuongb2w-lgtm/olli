# M1-T05 — Course & Class Operations Implementation

**Task:** M1-T05  
**Baseline:** M1-T04 at `266bdce`  
**Permissions:** `enrollment.read`, `enrollment.create`, `enrollment.update` (M0 registry — no separate course/class codes)

---

## Existing Course Schema (M0)

| Column | Type | Notes |
|--------|------|-------|
| `id` | uuid | PK |
| `organization_id` | uuid | FK → organization |
| `code` | text NOT NULL | `UNIQUE (organization_id, code)` |
| `name` | text NOT NULL | Unicode-safe |
| `level_code` | text | Optional |
| `status` | text | `active`, `inactive`, `archived` (default `active`) |
| `created_at`, `updated_at` | timestamptz | Auto |
| `created_by`, `updated_by` | uuid | Audit; FK added in M1-T05 migration |

**RLS:** org-scoped; `enrollment.*` permissions.

---

## Existing Class Schema (M0 + M1-T05 migration)

| Column | Type | Notes |
|--------|------|-------|
| `id` | uuid | PK |
| `organization_id` | uuid | FK → organization |
| `course_id` | uuid | Composite FK `(organization_id, course_id)` → course |
| `name` | text NOT NULL | No separate class code column |
| `term_start_date`, `term_end_date` | date | Optional; `term_end_date >= term_start_date` |
| `capacity` | integer | Optional |
| `status` | text | **M1-T05:** `planned`, `trial`, `active`, `closed` |
| Audit columns | | Same as course |

**M0 statuses** `completed`, `cancelled` migrated to `closed`. **`trial`** added.

---

## Migration

`supabase/migrations/20260914141000_m1_t05_class_lifecycle.sql`:

1. `UPDATE class SET status = 'closed' WHERE status IN ('completed', 'cancelled')`
2. Replace `class_status_check` with M1-T05 lifecycle values
3. Add audit FK constraints on `course` and `class` (`created_by`, `updated_by` → `app_user`)

---

## Semantic Boundary

- **Course / Program:** reusable academic offering (e.g. IELTS Preparation)
- **Class:** one delivery instance/cohort of a Course
- **Enrollment** (out of scope): temporal Student ↔ Class link
- No LMS fields, no `teacher_id` on class, no schedule arrays on class

---

## Class Lifecycle

| Status | Meaning |
|--------|---------|
| `planned` | Being prepared; no enrollments required |
| `trial` | Trial/pre-confirmation operational state |
| `active` | Actively delivered |
| `closed` | Delivery ended; history preserved |

Lifecycle changes to **`active`** or **`closed`** require UI confirmation. Closing never deletes enrollments, schedules, assignments, or sessions.

---

## Routes

| Route | Purpose |
|-------|---------|
| `/classes` | Class list (search, course filter, status filter, pagination) |
| `/classes/new` | Create class |
| `/classes/[id]/edit` | Edit class + lifecycle confirmation |
| `/courses` | Course list |
| `/courses/new` | Create course |
| `/courses/[id]/edit` | Edit course |

Navigation: **Classes** enabled in app shell; **Courses** linked from class list header.

---

## Server Actions

- `src/app/actions/courses.ts` — `createCourse`, `updateCourse`
- `src/app/actions/classes.ts` — `createClass`, `updateClass`

Trusted context: `organization_id`, `created_by`, `updated_by` from `getCurrentAppUser()`. Session Supabase client only.

---

## Search / Filter / Pagination

URL params: `q`, `course`, `status`, `page`, `pageSize` (25/50/100).

Server-side resolution in `query-class-list.ts`: search matches class name or course code/name before pagination.

---

## Explicit Boundaries (not implemented)

- Enrollment CRUD / roster
- `Student.current_class_id`
- ClassSchedule CRUD
- ClassTeacherAssignment CRUD
- TeachingSession / Attendance
- Hard delete
- Finance / P&L fields

---

## Tests

- `scripts/course-class-smoke.mjs` — 45 cases (CC-1 … CC-45)
- `tests/e2e/course-class.spec.ts` — 6 browser cases

---

## Deviations

1. **Class lifecycle migration:** M0 `completed`/`cancelled` → `closed`; adds `trial`. Updates product contract vs M0 status registry doc.
2. **Permissions:** Uses existing `enrollment.*` codes per M0 RLS matrix — not separate `course.*` / `class.*`.
3. **No class code field:** Search by class name only; course filter by course ID.

---

## Recommended M1-T06

**Enrollment + Class Roster** — link students to classes, enrollment lifecycle, roster read model.
