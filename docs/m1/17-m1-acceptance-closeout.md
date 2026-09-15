# M1-T11 — Academic Operations Acceptance & Closeout

**Task:** M1-T11  
**Baseline:** M1-T10 at `8ed07f0`  
**Result:** **PASS — M1 CLOSED**

---

## 1. Milestone scope

M1 delivers the complete academic operations vertical slice:

| Domain | Tasks | Status |
|--------|-------|--------|
| Design & readiness | T01 | CLOSED |
| Student list | T02 | CLOSED |
| Student CRUD | T03 | CLOSED |
| Guardian relationships | T04 | CLOSED |
| Course/Class | T05 | CLOSED |
| Enrollment/roster/transfer | T06 | CLOSED |
| Teaching operations | T07 | CLOSED |
| Session execution (attendance/observation) | T08 | CLOSED |
| Assessments & progress | T09 | CLOSED |
| Academic reporting | T10 | CLOSED |
| Acceptance & closeout | T11 | CLOSED |

Out of scope for M1: finance, parent portal, PDF/export, report snapshots, marketing/BI dashboards.

---

## 2. Final architecture

Reports and progress views are **live read models** assembled in `src/lib/reports/` and server pages. Operational tables remain the single source of truth. No derived academic facts are persisted on Student, Class, or Enrollment.

Security model: Supabase RLS + `has_permission()` checks in policies; Server Actions revalidate permissions and org context; two M1 business RPCs are SECURITY INVOKER with explicit permission gates.

---

## 3. Domain map

```text
Organization
 ├─ Student
 │   ├─ StudentGuardian ─ Guardian
 │   └─ Enrollment
 │        ├─ Class ─ Course
 │        │   ├─ ClassTeacherAssignment ─ Teacher
 │        │   ├─ ClassSchedule ─ Room (optional)
 │        │   │    └─ TeachingSession (materialized)
 │        │   └─ Assessment
 │        ├─ Attendance ─ TeachingSession
 │        ├─ TeacherObservation ─ TeachingSession
 │        │    └─ ObservationRating (reference indicators)
 │        └─ AssessmentResult ─ Assessment
 └─ AppUser / Roles / Permissions
```

Reports read across Enrollment-scoped facts without storing aggregates.

---

## 4. Permissions matrix

Exact codes from `20260914140100_reference_data.sql` (34 total).

| Domain | Read | Create/Record | Update |
|--------|------|---------------|--------|
| Student | `student.read` | `student.create` | `student.update` |
| Guardian | `guardian.read` | `guardian.create` | `guardian.update` |
| Course/Class/Room/Schedule/Session | `enrollment.read` | `enrollment.create` | `enrollment.update` |
| Enrollment | `enrollment.read` | `enrollment.create` | `enrollment.update` |
| Teacher (RLS) | `teacher.read` | `teacher.create` | `teacher.update` |
| Attendance | `attendance.read` | `attendance.record` | `attendance.record` |
| Observation | `observation.read` | `observation.record` | `observation.record` |
| Assessment | `assessment.read` | `assessment.create` | `assessment.create` |
| Assessment scores | `assessment.read` | `assessment_result.record` | `assessment_result.record` |
| Reporting composition | Section permissions above | — | — |

**Intentional reuse (technical debt, accepted V1):** Course, Class, Room, ClassSchedule, ClassTeacherAssignment, and TeachingSession RLS uses `enrollment.*` rather than dedicated academic-ops codes. Documented; no security bug identified.

**Unused in M1 app:** `report.read` (T10 composes section permissions), `teacher.*` UI (teachers via seed/DB), `progress_evaluation.record`, all finance codes.

---

## 5. Lifecycle matrix

| Entity | Values | Enforcement |
|--------|--------|-------------|
| Student | `prospect`, `active`, `inactive`, `graduated`, `withdrawn` | CHECK constraint + app validation |
| Guardian | `active`, `inactive` | CHECK constraint |
| StudentGuardian | `active`, `ended` | CHECK constraint; unlink sets `ended` |
| Course | `active`, `inactive`, `archived` | CHECK constraint |
| Class | `planned`, `trial`, `active`, `closed` | CHECK constraint (M1-T05 migration) |
| Enrollment | `pending`, `active`, `transferred`, `withdrawn`, `completed` | CHECK + overlap exclusion for operational statuses |
| TeachingSession | `scheduled`, `in_progress`, `completed`, `cancelled` | CHECK constraint |
| Assessment | `draft`, `open`, `closed` | CHECK constraint |
| AssessmentResult | `draft`, `finalized`, `corrected` | CHECK + trigger on finalized immutability |

Terminal enrollment transitions (`transferred`, `withdrawn`, `completed`) are enforced in Server Actions and `transfer_enrollment` RPC.

---

## 6. Integrity constraints

| Constraint | Mechanism |
|------------|-----------|
| Normalized student code uniqueness | Partial unique index on `(organization_id, lower(btrim(student_code)))` |
| One active primary contact | Partial unique on `(organization_id, student_id)` where primary + active |
| Enrollment overlap | GiST exclusion on `(org, student, class)` date ranges for pending/active |
| Org-safe composite FKs | `(organization_id, id)` parent uniqueness pattern across M1 tables |
| Session idempotent generation | Partial unique on `(org, class_schedule_id, occurrence_date)` |
| Room/teacher time conflicts | GiST exclusion on overlapping sessions |
| Attendance uniqueness | UNIQUE `(teaching_session_id, enrollment_id)` |
| Assessment result uniqueness | UNIQUE `(assessment_id, enrollment_id)` |
| Observation uniqueness | Partial unique per session × enrollment (non-void) |
| Context triggers | Attendance, observation, assessment_result validate enrollment/class/org alignment and date eligibility |

---

## 7. RPC inventory

| RPC | Security | Purpose |
|-----|----------|---------|
| `has_permission(p_code)` | DEFINER | Permission check for RLS and app |
| `current_app_user_id()` | DEFINER | Resolve active app user |
| `current_organization_id()` | DEFINER | Resolve org from auth |
| `is_active_app_user()` | DEFINER | Active user gate |
| `set_own_preferred_locale(p_locale)` | DEFINER | Locale persistence (M0) |
| `transfer_enrollment(...)` | **INVOKER** | Atomic enrollment transfer; requires `enrollment.update` |
| `generate_teaching_sessions(...)` | **INVOKER** | Idempotent session generation; requires `enrollment.create` |

No M1 RPC uses privileged bypass of tenant RLS. Trigger functions are INVOKER except `protect_app_user_sensitive_fields` (DEFINER, IAM-only).

---

## 8. Historical-truth guarantees

| Scenario | Guarantee | Verification |
|----------|-----------|--------------|
| Transfer | Source enrollment → `transferred` with `end_date`; destination new row; source `class_id` unchanged | EN-37–39, AC-18–19, RP-10–11 |
| Re-enrollment | New enrollment row; prior terminal history preserved | EN-28–31 |
| Teacher reassignment | Completed session `teacher_id` protected by trigger | SE-46–47, TE-33 |
| Schedule edit | Existing sessions not rewritten | TE-22–23 |
| Room/location | Session stores materialized `room_id`; schedule location fallback at generation | SE-50–51 |
| Class close | History readable (sessions, attendance, assessments, reports) | AS-34, RP-24 |

---

## 9. Reporting formulas (reconfirmed)

**Attendance rate:** `(present + late) / (present + absent + late + excused)` — not-recorded excluded from denominator.

**Assessment aggregates:** Mean/min/max from recorded percentages only; missing result ≠ zero.

**Observations:** Included only with `observation.read`; categorical frequency only, no invented numeric KPIs.

---

## 10. Security / tenant model

- All M1 tables: RLS enabled with `organization_id = current_organization_id()` predicate.
- Client cannot set `organization_id` or audit actor columns through normal app paths.
- Guardian data gated by `guardian.read`; observations by `observation.read`; assessment by `assessment.read`.
- Report sections omitted from server payload when permission absent (not CSS-only hiding).
- No finance mutations from M1 academic Server Actions (verified by grep + RP-64 / AC scenario).

---

## 11. Timezone behavior

- Organization default: `Asia/Ho_Chi_Minh` (`organization.timezone`).
- Session generation uses org timezone via `generate_teaching_sessions` (not browser timezone).
- Reports use `TeachingSession.occurrence_date` / `scheduled_start_at` as stored truth.
- UI display via `Intl.DateTimeFormat` with app locale.

---

## 12. Teacher / room resolution

1. `class_schedule.teacher_id` when set on schedule used at generation.
2. Else primary `class_teacher_assignment` valid on occurrence date (unambiguous).
3. Room: `teaching_session.room_id` authoritative; `class_schedule.location` legacy fallback when no room.

Completed sessions: `teacher_id` changes blocked by trigger.

---

## 13. T11 closeout fixes

| Fix | Reason |
|-----|--------|
| Batch assessment scored-count query | N+1 in `fetchClassAssessments` |
| Batch class assessment fetches in progress report | N+1 in all-history enrollment path |
| Remove dead `student-progress-list` / `query-student-progress` | Superseded by T10 reports route |
| Fix `revalidatePath` to reports progress route | Stale cache path |
| Lint: 6 → 0 warnings | Smoke unused vars; `_locale` param |
| Add `m1-acceptance-scenario.mjs` | AC-1…AC-19 vertical slice |

**Not changed (documented as debt):** Class sub-page cross-navigation; Vietnamese accent-insensitive search; `enrollment.*` permission reuse for academic ops.

---

## 14. Final test accounting

### DB / API / Node

| Suite | Count |
|-------|------:|
| M0 DB (integrity + security + charge_balance + locale) | 66 |
| API security | 6 |
| Student list | 20 |
| Student mutations | 30 |
| Guardian relationships | 44 |
| Course/class | 45 |
| Enrollment | 55 |
| Teaching | 60 |
| Session execution | 71 |
| Assessments | 65 |
| Reporting | 68 |
| **M1 acceptance scenario (new)** | **19** |
| **Subtotal** | **549** |

### E2E

| Suite | Count |
|-------|------:|
| app-smoke | 8 |
| assessments | 3 |
| course-class | 5 |
| enrollment-roster | 4 |
| guardian-relationships | 4 |
| reports | 3 |
| session-execution | 3 |
| student-list | 9 |
| student-mutations | 5 |
| teaching-operations | 4 |
| **Subtotal** | **51** |

### Executable total: **549 + 51 = 600 PASS**

Baseline was 581; **+19** from M1 acceptance scenario (T11 requirement §28).

### Static / build

| Check | Result |
|-------|--------|
| i18n parity | PASS |
| env audit | PASS |
| lint | 0 errors, 0 warnings (target met) |
| typecheck | PASS |
| production build | PASS |
| fresh DB reset + verify | PASS (T11 §27) |

---

## 15. Known limitations (post-M1)

| Item | Classification |
|------|----------------|
| Vietnamese accent-insensitive search imperfect | Accepted V1 limitation |
| Course/Class uses `enrollment.*` permissions | Accepted V1 limitation (technical debt) |
| Organization-wide teacher scope (no class-scoped teacher role) | Future milestone |
| Legacy `class_schedule.location` fallback | Accepted V1 limitation |
| Recurring conflicts detected at materialized session level | Accepted V1 limitation |
| Live reports not frozen snapshots | Accepted V1 limitation |
| No parent portal / export / PDF | Future milestone |
| No finance coupling in M1 | Intentional boundary for M2 |
| Class sub-pages lack cross-links (must return to list) | Usability improvement |

No unresolved security or data-integrity concerns accepted.

---

## 16. Deferred scope (M2+)

- M2 Finance/Cost Foundation (Charge, Payment, expense, revenue recognition)
- Report export/finalization and parent communication
- Accent-insensitive Vietnamese search platform
- Dedicated academic-ops permission codes (optional refactor)
- Global reports navigation module

---

## 17. Final acceptance result

**PASS — M1 CLOSED**

All architecture invariants verified. Migration-from-zero succeeds. Full verify PASS at 600 executable tests. Repository clean after closeout commit.
