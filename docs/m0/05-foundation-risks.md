# M0-T01 — Foundation Risks

**Date:** 2026-09-14

---

## 1. Ambiguous Concepts

| Concept | Ambiguity | Recommendation |
|---------|-----------|----------------|
| **Course vs Class** | "Course" may mean catalog template or running cohort | **Course** = catalog/program; **Class** = operational instance with schedule and term |
| **Staff vs User** | Staff may be any employee; User is login identity | Use **User + Role** for staff; separate **Teacher** master only for instructors |
| **Assessment as template vs event** | One-off quiz vs reusable rubric | M0-T02: model **Assessment** as event tied to Class + date; defer reusable templates |
| **Receivable vs Invoice** | Terms may overlap | Single **Receivable** entity with `invoice_number` and issue date; InvoiceLine for detail |
| **Guardian vs Payer** | Payer may not be guardian (company sponsor) | Guardian is primary; add optional **Payer** reference on Receivable if needed in M0-T03 |
| **Teaching Session vs Schedule** | Recurring pattern vs single occurrence | **TeachingSession** = occurrence; recurring rule is configuration (defer RRULE to later) |

---

## 2. Duplicated Concepts (Avoid in Modelling)

| Risk | Prevention |
|------|------------|
| Storing "current class" on Student **and** open Enrollment | **Enrollment** is source of truth; "current" is computed query |
| Duplicating teacher name on Session, Observation, Expense | FK to Teacher; snapshot only where immutability required |
| Separate "tuition" and "fee" entities without distinction | Unified **Charge** with `charge_type` code |
| Dashboard tables mirroring transactional data | Compute from source; no `monthly_revenue_summary` table in M0 |
| Vietnamese status strings in database | Stable codes only; i18n at UI layer |

---

## 3. Data-History Risks

| Scenario | Risk | Mitigation |
|----------|------|------------|
| Student transfers class | Past attendance/reporting corrupted | Close old Enrollment; open new; never update historical Enrollment.class_id in place |
| Teacher reassigned | Past sessions show wrong teacher | Session stores teacher at time of delivery; ClassTeacherAssignment is effective-dated |
| Tuition price increase | Historical invoices recalculated | Charge stores amount at creation; TuitionPlan versioned with effective_from |
| Expense category renamed/reparented | Past reports change group | Expense stores cost_group_id + category_id at posting time |
| Guardian deleted | Receivables orphaned | Soft archive; FK restrict on financial records |
| Student inactive | Historical evidence hidden | Filter active in UI; include inactive in historical reports |
| Assessment score corrected | Original score lost | Status `finalized` + correction record or versioned result |

---

## 4. Finance-Model Risks

| Risk | Severity | Notes |
|------|----------|-------|
| **Cost B not documented in repo** | **High** | Two-group structure assumed (`operating`, `teacher_direct`). **Must confirm before M0-T02.** |
| Flattening cost groups into tags | High | Violates Cost B; reporting would lose operating vs direct split |
| Mixing accrual and cash without period model | Medium | FinancialPeriod + explicit posting dates |
| Charges editable after payment | High | Immutable charges; adjustments as separate records |
| Multi-currency (if needed) | Medium | Not specified; default single currency per Organization with code field |
| Tax / VAT | Low (unknown) | Not in M0 scope unless specified; avoid hardcoding "no tax" |

### Cost B — Assumed Structure (Pending Confirmation)

```
CostGroup: operating
  └── ExpenseCategory: rent, utilities, marketing, admin_salary, ...

CostGroup: teacher_direct
  └── ExpenseCategory: teacher_salary, teaching_materials, contractor_fee, ...
```

If the prior agreement differs (different group names, different split logic, or mandatory sub-group rules), **M0-T02 must not proceed until resolved**.

---

## 5. Localization Risks

| Risk | Mitigation |
|------|------------|
| Hard-coded Vietnamese in validation messages | All messages via i18n keys from M0 |
| Enum labels stored in DB as Vietnamese | Store code; translate in app |
| Finance terms inconsistent between vi/en | Glossary of stable keys in i18n resource files |
| Exported PDF invoices in wrong language | Export uses locale parameter + same keys |
| Date/number formatting | Locale-aware formatting layer; store ISO dates and decimal amounts in DB |
| RTL or third language | Not required; design keys to allow extension |

**M0 i18n minimum:** Vietnamese (`vi`) and English (`en`) as first-class; locale code on User; organization default locale.

---

## 6. Architecture Conflicts with Existing Code

**None.** Greenfield repository.

Future conflicts to prevent:
- Do not embed business rules in React/Vue components  
- Do not use UI form field names as database column semantics  
- Do not choose an ORM pattern that merges Enrollment history into Student profile  

---

## 7. Product Boundary Risks

| Risk | Description |
|------|-------------|
| Scope creep to LMS | Feature requests for homework/exams must be rejected or routed to external tools |
| Over-automation | Auto-grading, auto-progress from AI — out of scope |
| Guardian portal premature | Mobile/portal before domain stable duplicates logic |
| Reporting before data model | Dashboards before canonical entities invite wrong aggregates |

---

## 8. Unresolved Conflicts Requiring Stakeholder Input

| # | Item | Blocking M0-T02? |
|---|------|------------------|
| 1 | Confirm Cost B group names and subcategory list | **Yes** — finance schema depends on this |
| 2 | Enrollment status enum (exact lifecycle states) | Partial — can start with draft set |
| 3 | One guardian vs many per student billing rules | Partial |
| 4 | Technology stack selection | Yes — before implementation, not before entity modelling |
| 5 | Multi-center (SaaS) vs single center | Partial — recommend `organization_id` on all entities anyway |
| 6 | Assessment types catalog (center-defined vs fixed) | No — defer to CFG table with codes |

---

## 9. Risk Priority Matrix

| Priority | Risk | Action |
|----------|------|--------|
| P0 | Cost B undefined in repo | Stakeholder confirmation |
| P0 | Historical enrollment corruption | Enforce in M0-T02 schema rules |
| P1 | i18n not planned from day one | Include in stack choice and folder structure in M0-T02/T03 |
| P1 | LMS scope creep | Product contract sign-off |
| P2 | Assessment template complexity | Defer templates; event-only model first |
| P2 | Audit log scope | Identify tables now; implement later |
