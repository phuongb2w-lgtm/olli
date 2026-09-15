# M1-T07 — Teaching Operations Foundation

**Task:** M1-T07  
**Baseline:** M1-T06 at `92af2d4`  
**Permissions:** `enrollment.read/create/update` for schedule, assignment, session, room; `teacher.read` for teacher master lookups

---

## Existing Schema Audit (M0)

### Teacher identity

M0 defines a dedicated `teacher` table (not `app_user`-only):

| Column | Notes |
|--------|-------|
| `organization_id` | Org scope |
| `user_id` | Optional link to `app_user` |
| `given_name`, `family_name` | Display identity |
| `status` | `active`, `inactive`, `on_leave`, `terminated` |

Teacher eligibility for assignment: active `teacher` row in the same organization.

### ClassTeacherAssignment

| Column | Notes |
|--------|-------|
| `class_id`, `teacher_id` | Composite org FKs |
| `role_code` | `primary`, `assistant` |
| `effective_from`, `effective_to` | Date range |
| `status` | `active`, `ended` |

History preserved via `status = ended` and effective dates — no hard delete.

### ClassSchedule (M0 + M1-T07)

M0: one weekly slot per row — `weekday_code` (`mon`–`sun`), `start_time`, `end_time`, `effective_from/to`, `location` (text), `status` (`active`/`ended`).

M1-T07 adds: `room_id`, `teacher_id` (optional explicit schedule teacher), `created_by`, `updated_by`.

### TeachingSession (M0 + M1-T07)

| Column | Notes |
|--------|-------|
| `class_schedule_id` | Source schedule (nullable for manual) |
| `teacher_id` | Required — materialized at generation |
| `scheduled_start_at`, `scheduled_end_at` | `timestamptz` |
| `status` | M0: `scheduled`, `in_progress`, `completed`, `cancelled` |
| `occurrence_date` | **M1-T07** — local occurrence date for idempotency |
| `room_id` | **M1-T07** — snapshot from schedule at generation |

UI maps `scheduled` → “Planned” / “Dự kiến” (no status migration).

### Room (M1-T07 — new)

Minimal master: `organization_id`, `name`, optional `code`, optional `capacity`, `status` (`active`/`inactive`), audit columns.

RLS uses `enrollment.*` (academic infrastructure — same family as course/class/schedule).

---

## Migration

`20260914141200_m1_t07_teaching_operations.sql`:

1. **`room`** table + RLS
2. **`class_schedule`**: `room_id`, `teacher_id`, audit FKs
3. **`class_teacher_assignment`**: audit FKs
4. **`teaching_session`**: `room_id`, `occurrence_date`
5. **Idempotency**: partial unique index `(organization_id, class_schedule_id, occurrence_date)`
6. **Conflicts**: EXCLUDE on room and teacher overlapping `scheduled/in_progress/completed` sessions
7. **`generate_teaching_sessions()`** RPC — SECURITY INVOKER, max 366-day range

---

## Teacher Assignment Semantics

- Multiple assignments per class allowed (primary/assistant, overlapping date ranges)
- End assignment → `status = ended`, sets `effective_to` — row retained
- No `class.teacher_id` shortcut

Session generation teacher resolution (per occurrence date):

1. If `class_schedule.teacher_id` set → use it
2. Else exactly one active `primary` assignment covering the date → use it
3. Else error `ambiguous_teacher` — does not pick arbitrarily

---

## ClassSchedule Validation

Server-side: valid weekday, `end_time > start_time`, effective dates, closed class rejects new active schedules, org consistency on class/teacher/room FKs.

---

## TeachingSession Generation

Bounded by intersection of:

- Requested `[range_start, range_end]` (max 366 days)
- Schedule `effective_from/to`
- Class `term_start_date/term_end_date`

Uses `organization.timezone` (default `Asia/Ho_Chi_Minh`) to convert `(occurrence_date + local time)` → `timestamptz`:

```sql
(occurrence_date + start_time) AT TIME ZONE org_timezone
```

Idempotent via unique index + `ON CONFLICT DO NOTHING`.

---

## Historical Truth

- Editing `class_schedule` times/dates does **not** update existing `teaching_session` rows
- Ending a schedule does **not** delete materialized sessions
- Session cancel/complete preserves row; no enrollment or attendance side effects

---

## Conflict Handling

| Type | Enforcement |
|------|-------------|
| Room double-book | DB EXCLUDE on `teaching_session` (planned/completed/in_progress) |
| Teacher double-book | DB EXCLUDE on `teaching_session` |
| Cancelled session | Excluded from overlap constraint |
| Recurring schedule future conflicts | Not enforced at schedule layer (deferred) |
| Multi-teacher class | Not treated as occupying every slot unless explicit on schedule/session |

---

## Routes / UI

| Route | Purpose |
|-------|---------|
| `/classes/[id]/teaching` | Teachers, recurring schedule, sessions |
| `/rooms`, `/rooms/new`, `/rooms/[id]/edit` | Room master |

Class list links: Roster + Teaching (when `enrollment.read`).

---

## Tests

- `scripts/teaching-smoke.mjs` — 60 tests (TE-1…TE-60)
- `tests/e2e/teaching-operations.spec.ts` — 4 e2e tests

---

## Deviations

- Session status codes remain M0 (`scheduled` not `planned`); UI labels only
- `class_schedule.location` text retained; `room_id` preferred for new data
- Teacher conflict at recurring schedule creation not enforced (session-level only)

---

## Recommended M1-T08

**Attendance + TeachingSession execution + learner observation layer** — connect `Enrollment` + `TeachingSession` → `Attendance`; teacher observations; no finance in T08 unless scoped separately.
