# M1-T09 — Assessment, Test Scores & Academic Progress

**Task:** M1-T09  
**Baseline:** M1-T08 at `ccef28e`  
**Permissions:** `assessment.read`, `assessment.create`, `assessment_result.record`, `observation.read` (hardening)

---

## Existing Schema Audit (M0)

### Assessment

| Column | Notes |
|--------|-------|
| `class_id` | Class-scoped; Course via Class |
| `assessment_type_code` | Free text code (app validates enum) |
| `title`, `assessed_on`, `max_score` | Operational metadata |
| `status` | `draft`, `open`, `closed` |
| `created_by` | Audit on create |

### AssessmentResult

| Column | Notes |
|--------|-------|
| `assessment_id`, `enrollment_id` | Enrollment-scoped scores |
| `raw_score`, `max_score` | Numeric; `0 <= raw_score <= max_score` |
| `status` | `draft`, `finalized`, `corrected` |
| **UNIQUE** | `(assessment_id, enrollment_id)` |

No score columns on Student, Enrollment, Attendance, or TeachingSession.

---

## Migration

`20260914141400_m1_t09_assessments.sql`:

1. `assessment.updated_by` + audit FKs
2. `assessment_result.updated_by` + audit FKs on `recorded_by`/`updated_by`
3. `validate_assessment_result_context` trigger (class match, date eligibility, pending rejection, score range)
4. `protect_finalized_assessment_result` — blocks score change only when status stays `finalized`; corrections set `corrected`

---

## Eligibility

For assessment date D:

- Same Class as Assessment
- `start_date <= D`
- `end_date IS NULL OR end_date >= D`
- Exclude `pending`
- Terminal enrollments remain eligible when date interval matches

No result row = **No score recorded** (not zero).

---

## Permissions

| Action | Permission |
|--------|------------|
| View assessments / results / progress | `assessment.read` |
| Create / edit assessment | `assessment.create` |
| Record / correct scores | `assessment_result.record` |
| View observation content | `observation.read` |
| Record observation | `observation.record` |

Staff (seed): `assessment.read` only — no create/record.

---

## Observation Read Hardening (T08 fix)

Session execution loads observation data only when `observation.read` or `observation.record`. Roster hides observation column without read permission. No ratings/comments in props or UI for unauthorized users.

---

## Routes

- `/classes/[id]/assessments` — list + create (if permitted)
- `/classes/[id]/assessments/[assessmentId]` — edit metadata + score entry
- `/students/[id]/progress` — derived academic progress

Closed classes: new assessment creation blocked; historical view/correction allowed per permissions.

---

## Tests

- `scripts/assessment-smoke.mjs` — 65 tests (AS-1…AS-65)
- `tests/e2e/assessments.spec.ts` — 3 e2e tests

---

## Deviations

None.

---

## Recommended M1-T10

**Academic reporting foundation** — class attendance report, class assessment report, end-of-course class report, individual learner progress report (read models only; no PDF in T10 unless scoped).
