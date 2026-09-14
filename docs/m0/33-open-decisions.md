# M0 — Open Decision Register

Intentionally unresolved business decisions. These must not become hidden assumptions in M1.

---

## Cost B business group names/codes

| Field | Value |
|-------|-------|
| **Status** | OPEN BUSINESS DECISION |
| **Technical state** | Two structural `cost_group` slots exist per organization |
| **Impact** | No technical blocker — slots are ready; labels/codes TBD |
| **M1 action** | Define business naming with finance stakeholders before expense reporting UI |

---

## TuitionPlan exclusivity/scope

| Field | Value |
|-------|-------|
| **Status** | OPEN BUSINESS RULE |
| **Technical state** | `tuition_plan` table exists; no overlap/exclusivity constraint |
| **Impact** | Pricing scope undefined — multiple active plans per context may or may not be allowed |
| **M1 action** | Lock pricing rules before enrollment billing workflows |

---

## FinancialPeriod

| Field | Value |
|-------|-------|
| **Status** | DEFERRED |
| **Technical state** | No `financial_period` table in M0 |
| **Impact** | Period-close reporting not available |
| **M1 action** | Design when finance reporting milestone is scoped |

---

## OrganizationSettings expansion

| Field | Value |
|-------|-------|
| **Status** | DEFERRED |
| **Technical state** | `organization` has `name`, `default_locale`, `status` only |
| **Impact** | No extended org configuration (timezone, branding, fiscal year, etc.) |
| **M1 action** | Extend when settings UI is designed |

---

## Student/Guardian portal access

| Field | Value |
|-------|-------|
| **Status** | OUT OF M0 |
| **Technical state** | Admin/staff application only in M0 |
| **Impact** | No self-service portal for students or guardians |
| **M1 action** | Separate milestone if product requires portal |

---

## Teacher-specific visibility rules

| Field | Value |
|-------|-------|
| **Status** | NOT YET LOCKED |
| **Technical state** | Teacher authorization via permission codes only; no class-scoped auto-filter |
| **Impact** | Teachers with `student.read` see all org students unless future rules added |
| **M1 action** | Define teacher visibility scope (own classes only vs org-wide) |

---

## Reporting & dashboards

| Field | Value |
|-------|-------|
| **Status** | OUT OF M0 |
| **Technical state** | `report.read` permission reserved; no reporting UI |
| **Impact** | No operational dashboards in foundation |
| **M1+ action** | Design reporting milestone separately |

---

## How to use this register

1. Before implementing M1 features, check whether the feature touches an open decision.
2. If yes, resolve or explicitly defer again with stakeholder sign-off.
3. Do not encode guessed business rules into schema constraints without decision closure.
