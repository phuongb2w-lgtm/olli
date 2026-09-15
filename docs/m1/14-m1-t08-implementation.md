# M1-T08 — Attendance, Session Execution & Learner Observation

**Task:** M1-T08  
**Baseline:** M1-T07 at `fdfc9f3`  
**Permissions:** `attendance.read` / `attendance.record`, `observation.read` / `observation.record`, `enrollment.update` (session lifecycle)

---

## Existing Schema Audit (M0)

### Attendance

| Column | Notes |
|--------|-------|
| `teaching_session_id`, `enrollment_id` | Composite org FKs |
| `status` | `present`, `absent`, `late`, `excused` |
| `recorded_by`, `recorded_at` | Audit on create |
| **UNIQUE** | `(teaching_session_id, enrollment_id)` |

Triggers: `validate_attendance_context` (class/org match), M1-T08 `validate_attendance_enrollment_eligibility` (date + no pending).

### Observations

| Table | Role |
|-------|------|
| `observation_indicator` | Global reference (`concentration`, `engagement`, `participation`) |
| `teacher_observation` | Enrollment + optional `teaching_session_id`, comment, status |
| `observation_rating` | One rating per indicator per observation |

M1-T08 adds unique `(organization_id, enrollment_id, teaching_session_id)` on `teacher_observation` where session linked and not void.

---

## Migration

`20260914141300_m1_t08_attendance_observations.sql`:

1. `attendance.updated_by` + audit FKs
2. `teacher_observation` audit FKs + session/enrollment uniqueness
3. Enrollment date eligibility trigger on attendance
4. Observation class/org context trigger

No new attendance status codes. No roster denormalization.

---

## Session Roster Derivation

For session occurrence date D:

- Same `class_id`
- `start_date <= D`
- `end_date IS NULL OR end_date >= D`
- Exclude `pending` from roster visibility
- Terminal statuses (transferred/withdrawn/completed) remain visible when date interval matches

Operational attendance marking: `active` enrollment only.

Missing row = **Not recorded** (UI only, not a DB status).

---

## Session Execution Workflow

| Transition | Allowed |
|------------|---------|
| `scheduled` → `in_progress` | Start session |
| `in_progress` → `completed` | Complete (confirm if unrecorded) |
| `scheduled`/`in_progress` → `cancelled` | Cancel |

No auto-attendance on start/complete/cancel. No enrollment/student mutation.

---

## Permissions

| Action | Permission |
|--------|------------|
| View roster / session | `attendance.read` or `enrollment.read` |
| Record attendance | `attendance.record` |
| Record observation | `observation.record` |
| Session start/complete/cancel | `enrollment.update` |

Staff (seed): read-only for attendance/observation. Admin: full record access.

Teacher authorization is organization-wide per existing permission model (documented limitation).

---

## Room / Location Precedence

1. `room_id` → Room master name  
2. Legacy `class_schedule.location` when no room

---

## Teacher Resolution (T07 regression)

`generate_teaching_sessions` resolves primary teacher per **occurrence date** effective range. Ambiguous primary remains blocked.

Session execution displays session's explicit `teacher_id` (historical).

---

## Routes

- `/classes/[id]/teaching` — session list with **Open session** link
- `/classes/[id]/teaching/sessions/[sessionId]` — execution UI

---

## Tests

- `scripts/session-execution-smoke.mjs` — 71 tests (SE-1…SE-71)
- `tests/e2e/session-execution.spec.ts` — 3 e2e tests

---

## Deviations

None.

---

## Recommended M1-T09

**Assessment & Test Score model + academic progress read models** — normalized `assessment` / `assessment_result` workflow; no scores in attendance/observation.
