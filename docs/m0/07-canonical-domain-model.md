# M0-T02 — Canonical Domain Model

**Date:** 2026-09-14  
**Status:** Proposed for review  
**Baseline commit:** `294e6d3` (M0-T01)

This document is the **authoritative logical model** for M0-T03 physical schema work. It supersedes preliminary assumptions in [04-entity-inventory.md](./04-entity-inventory.md) where they conflict.

---

## Modelling Conventions

| Convention | Rule |
|------------|------|
| Primary keys | UUID (`uuid`) for all canonical entities |
| Tenant scope | `organization_id` on all tenant-owned records |
| Status / type values | Stable machine codes (`active`, `present`) — never translated labels |
| Timestamps | `created_at`, `updated_at` on all entities |
| Authorship | `created_by`, `updated_by` (FK → User) on user-mutable records |
| Deletion | Soft archive (`archived_at` or `status = inactive`); no hard delete of referenced records |
| Derived state | Not stored canonically (current class, balances, KPIs) |

---

## Entity Type Legend

| Code | Meaning |
|------|---------|
| **MD** | Master data |
| **REL** | Relationship / assignment history |
| **EV** | Event or lifecycle record |
| **FT** | Financial transaction |
| **CFG** | Configuration / reference |

---

## A. Organization & Access

### Organization

| Field | Value |
|-------|-------|
| **Purpose** | Language center tenant; root organizational boundary |
| **Domain** | Organization & Access |
| **Type** | MD |
| **Primary relationships** | 1:N all tenant-owned entities |
| **Cardinality** | One org → many records in every domain |
| **Organization scope** | Self (tenant root) |
| **Historical behavior** | Settings changes (currency, locale) do not rewrite past financial amounts |
| **Lifecycle / status** | `active`, `inactive` |
| **Deletion / archive** | Soft archive only; restrict if any child records exist |

**Key attributes:** `name`, `default_locale` (BCP 47: `vi`, `en`), `timezone`, `currency_code` (ISO 4217)

---

### User

| Field | Value |
|-------|-------|
| **Purpose** | Authenticated staff identity for login and authorization |
| **Domain** | Organization & Access |
| **Type** | MD |
| **Primary relationships** | N:M Role via UserRole; optional link from Teacher |
| **Cardinality** | Many users per org; one user may hold multiple roles |
| **Organization scope** | `organization_id` required |
| **Historical behavior** | UserRole assignments are effective-dated |
| **Lifecycle / status** | `active`, `inactive`, `locked` |
| **Deletion / archive** | Soft archive; preserve FK integrity on historical `created_by` |

**Key attributes:** `email`, `password_credential_ref`, `display_name`, `preferred_locale`

> **User ≠ Teacher.** A User is an authentication/account record. A Teacher is a business identity for academic and cost attribution. Link: `Teacher.user_id` (optional, nullable FK → User). A teacher may exist without login; a user may exist without being a teacher (admin, accountant).

---

### Role

| Field | Value |
|-------|-------|
| **Purpose** | Named authorization profile |
| **Domain** | Organization & Access |
| **Type** | CFG |
| **Primary relationships** | N:M Permission via RolePermission; N:M User via UserRole |
| **Cardinality** | Many roles per org |
| **Organization scope** | `organization_id` |
| **Historical behavior** | Role code stable; label localized in i18n |
| **Lifecycle / status** | `active`, `inactive` |
| **Deletion / archive** | Deactivate; never delete if UserRole history exists |

**Key attributes:** `code` (stable, e.g. `admin`, `teacher`, `accountant`)

---

### Permission

| Field | Value |
|-------|-------|
| **Purpose** | Atomic authorization capability |
| **Domain** | Organization & Access |
| **Type** | CFG |
| **Primary relationships** | N:M Role via RolePermission |
| **Cardinality** | Many permissions per role |
| **Organization scope** | Global catalog or org-scoped (org-scoped preferred for flexibility) |
| **Historical behavior** | Code-only identifiers |
| **Lifecycle / status** | `active`, `inactive` |
| **Deletion / archive** | Deactivate only |

**Key attributes:** `code` (e.g. `enrollment.create`, `charge.post`)

---

### RolePermission

| Field | Value |
|-------|-------|
| **Purpose** | Junction: which permissions a role grants |
| **Domain** | Organization & Access |
| **Type** | CFG |
| **Primary relationships** | Role, Permission |
| **Cardinality** | N:M between Role and Permission |
| **Organization scope** | Inherited via Role |
| **Historical behavior** | Static mapping; changes affect future authorization only |
| **Lifecycle / status** | Implicit via Role status |
| **Deletion / archive** | Remove mapping row if role reconfigured |

---

### UserRole

| Field | Value |
|-------|-------|
| **Purpose** | Assignment of role(s) to user with optional effective window |
| **Domain** | Organization & Access |
| **Type** | REL |
| **Primary relationships** | User, Role |
| **Cardinality** | N:M with temporal semantics |
| **Organization scope** | Inherited via User |
| **Historical behavior** | `effective_from`, `effective_to` preserve past authorization context |
| **Lifecycle / status** | `active`, `ended` |
| **Deletion / archive** | End-date assignment; do not delete historical rows |

---

## B. People

### Student

| Field | Value |
|-------|-------|
| **Purpose** | Learner identity and operational profile |
| **Domain** | People |
| **Type** | MD |
| **Primary relationships** | N:M Guardian via StudentGuardian; 1:N Enrollment |
| **Cardinality** | Many students per org |
| **Organization scope** | `organization_id` |
| **Historical behavior** | **No `current_class_id`.** Current class derived from active Enrollment |
| **Lifecycle / status** | `prospect`, `active`, `inactive`, `graduated`, `withdrawn` |
| **Deletion / archive** | Soft archive; historical records retain FK |

**Key attributes:** `given_name`, `family_name`, `date_of_birth`, `student_code` (human-readable, not PK)

---

### Guardian

| Field | Value |
|-------|-------|
| **Purpose** | Parent/guardian contact; primary billing party |
| **Domain** | People |
| **Type** | MD |
| **Primary relationships** | N:M Student via StudentGuardian; 1:N Payment |
| **Cardinality** | Many guardians per org; one guardian → many students |
| **Organization scope** | `organization_id` |
| **Historical behavior** | Inactive guardian remains on historical charges/payments |
| **Lifecycle / status** | `active`, `inactive` |
| **Deletion / archive** | Soft archive |

**Key attributes:** `given_name`, `family_name`, `phone`, `email`

---

### StudentGuardian

| Field | Value |
|-------|-------|
| **Purpose** | Relationship between student and guardian |
| **Domain** | People |
| **Type** | REL |
| **Primary relationships** | Student, Guardian |
| **Cardinality** | N:M — multiple guardians per student; one guardian → multiple students |
| **Organization scope** | Inherited via Student |
| **Historical behavior** | Relationship type and contact flags may change with effective dates |
| **Lifecycle / status** | `active`, `ended` |
| **Deletion / archive** | End relationship; do not delete historical link |

**Key attributes:** `relationship_type` (`mother`, `father`, `guardian`, `other`), `is_primary_contact`, `is_billing_contact`

> Do **not** store guardians as repeated text fields on Student.

---

### Teacher

| Field | Value |
|-------|-------|
| **Purpose** | Instructor business identity for scheduling, evidence, and cost attribution |
| **Domain** | People |
| **Type** | MD |
| **Primary relationships** | Optional User; ClassTeacherAssignment; TeachingSession; TeacherObservation |
| **Cardinality** | Many teachers per org |
| **Organization scope** | `organization_id` |
| **Historical behavior** | Inactive teacher remains on historical sessions and expenses |
| **Lifecycle / status** | `active`, `inactive`, `on_leave`, `terminated` |
| **Deletion / archive** | Soft archive |

**Key attributes:** `given_name`, `family_name`, `employee_code`, `user_id` (nullable FK → User)

---

## C. Academic Operations

### Course

| Field | Value |
|-------|-------|
| **Purpose** | Catalog / program definition |
| **Domain** | Academic Operations |
| **Type** | MD |
| **Primary relationships** | 1:N Class; referenced by TuitionPlan |
| **Cardinality** | Many courses per org |
| **Organization scope** | `organization_id` |
| **Historical behavior** | Catalog changes do not alter completed class records |
| **Lifecycle / status** | `active`, `inactive`, `archived` |
| **Deletion / archive** | Soft archive |

**Key attributes:** `code`, `level_code`, `default_duration_weeks`

---

### Class

| Field | Value |
|-------|-------|
| **Purpose** | Operational running group — a specific offering with term and capacity |
| **Domain** | Academic Operations |
| **Type** | MD |
| **Primary relationships** | Course; 1:N Enrollment, ClassSchedule, TeachingSession, Assessment |
| **Cardinality** | Many classes per course |
| **Organization scope** | `organization_id` |
| **Historical behavior** | Teacher assignment via ClassTeacherAssignment, not a mutable field on Class |
| **Lifecycle / status** | `planned`, `active`, `completed`, `cancelled` |
| **Deletion / archive** | Soft archive after terminal status |

**Key attributes:** `name`, `term_start_date`, `term_end_date`, `capacity`

---

### ClassSchedule

| Field | Value |
|-------|-------|
| **Purpose** | Planned recurring teaching arrangement for a class |
| **Domain** | Academic Operations |
| **Type** | REL |
| **Primary relationships** | Class; source for TeachingSession generation |
| **Cardinality** | One class → one or more schedule rules |
| **Organization scope** | Inherited via Class |
| **Historical behavior** | Effective-dated; schedule changes do not rewrite past sessions |
| **Lifecycle / status** | `active`, `ended` |
| **Deletion / archive** | End-date rule; preserve for historical session linkage |

**Key attributes:** `weekday_code`, `start_time`, `end_time`, `effective_from`, `effective_to`, `location`

> **ClassSchedule ≠ TeachingSession.** Schedule = planned pattern. Session = individual meeting (actual operational event).

---

### Enrollment

| Field | Value |
|-------|-------|
| **Purpose** | Historical bridge linking Student to Class for a bounded period |
| **Domain** | Academic Operations |
| **Type** | EV |
| **Primary relationships** | Student, Class; scope for Attendance, AssessmentResult, learning evidence |
| **Cardinality** | Many enrollments per student over time; many per class |
| **Organization scope** | `organization_id` |
| **Historical behavior** | **Critical.** Period is immutable once closed. Transfer = close + new enrollment |
| **Lifecycle / status** | `pending`, `active`, `transferred`, `withdrawn`, `completed` |
| **Deletion / archive** | Never delete; terminal status only |

**Key attributes:** `start_date`, `end_date` (nullable while active)

**Temporal rule:** A student must not have **overlapping active enrollment periods for the same class**. Rejoining the same class later creates a **new** enrollment row. Do **not** use `UNIQUE(student_id, class_id)`.

---

### ClassTeacherAssignment

| Field | Value |
|-------|-------|
| **Purpose** | Which teacher is assigned to a class, effective-dated |
| **Domain** | Academic Operations |
| **Type** | REL |
| **Primary relationships** | Class, Teacher |
| **Cardinality** | One class may have sequential or concurrent assignments |
| **Organization scope** | Inherited via Class |
| **Historical behavior** | New assignment closes prior row; does not rewrite TeachingSession |
| **Lifecycle / status** | `active`, `ended` |
| **Deletion / archive** | End-date; never delete if sessions reference era |

**Key attributes:** `effective_from`, `effective_to`, `role_code` (`primary`, `assistant`)

---

### TeachingSession

| Field | Value |
|-------|-------|
| **Purpose** | One actual or scheduled class meeting — historical record of what happened |
| **Domain** | Academic Operations |
| **Type** | EV |
| **Primary relationships** | Class; Teacher (session teacher); ClassSchedule (optional); 1:N Attendance |
| **Cardinality** | Many sessions per class |
| **Organization scope** | `organization_id` |
| **Historical behavior** | **`teacher_id` frozen at session creation/completion.** Later class reassignment must not rewrite |
| **Lifecycle / status** | `scheduled`, `in_progress`, `completed`, `cancelled` |
| **Deletion / archive** | Cancel status; never hard delete with attendance |

**Key attributes:** `scheduled_start_at`, `scheduled_end_at`, `actual_start_at`, `actual_end_at`, `teacher_id`

---

### Attendance

| Field | Value |
|-------|-------|
| **Purpose** | Student presence record for one teaching session |
| **Domain** | Academic Operations |
| **Type** | EV |
| **Primary relationships** | TeachingSession, **Enrollment** (primary context), Student |
| **Cardinality** | One row per (session, enrollment); many per session |
| **Organization scope** | Inherited via Class |
| **Historical behavior** | Event-based; corrections via explicit correction record or status update with audit |
| **Lifecycle / status** | `present`, `absent`, `late`, `excused` |
| **Deletion / archive** | Never delete; correct with audit trail |

> **Decision:** Primary FK is **Enrollment** (not Student alone) because enrollment defines the student's membership in the class during that period. See [08-entity-relations.md](./08-entity-relations.md).

---

## D. Learning Evidence

### Assessment

| Field | Value |
|-------|-------|
| **Purpose** | Teacher/staff-recorded evaluation event (management evidence, not exam delivery) |
| **Domain** | Learning Evidence |
| **Type** | EV |
| **Primary relationships** | Class; 1:N AssessmentResult |
| **Cardinality** | Many assessments per class |
| **Organization scope** | `organization_id` |
| **Historical behavior** | `max_score` and `assessed_on` fixed at creation |
| **Lifecycle / status** | `draft`, `open`, `closed` |
| **Deletion / archive** | Close/cancel; retain if results exist |

**Key attributes:** `assessment_type_code`, `title`, `max_score`, `assessed_on`

> No assessment-template engine in M0.

---

### AssessmentResult

| Field | Value |
|-------|-------|
| **Purpose** | One student's score/outcome on an assessment |
| **Domain** | Learning Evidence |
| **Type** | EV |
| **Primary relationships** | Assessment, Enrollment, Student; author Teacher/User |
| **Cardinality** | One result per (assessment, enrollment) typically |
| **Organization scope** | Inherited via Assessment |
| **Historical behavior** | Immutable when `finalized`; corrections via new adjustment row |
| **Lifecycle / status** | `draft`, `finalized`, `corrected` |
| **Deletion / archive** | Never delete finalized results |

**Key attributes:** `raw_score`, `max_score` (copied from assessment at entry), `normalized_score` (**derived**, not stored)

---

### TeacherObservation

| Field | Value |
|-------|-------|
| **Purpose** | Header for qualitative management evidence about a student |
| **Domain** | Learning Evidence |
| **Type** | EV |
| **Primary relationships** | Enrollment, Student, Class, Teacher; optional TeachingSession; 1:N ObservationRating |
| **Cardinality** | Many observations per enrollment |
| **Organization scope** | `organization_id` |
| **Historical behavior** | Append-only evidence; never overwrite prior observations |
| **Lifecycle / status** | `draft`, `recorded` |
| **Deletion / archive** | Soft void with reason; retain for audit |

**Key attributes:** `observed_at`, `comment` (free text)

---

### ObservationRating

| Field | Value |
|-------|-------|
| **Purpose** | Structured indicator rating within an observation (extensible without EAV) |
| **Domain** | Learning Evidence |
| **Type** | EV |
| **Primary relationships** | TeacherObservation |
| **Cardinality** | One row per indicator per observation (1–N indicators) |
| **Organization scope** | Inherited via observation |
| **Historical behavior** | Indicator codes stable; values are codes not translated labels |
| **Lifecycle / status** | Implicit via parent observation |
| **Deletion / archive** | Void with parent observation |

**Key attributes:** `indicator_code` (`concentration`, `engagement`, `participation`, …), `rating_code` (`low`, `medium`, `high` or numeric scale code)

> Simple extensibility: add new `indicator_code` values in config/i18n without schema redesign. Not a generic EAV system — fixed columns per row (indicator + rating).

---

### ProgressEvaluation

| Field | Value |
|-------|-------|
| **Purpose** | Periodic teacher judgment of student improvement/progress |
| **Domain** | Learning Evidence |
| **Type** | EV |
| **Primary relationships** | Enrollment, Student, Class, Teacher |
| **Cardinality** | Many evaluations per enrollment over time |
| **Organization scope** | `organization_id` |
| **Historical behavior** | Each evaluation is a new record; never overwrite prior evaluations |
| **Lifecycle / status** | `draft`, `finalized` |
| **Deletion / archive** | Void with audit; retain history |

**Key attributes:** `evaluation_period_start`, `evaluation_period_end`, `evaluated_at`, `progress_level_code`, `improvement_code`, `summary_comment`

> Progress is **not** a mutable field on Student.

---

## E. Finance

See [09-finance-model.md](./09-finance-model.md) for full finance decisions.

### TuitionPlan — MD (versioned, effective-dated)
### Charge — FT (canonical money owed)
### FinancialAdjustment — FT (discount, waiver, correction, reversal)
### Payment — FT (money received)
### PaymentAllocation — FT (payment applied to charge)
### CostGroup — CFG (exactly two slots per org; labels pending)
### ExpenseCategory — CFG (belongs to one CostGroup)
### Expense — FT (actual spend event with category snapshot)

---

## F. Rejected / Deferred from M0-T01 Preliminary Inventory

| Entity | M0-T02 Decision | Reason |
|--------|-----------------|--------|
| **Receivable** | **Rejected** | Duplicates Charge as debt source; invoice is derived document |
| **InvoiceLine** | **Rejected** | Duplicates Charge; no second debt store |
| **FinancialPeriod** | **Deferred** | Period close/lock not required yet; use transaction dates |
| **LocalePreference** | **Rejected** | Simplified to `User.preferred_locale` + `Organization.default_locale` |
| **OrganizationSettings** | **Deferred** | Core settings on Organization; expand in M0-T03 if needed |

---

## Canonical Entity Count

**30 accepted entities** for the logical model (including junction/child tables RolePermission, ObservationRating, ClassSchedule).

---

## Corrections from M0-T01

| M0-T01 assumption | M0-T02 correction |
|-------------------|-------------------|
| Cost B groups named `operating` / `teacher_direct` | **Not canonical.** Use `group_slot` (1 or 2); business codes/names pending |
| Receivable + InvoiceLine in finance chain | **Removed.** Charge is sole debt source |
| FinancialPeriod required | **Deferred** |
| ClassSchedule implicit | **Added explicitly** |
| TeacherObservation flat fields only | **Header + ObservationRating** for extensible indicators |
| LocalePreference entity | **Removed.** Locale on User/Organization |
