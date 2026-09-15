# M1-T10 — Academic Reporting Foundation

**Task:** M1-T10  
**Baseline:** M1-T09 at `4ed11f6`  
**Migration:** None (read models only)

---

## Architecture

Reports are **live read models** assembled server-side in `src/lib/reports/`. They do not persist derived facts on operational tables.

| Report | Builder | Route |
|--------|---------|-------|
| Class attendance | `build-class-attendance-report.ts` | `/classes/[id]/reports/attendance` |
| Class assessment | `build-class-assessment-report.ts` | `/classes/[id]/reports/assessments` |
| End-of-course class | `build-class-end-of-course-report.ts` | `/classes/[id]/reports/end-of-course` |
| Learner progress | `build-student-progress-report.ts` | `/students/[id]/reports/progress` |

Hub: `/classes/[id]/reports`

Legacy redirect: `/students/[id]/progress` → `/students/[id]/reports/progress`

---

## Source-of-truth mapping

| Report section | Source tables |
|----------------|---------------|
| Attendance | `teaching_session`, `enrollment`, `attendance` |
| Assessments | `assessment`, `assessment_result`, `enrollment` |
| Observations | `teacher_observation`, `observation_rating` |
| Branding header | `organization.name` only (no logo field in schema) |
| Class context | `class`, `course` |

---

## Attendance formulas

**Session inclusion (denominator opportunity):**

- Included: `completed`, `in_progress`
- Excluded: `cancelled`, `scheduled` (future/planned)

**Enrollment eligibility:** date interval per `roster-eligibility.ts`; `pending` excluded from learner rows.

**Status buckets:** missing attendance row → `notRecorded` (not absent).

**Attendance rate:**

```
(present + late) / (present + absent + late + excused)
```

Returns `null` when no recorded eligible sessions exist.

---

## Assessment aggregates

- Missing `assessment_result` → no-score (not zero)
- Mean/min/max percentages use recorded results only
- Per-assessment enrollment eligibility matches T09 assessment date rules

---

## Enrollment historical handling

Individual reports anchor on **Enrollment** when scoped. Re-enrollment and transfer produce separate enrollment periods; results and attendance are not merged across enrollments.

---

## Observation permission composition

- `observation.read` required to fetch/include observation payload
- Without permission: observations omitted from query, UI, and print (not CSS-hidden)
- Attendance/assessment sections remain available when observation access is missing

---

## Locale & branding

- VI/EN via `next-intl` `reports` namespace
- Report locale follows application locale (no duplicate report implementations)
- Organization name from authenticated org row; no hard-coded center name

---

## Print behavior

- `ReportPrintButton` triggers browser print
- `.report-no-print` hides navigation/forms in `@media print` (`globals.css`)
- No PDF library added

---

## Performance

Batched queries in `fetch-report-data.ts`: enrollments, sessions, attendance, assessments/results, and observations fetched in bounded queries (no per-learner N+1).

---

## Permissions

Composed from existing codes:

| Report | Permission |
|--------|------------|
| Attendance | `attendance.read` |
| Assessment | `assessment.read` |
| Observations | `observation.read` |
| Class hub / context | `enrollment.read` and/or section permissions |
| Student progress | `student.read` / `enrollment.read` + section permissions |

No new `report.read` usage in T10 UI (code exists in M0 reference data but is not required here).

---

## Tests

- Smoke: `scripts/reports-smoke.mjs` — RP-1…RP-68 (68 tests)
- E2E: `tests/e2e/reports.spec.ts` — 3 tests

---

## Deviations

None.
