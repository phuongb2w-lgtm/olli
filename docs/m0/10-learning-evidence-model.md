# M0-T02 — Learning Evidence Model

**Date:** 2026-09-14

Learning evidence in Olli is **management evidence** entered by teachers/staff. It is not LMS functionality — no exam delivery, no automated grading, no student interaction.

---

## Scope Boundary

| In scope | Out of scope |
|----------|--------------|
| Teacher enters test score after offline test | Online exam delivery |
| Teacher records concentration/engagement | Student self-assessment UI |
| Teacher writes progress evaluation | Automated grading engine |
| Assessment event metadata (date, max score) | Question banks |

---

## Entity Overview

```
Class
  └── Assessment (event)
         └── AssessmentResult (per student/enrollment)

Enrollment
  ├── TeacherObservation (header)
  │      └── ObservationRating (indicator rows)
  └── ProgressEvaluation (periodic summary)
```

All evidence anchors to **Enrollment** for historical class context.

---

## Assessment

**Purpose:** Define a management evaluation event — e.g. "Unit 3 vocabulary test, max 20 points, 2026-03-15".

| Field | Type | Notes |
|-------|------|-------|
| id | UUID | PK |
| organization_id | UUID | |
| class_id | UUID | FK → Class |
| assessment_type_code | code | e.g. `quiz`, `midterm`, `speaking`, `writing` |
| title | text | Internal title; display may use i18n template |
| max_score | decimal | Fixed at creation |
| assessed_on | date | Event date |
| status | code | `draft`, `open`, `closed` |
| created_by | UUID | FK → User |

**Not modelled:** question content, rubric engine, template library (deferred indefinitely).

---

## AssessmentResult

**Purpose:** One student's outcome on an assessment.

| Field | Type | Notes |
|-------|------|-------|
| id | UUID | PK |
| assessment_id | UUID | FK → Assessment |
| enrollment_id | UUID | FK → Enrollment — **historical context** |
| student_id | UUID | FK → Student (denormalized convenience) |
| raw_score | decimal | Entered by teacher |
| max_score | decimal | Copied from Assessment at entry time |
| normalized_score | — | **DERIVED:** raw_score / max_score — do not store |
| status | code | `draft`, `finalized`, `corrected` |
| recorded_by | UUID | FK → User or Teacher |
| finalized_at | timestamp | Set when finalized |

**Immutability:** When `status = finalized`, raw_score is immutable. Corrections:
- Set status → `corrected`
- Create correction record OR new result version (M0-T03 detail; prefer explicit correction row linked to original)

**Scenario 6 support:** Teacher enters score for offline test — Assessment + AssessmentResult only; no exam entity.

---

## TeacherObservation

**Purpose:** Qualitative evidence about a student at a point in time.

### Design choice: Header + ObservationRating

Evaluated options:

| Option | Verdict |
|--------|---------|
| Fixed columns (`concentration`, `engagement`) only | Too rigid long-term |
| Generic EAV (entity-attribute-value) | Over-engineered; harms query clarity |
| **Header + ObservationRating rows** | **Accepted** — extensible, structured, simple |

### TeacherObservation (header)

| Field | Type | Notes |
|-------|------|-------|
| id | UUID | PK |
| organization_id | UUID | |
| enrollment_id | UUID | FK → Enrollment |
| student_id | UUID | FK → Student |
| class_id | UUID | FK → Class |
| teacher_id | UUID | FK → Teacher (author) |
| teaching_session_id | UUID | Nullable — link to specific session if applicable |
| observed_at | timestamp | When observation was made |
| comment | text | Free-text teacher comment |
| status | code | `draft`, `recorded`, `void` |

### ObservationRating (indicator rows)

| Field | Type | Notes |
|-------|------|-------|
| id | UUID | PK |
| teacher_observation_id | UUID | FK → TeacherObservation |
| indicator_code | code | `concentration`, `engagement`, `participation`, … |
| rating_code | code | Scale: `low`, `medium`, `high` OR numeric scale codes |

**Uniqueness:** `UNIQUE(teacher_observation_id, indicator_code)`

**Scenario 7 support:** One observation with two ratings:
- `{ indicator: concentration, rating: low }`
- `{ indicator: engagement, rating: high }`
- Plus optional comment on header

**i18n:** Indicator and rating **codes** stored; Vietnamese/English labels in i18n catalog.

**Extensibility:** New indicators added by defining new `indicator_code` values in configuration — no schema change required.

---

## ProgressEvaluation

**Purpose:** Periodic summary judgment — "Student improved over March" — distinct from point-in-time observation.

| Field | Type | Notes |
|-------|------|-------|
| id | UUID | PK |
| organization_id | UUID | |
| enrollment_id | UUID | FK → Enrollment |
| student_id | UUID | FK → Student |
| class_id | UUID | FK → Class |
| teacher_id | UUID | FK → Teacher (evaluator) |
| evaluation_period_start | date | Period covered |
| evaluation_period_end | date | |
| evaluated_at | timestamp | When evaluation recorded |
| progress_level_code | code | e.g. `below_expectation`, `on_track`, `above_expectation` |
| improvement_code | code | e.g. `declined`, `stable`, `improved`, `significantly_improved` |
| summary_comment | text | Narrative evaluation |
| status | code | `draft`, `finalized` |

**Scenario 8 support:** March observation (low concentration) remains unchanged. April ProgressEvaluation records `improvement_code = improved`. Separate records — no overwrite.

**Not on Student:** No `progress_score` or `current_level` mutable field on Student master.

---

## Connection to Business Performance

Learning evidence connects to business performance through shared keys:

| Evidence | Business link |
|----------|---------------|
| AssessmentResult | enrollment_id → Charge (tuition paid for that class) |
| Attendance | session → class → enrollment → revenue |
| ProgressEvaluation | retention indicator alongside enrollment lifecycle |
| TeacherObservation | teacher_id → Expense (direct cost) via attribution |

Reports join evidence and finance on `enrollment_id`, `class_id`, `student_id`, `teacher_id` — not separate silos.

---

## Status Code Reference (Domain — Not Labels)

| Entity | Codes |
|--------|-------|
| Assessment | `draft`, `open`, `closed` |
| AssessmentResult | `draft`, `finalized`, `corrected` |
| TeacherObservation | `draft`, `recorded`, `void` |
| ProgressEvaluation | `draft`, `finalized` |
| Attendance | `present`, `absent`, `late`, `excused` |

All display labels resolved via i18n: `status.attendance.present` → vi: "Có mặt", en: "Present".

---

## Deferred (Not in M0 Learning Model)

- Assessment templates / reusable rubrics
- File attachments (scan of test paper)
- Guardian-visible progress portal
- Automated progress scoring algorithms
- LMS content linkage
