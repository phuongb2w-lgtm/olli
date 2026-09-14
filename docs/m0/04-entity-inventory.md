# M0-T01 — Preliminary Entity Inventory

**Date:** 2026-09-14  
**Status:** ⚠ **Partially superseded by M0-T02** — see [07-canonical-domain-model.md](./07-canonical-domain-model.md) for authoritative entity decisions.

### Corrections applied in M0-T02
- **Receivable, InvoiceLine** — rejected (duplicate debt source)
- **FinancialPeriod** — deferred
- **LocalePreference** — removed (locale on User/Organization)
- **CostGroup codes** `operating`/`teacher_direct` — not canonical; use `group_slot`
- **ClassSchedule** — added as explicit entity
- **ObservationRating** — added under TeacherObservation

For each entity: **purpose**, **key relationships**, **data classification** (master / event / financial transaction), and **historical-truth notes**.

Legend:
- **MD** = Master data  
- **EV** = Event / lifecycle data  
- **FT** = Financial transaction data  
- **CFG** = Configuration / reference data  

---

## Organization & Access

### Organization (Center)

| Attribute | Value |
|-----------|-------|
| **Purpose** | Represents the language center tenant; root scope for all data |
| **Relationships** | Parent of all domain entities; 1:N Users, Students, Classes, etc. |
| **Classification** | MD |
| **Historical notes** | Settings may be effective-dated (e.g. currency change); do not rewrite past financial records |

### User

| Attribute | Value |
|-----------|-------|
| **Purpose** | Authenticated staff account for system access |
| **Relationships** | N:M Roles; optional 1:1 link to Teacher; belongs to Organization |
| **Classification** | MD |
| **Historical notes** | `inactive`/`archived` state; never delete if referenced in audit or transactions |

### Role

| Attribute | Value |
|-----------|-------|
| **Purpose** | Named access profile (e.g. admin, teacher, accountant) |
| **Relationships** | N:M Permissions; N:M Users |
| **Classification** | CFG |
| **Historical notes** | Stable internal `code`; labels localized (vi/en) |

### Permission

| Attribute | Value |
|-----------|-------|
| **Purpose** | Atomic authorization capability (e.g. `enrollment.create`) |
| **Relationships** | N:M Roles |
| **Classification** | CFG |
| **Historical notes** | Stable code keys only |

### UserRole (assignment)

| Attribute | Value |
|-----------|-------|
| **Purpose** | Records which roles a user holds, with optional effective dates |
| **Relationships** | User, Role |
| **Classification** | EV (assignment event) |
| **Historical notes** | Effective_from / effective_to; past authorization context preserved |

### LocalePreference

| Attribute | Value |
|-----------|-------|
| **Purpose** | User or organization default language (vi, en) |
| **Relationships** | User and/or Organization |
| **Classification** | CFG |
| **Historical notes** | BCP 47 locale codes; not free-text labels |

---

## People

### Student

| Attribute | Value |
|-----------|-------|
| **Purpose** | Learner identity and operational profile |
| **Relationships** | N:M Guardian; 1:N Enrollment; 1:N Attendance, AssessmentResult, etc. |
| **Classification** | MD |
| **Historical notes** | Status lifecycle (`prospect`, `active`, `inactive`, `graduated`, `withdrawn`); soft archive; `created_at`, `updated_at`, `created_by`, `updated_by` |

### Guardian

| Attribute | Value |
|-----------|-------|
| **Purpose** | Parent/guardian contact; often billing contact |
| **Relationships** | N:M Student; 1:N Receivable/Payment (as payer) |
| **Classification** | MD |
| **Historical notes** | Same lifecycle/audit pattern as Student; inactive ≠ deleted |

### StudentGuardian

| Attribute | Value |
|-----------|-------|
| **Purpose** | Relationship between student and guardian (primary, emergency, billing) |
| **Relationships** | Student, Guardian |
| **Classification** | MD (relationship master) |
| **Historical notes** | `relationship_type` as stable code; effective dates if custody/contact changes |

### Teacher

| Attribute | Value |
|-----------|-------|
| **Purpose** | Instructor profile for scheduling, observations, and direct cost linkage |
| **Relationships** | Optional User; N:M TeachingSession (via assignment); 1:N TeacherObservation |
| **Classification** | MD |
| **Historical notes** | Employment status lifecycle; historical sessions retain teacher snapshot or FK to archived teacher |

---

## Academic Operations

### Course (Program)

| Attribute | Value |
|-----------|-------|
| **Purpose** | Catalog definition — level, program code, default structure |
| **Relationships** | 1:N Class |
| **Classification** | MD |
| **Historical notes** | Price/tuition rules reference Course with effective dates, not embedded in Course alone |

### Class

| Attribute | Value |
|-----------|-------|
| **Purpose** | Operational running group — specific schedule, term, capacity |
| **Relationships** | Course; 1:N Enrollment, TeachingSession, Assessment |
| **Classification** | MD |
| **Historical notes** | Status lifecycle (`planned`, `active`, `completed`, `cancelled`); teacher assignment via separate assignment records |

### Enrollment

| Attribute | Value |
|-----------|-------|
| **Purpose** | Student registered in a class for a defined period |
| **Relationships** | Student, Class; triggers Charge(s); scope for Attendance and Results |
| **Classification** | EV |
| **Historical notes** | **Critical:** immutable enrollment period (`start_date`, `end_date`); status changes append or use status history; changing "current class" on Student must NOT alter past Enrollment rows |

### ClassTeacherAssignment

| Attribute | Value |
|-----------|-------|
| **Purpose** | Which teacher(s) are assigned to a class, with effective dates |
| **Relationships** | Class, Teacher |
| **Classification** | EV |
| **Historical notes** | Changing assignment creates new row or closes prior; old TeachingSessions retain assigned teacher at time of session |

### TeachingSession

| Attribute | Value |
|-----------|-------|
| **Purpose** | Scheduled or actual teaching occurrence |
| **Relationships** | Class; teacher snapshot or FK; 1:N Attendance |
| **Classification** | EV |
| **Historical notes** | Store `scheduled_at`, `actual_start`, `actual_end`, status; teacher_id at session time (denormalized snapshot OR immutable assignment FK) |

### Attendance

| Attribute | Value |
|-----------|-------|
| **Purpose** | Student presence record for one session |
| **Relationships** | TeachingSession, Student, Enrollment (optional FK for validation) |
| **Classification** | EV |
| **Historical notes** | Status code (`present`, `absent`, `late`, `excused`); `recorded_at`, `recorded_by`; append-only corrections via adjustment record if needed |

---

## Learning Evidence

### Assessment

| Attribute | Value |
|-----------|-------|
| **Purpose** | Definition of an evaluation event (midterm, quiz, speaking test) |
| **Relationships** | Class (and optionally TeachingSession); 1:N AssessmentResult |
| **Classification** | EV (scheduled event) or MD (reusable template) — **see risks** |
| **Historical notes** | `assessment_type` as stable code; max_score fixed at creation; date fixed |

### AssessmentResult

| Attribute | Value |
|-----------|-------|
| **Purpose** | Score or outcome for one student on one assessment |
| **Relationships** | Assessment, Student, Enrollment |
| **Classification** | EV |
| **Historical notes** | Immutable once finalized; corrections via new version or explicit adjustment with reason |

### TeacherObservation

| Attribute | Value |
|-----------|-------|
| **Purpose** | Qualitative management evidence (concentration, engagement, participation, free-text comment) |
| **Relationships** | Student, Teacher, Class or TeachingSession |
| **Classification** | EV |
| **Historical notes** | Observation date; rating scales as stable codes; `created_by` |

### ProgressEvaluation

| Attribute | Value |
|-----------|-------|
| **Purpose** | Periodic summary judgment of student improvement/progress |
| **Relationships** | Student, Class or Enrollment, Teacher |
| **Classification** | EV |
| **Historical notes** | Evaluation period; level/progress as codes; effective snapshot of enrollment context |

---

## Finance

### Cost B Architecture (Mandatory Structure)

Cost architecture **must not** be flattened into arbitrary expense labels. The agreed **Cost B** model has **exactly two main groups**:

| Group code (proposed) | Name (localized) | Contains |
|----------------------|------------------|----------|
| `operating` | Operating Costs (vi: *Chi phí hoạt động*) | Indirect / overhead: rent, utilities, marketing, admin salaries, office supplies, insurance, etc. |
| `teacher_direct` | Teacher-Related / Direct Costs (vi: *Chi phí trực tiếp giáo viên*) | Costs directly tied to teaching delivery: teacher compensation, class materials, direct teaching supplies, session-based contractor fees, etc. |

> **⚠ UNRESOLVED:** Exact Cost B definition is referenced as "previously agreed" but not found in repository. Subcategory taxonomy under each group must be confirmed before M0-T02. **Do not flatten these two groups into a single expense list.**

Each ExpenseCategory belongs to **exactly one** CostGroup. Expenses reference a category (which implies its group).

---

### FinancialPeriod

| Attribute | Value |
|-----------|-------|
| **Purpose** | Bounded reporting window (month, quarter, term) |
| **Relationships** | Organization; scopes Expense, reporting aggregates |
| **Classification** | CFG |
| **Historical notes** | `start_date`, `end_date`, status (`open`, `closed`); closed periods restrict backdated edits |

### TuitionPlan / FeeSchedule

| Attribute | Value |
|-----------|-------|
| **Purpose** | Price rules for courses/classes with effective dates |
| **Relationships** | Course and/or Class; 1:N Charge generation |
| **Classification** | MD (versioned) |
| **Historical notes** | **Effective dating required** — price change must not rewrite historical Charge amounts |

### Charge (Tuition / Fee line)

| Attribute | Value |
|-----------|-------|
| **Purpose** | Monetary amount owed for a service |
| **Relationships** | Enrollment and/or Student; Guardian (payer); may roll into Receivable |
| **Classification** | FT |
| **Historical notes** | Immutable amount, currency, `charged_at`; links to TuitionPlan version used; status lifecycle |

### Receivable (Invoice)

| Attribute | Value |
|-----------|-------|
| **Purpose** | Bill issued to payer summarizing charges |
| **Relationships** | Guardian (payer); 1:N InvoiceLine → Charge; 1:N PaymentAllocation |
| **Classification** | FT |
| **Historical notes** | Invoice number, issue date, due date, status; PDF/export is presentation |

### InvoiceLine

| Attribute | Value |
|-----------|-------|
| **Purpose** | Line item on receivable pointing to underlying charge |
| **Relationships** | Receivable, Charge |
| **Classification** | FT |
| **Historical notes** | Denormalized description snapshot acceptable for export immutability |

### Payment

| Attribute | Value |
|-----------|-------|
| **Purpose** | Money received from payer |
| **Relationships** | Guardian; N:M Receivable via PaymentAllocation |
| **Classification** | FT |
| **Historical notes** | Immutable amount, `paid_at`, method code; reversals via contra Payment, not delete |

### PaymentAllocation

| Attribute | Value |
|-----------|-------|
| **Purpose** | Applies payment amount to specific receivable(s) |
| **Relationships** | Payment, Receivable |
| **Classification** | FT |
| **Historical notes** | Append-only; reallocation creates new allocation records |

### Discount / Adjustment

| Attribute | Value |
|-----------|-------|
| **Purpose** | Reduction or correction to charge or receivable with documented reason |
| **Relationships** | Charge or Receivable; optional Enrollment |
| **Classification** | FT |
| **Historical notes** | Reason code (stable); amount; `approved_by`; immutable once posted |

### CostGroup

| Attribute | Value |
|-----------|-------|
| **Purpose** | Top-level cost structure — **exactly two records per org in Cost B** |
| **Relationships** | 1:N ExpenseCategory |
| **Classification** | CFG |
| **Historical notes** | Stable codes `operating`, `teacher_direct`; names localized |

### ExpenseCategory

| Attribute | Value |
|-----------|-------|
| **Purpose** | Subclassification within a cost group |
| **Relationships** | CostGroup; 1:N Expense |
| **Classification** | CFG |
| **Historical notes** | Renaming category must not change historical Expense group attribution — store `cost_group_id` snapshot on Expense or use category version |

### Expense

| Attribute | Value |
|-----------|-------|
| **Purpose** | Money spent, recorded against category and period |
| **Relationships** | ExpenseCategory, FinancialPeriod; optional Teacher, Class (for direct cost attribution) |
| **Classification** | FT |
| **Historical notes** | Immutable amount, date, category snapshot; optional link to teacher/class for direct cost reporting |

---

## Source vs Calculated vs Cached

| Value | Treatment |
|-------|-----------|
| Enrollment dates, session times, attendance status | **Source** — store |
| Charge/Payment/Expense amounts | **Source** — store (immutable) |
| Assessment scores, observations | **Source** — store |
| Outstanding balance per receivable | **Calculated** — charges + adjustments − allocations |
| Revenue for period | **Calculated** — sum of posted charges/payments by period |
| Attendance rate | **Calculated** — present / scheduled sessions |
| Average score by class | **Calculated** — aggregate AssessmentResult |
| Cost by Cost B group | **Calculated** — sum Expense by CostGroup |
| Teacher cost per hour | **Calculated** — direct expenses + allocated compensation / teaching hours |
| Dashboard KPI tiles | **Calculated** (cache later if performance requires) |

---

## Audit & Timestamp Requirements Summary

| Entity group | created_at / updated_at | created_by / updated_by | Soft archive | Immutable when posted | Effective dates |
|--------------|-------------------------|-------------------------|--------------|----------------------|-----------------|
| Organization, User, Role | Yes | Yes | User: yes | N/A | UserRole: yes |
| Student, Guardian, Teacher | Yes | Yes | Yes | N/A | StudentGuardian: optional |
| Course, Class | Yes | Yes | Class: yes | N/A | ClassTeacherAssignment: yes |
| Enrollment, Session, Attendance | Yes | Yes | No delete | Attendance: correction workflow | Enrollment: yes |
| Assessment, Results, Observations | Yes | Yes | No delete | Results: yes when finalized | Assessment: event date |
| Charges, Payments, Expenses | Yes | Yes | No delete | **Yes** | TuitionPlan: yes |
| CostGroup, ExpenseCategory | Yes | Yes | Category: deactivate | Expense: yes | TuitionPlan: yes |

Full audit trail (field-level change log) is **identified but deferred** — prioritize on financial transactions and enrollment status changes.
