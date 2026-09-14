# M0-T02 — Domain Validation Scenarios

**Date:** 2026-09-14

Validation of the canonical domain model against 14 required scenarios. Each scenario references the entities and rules that make it pass.

---

## Summary

| # | Scenario | Result |
|---|----------|--------|
| 1 | One guardian, two children | **PASS** |
| 2 | One student, mother and father guardians | **PASS** |
| 3 | Student transfers Class A → B | **PASS** |
| 4 | Teacher A replaced by Teacher B | **PASS** |
| 5 | Student misses one session | **PASS** |
| 6 | Teacher enters offline test score | **PASS** |
| 7 | Low concentration, good participation | **PASS** |
| 8 | Later progress evaluation — earlier not overwritten | **PASS** |
| 9 | Tuition price change — old charges unchanged | **PASS** |
| 10 | Half payment now, half later | **PASS** |
| 11 | One payment covers several charges | **PASS** |
| 12 | Discount after charge created | **PASS** |
| 13 | ExpenseCategory renamed — history intact | **PASS** |
| 14 | Inactive teacher/student — history intact | **PASS** |

**Overall: 14/14 PASS**

---

## Scenario Details

### Scenario 1 — One guardian has two children

**Setup:** Guardian G1 linked to Student S1 and Student S2 via StudentGuardian.

**Model support:**
- StudentGuardian N:M between Guardian and Student
- Each student has independent Enrollment, Charge, Attendance

**Validation:** G1 can be `is_billing_contact` on both relationships. Payments from G1 allocate to charges for either child.

**Result: PASS**

---

### Scenario 2 — One student has mother and father as guardians

**Setup:** Student S1 with Guardian G-mother and Guardian G-father.

**Model support:**
- Two StudentGuardian rows: `{ relationship_type: mother }`, `{ relationship_type: father }`
- `is_primary_contact` and `is_billing_contact` flags designate roles

**Validation:** Both guardians linked without duplicating guardian data on Student row.

**Result: PASS**

---

### Scenario 3 — Student transfers Class A to Class B

**Setup:** S1 enrolled in Class A from Jan–Feb, transfers to Class B in March.

**Model support:**
1. Close Enrollment-A: `status=transferred`, `end_date=2026-02-28`
2. Create Enrollment-B: `status=active`, `start_date=2026-03-01`
3. Attendance during Jan–Feb retains `enrollment_id` → Enrollment-A
4. No `current_class_id` on Student

**Validation:** Historical attendance in Class A remains tied to Enrollment-A. Class B attendance uses Enrollment-B.

**Result: PASS**

---

### Scenario 4 — Teacher A for two months, then Teacher B

**Setup:** Class C1 taught by T1 Jan–Feb, T2 from March.

**Model support:**
1. ClassTeacherAssignment: T1 `effective_to=2026-02-28`; T2 `effective_from=2026-03-01`
2. TeachingSession rows store `teacher_id` at session time
3. Sessions in Jan–Feb have `teacher_id=T1`; March+ have `teacher_id=T2`

**Validation:** Reassignment of ClassTeacherAssignment does not UPDATE past TeachingSession.teacher_id.

**Result: PASS**

---

### Scenario 5 — Student misses one session

**Setup:** S1 absent from session on 2026-02-10.

**Model support:**
- Attendance row: `{ teaching_session_id, enrollment_id, status: absent }`
- Attendance rate = derived: count(present) / count(sessions in enrollment period)

**Validation:** No counter on Student. Reporting query joins Attendance + TeachingSession + Enrollment.

**Result: PASS**

---

### Scenario 6 — Teacher enters test score (no online exam)

**Setup:** Teacher records midterm score 16/20 for offline test.

**Model support:**
- Assessment: `{ class_id, max_score: 20, assessed_on, assessment_type_code: midterm }`
- AssessmentResult: `{ raw_score: 16, max_score: 20, status: finalized }`
- No exam delivery, question bank, or LMS entities

**Validation:** Assessment is management evidence only.

**Result: PASS**

---

### Scenario 7 — Low concentration, good participation

**Setup:** Teacher observes low concentration and high engagement in same session.

**Model support:**
- TeacherObservation header with `observed_at`, optional `comment`
- ObservationRating: `{ indicator: concentration, rating: low }`
- ObservationRating: `{ indicator: engagement, rating: high }`

**Validation:** Structured extensible design without EAV. Observation is append-only historical record.

**Result: PASS**

---

### Scenario 8 — Later evaluation: student improved; earlier not overwritten

**Setup:** March observation (low concentration). April progress evaluation (improved).

**Model support:**
- March: TeacherObservation + ObservationRating (unchanged)
- April: new ProgressEvaluation `{ improvement_code: improved, evaluation_period: April }`

**Validation:** Separate entities, separate rows. No update to March observation. No progress field on Student.

**Result: PASS**

---

### Scenario 9 — Tuition price changes next month

**Setup:** TuitionPlan P1 amount=100 effective Jan–Feb. P2 amount=120 effective Mar+.

**Model support:**
- Charges in Jan–Feb created with `amount=100` copied from P1
- March charge created with `amount=120` copied from P2
- Charge.amount immutable; TuitionPlan edits don't cascade

**Validation:** Historical charges remain 100. No recalculation.

**Result: PASS**

---

### Scenario 10 — Half payment now, half later

**Setup:** Charge C1 amount=200. Payment P1=100, later P2=100.

**Model support:**
- PaymentAllocation: P1 → C1 amount=100 → charge status `partially_paid`
- PaymentAllocation: P2 → C1 amount=100 → charge status `paid`
- Balance derived: 200 − 100 − 100 = 0

**Validation:** Two payments, two allocations, one charge. No duplicate debt entity.

**Result: PASS**

---

### Scenario 11 — One payment pays several charges

**Setup:** Payment P1=300 pays C1=100, C2=100, C3=100.

**Model support:**
- Three PaymentAllocation rows from one Payment
- Each charge transitions to `paid` independently

**Validation:** N:M Payment↔Charge via PaymentAllocation.

**Result: PASS**

---

### Scenario 12 — Discount after charge created

**Setup:** Charge C1 amount=200 posted. Discount 20 granted later.

**Model support:**
- FinancialAdjustment: `{ charge_id: C1, adjustment_type: discount, amount: -20 }`
- Charge.amount remains 200
- Balance = 200 − 20 − allocations = 180 (before payment)

**Validation:** Original charge history explainable. Adjustment is separate immutable row.

**Result: PASS**

---

### Scenario 13 — ExpenseCategory renamed/reorganized

**Setup:** Category "Office supplies" renamed. Expense E1 posted before rename.

**Model support:**
- Expense stores `expense_category_id` (FK) + `cost_group_id` (snapshot at post)
- Rename changes category display name only
- Historical report by cost_group_id snapshot unchanged

**Validation:** Financial meaning preserved via snapshot. Category FK still resolves for detail drill-down.

**Result: PASS**

---

### Scenario 14 — Teacher or student becomes inactive

**Setup:** Teacher T1 status→inactive. Student S1 status→inactive.

**Model support:**
- Soft archive: `status=inactive`, no hard delete
- TeachingSession, Attendance, Payment, AssessmentResult retain FKs
- Reports include inactive entities in historical context; filter in UI for active-only views

**Validation:** Referential integrity preserved. Historical sessions and payments intact.

**Result: PASS**

---

## Validation Notes

- All scenarios validated against **logical model** — no physical schema or application code yet.
- Scenario 13 assumes category **reparenting between CostGroups is prohibited** by business rule. If reparenting were allowed, `cost_group_id` snapshot on Expense is mandatory (already in model).
- Scenario 3 transfer workflow is modelled as close + new enrollment; no transfer workflow entity (per task: do not overbuild).

---

## Completion Gate Checklist

| Gate | Status |
|------|--------|
| Git repository valid | ✅ (reinitialized) |
| M0-T01 baseline preserved | ✅ (commit `294e6d3`) |
| Canonical entity responsibilities explicit | ✅ |
| Duplicate sources of truth eliminated | ✅ (Receivable/InvoiceLine removed) |
| Enrollment preserves class history | ✅ |
| TeachingSession preserves teacher history | ✅ |
| Attendance event-based | ✅ |
| Learning evidence historical | ✅ |
| Finance: partial/multi-charge payments | ✅ |
| Financial adjustments preserve history | ✅ |
| Cost B two-group without guessed labels | ✅ |
| vi/en separated from domain codes | ✅ |
| Derived KPIs not canonical fields | ✅ |
| ER diagram complete | ✅ |
| All 14 scenarios validated | ✅ 14/14 |
| No LMS in domain model | ✅ |
