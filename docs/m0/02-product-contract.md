# M0-T01 — Product Contract

**Application name (working):** English Language Center Management Web App  
**Codename / repo:** Olli  
**Version:** M0 Foundation  
**Date:** 2026-09-14

---

## 1. Product Purpose

Olli is an **operational management system** for an English/language center. It connects people, academic operations, learning evidence, and financial records so that management can understand:

1. **Business performance** — revenue, receivables, costs, margins, and financial health  
2. **Learning / service quality** — attendance, assessments, teacher observations, and student progress

These two dimensions must be **connectable through the data model** (e.g., linking class enrollment and attendance to tuition charges; linking teacher costs to classes taught; linking assessment trends to retention and revenue).

The system records **management evidence** about teaching delivery and outcomes. It does **not** deliver learning content or replace the teacher's in-class teaching process.

---

## 2. Primary Users

| User type | Role in system | Primary needs |
|-----------|----------------|---------------|
| **Center management / owner** | Strategic oversight | Financial performance, cost structure, enrollment trends, quality indicators, reports |
| **Administrative staff** | Day-to-day operations | Student/guardian records, enrollments, scheduling, billing, payments, expenses |
| **Teachers** | Academic delivery (recorded, not delivered in-app) | Attendance, assessments, observations, progress notes |
| **Accountant / finance staff** | Financial operations | Receivables, payments, expenses, period close, cost reporting |
| **Guardians / parents** | Indirect (future portal possible) | Visibility into enrollment, attendance, progress, billing (scope TBD in later milestones) |

M0 establishes the domain foundation for **staff-facing management**. Guardian/student portals are not in M0 scope unless explicitly added later.

---

## 3. In Scope

### People & organization
- Students, guardians, teachers, staff users  
- Roles, permissions, center settings  
- Bilingual UI (Vietnamese + English)

### Academic operations
- Courses/programs, classes, enrollments  
- Teaching sessions / schedules  
- Attendance recording

### Learning evidence (management records only)
- Assessments and results (scores entered by staff/teachers)  
- Teacher observations (concentration, engagement, comments)  
- Progress evaluations

### Finance
- Tuition charges and receivables  
- Payments, discounts, adjustments  
- Expenses with **structured cost grouping** (Cost B: two main groups)  
- Financial periods  
- Performance reporting inputs (derived, not stored as opaque dashboard blobs)

### Cross-cutting
- Historical truth in data design  
- Stable internal codes/keys with localized labels  
- Auditability requirements identified (full audit implementation deferred)

---

## 4. Explicit Non-Scope

This application is **NOT an LMS**. The following are **out of scope** and must not be designed or implemented:

| Non-scope item | Rationale |
|----------------|-----------|
| Online homework | Teaching activity happens outside the app |
| Online examinations | No in-app exam delivery or auto-grading |
| Question banks | Content management, not operations |
| Student exercise interfaces | No student learning UI |
| Lesson content delivery | No curriculum/content hosting |
| Video courses | No media LMS |
| In-app student learning activities | Management evidence only |
| Automated grading systems | Teachers enter scores/observations manually |

Homework, exercises, teaching activities, and examinations remain part of the **teacher's process outside** this application. Olli records **evidence** (attendance, scores, observations, progress evaluations) after the fact.

### Also excluded from M0-T01 / early M0
- Dashboard screen implementation  
- Large CRUD UI suites  
- Visual UI redesign  
- Full audit log implementation  
- Mobile apps  
- Public API (domain model must be API-ready, but no API build in M0-T01)

---

## 5. Success Criteria for M0 Foundation

M0 foundation is successful when:

1. Product boundaries are documented and agreed  
2. Domain map and entity inventory are stable enough for relational modelling (M0-T02)  
3. Historical-truth and i18n rules are explicit  
4. Cost B two-group finance structure is confirmed  
5. No premature implementation constrains future architecture

---

## 6. Glossary (Canonical Terms)

| Term | Definition |
|------|------------|
| **Management evidence** | Records that prove or describe service delivery and outcomes (attendance, scores, observations) — not learning content |
| **Master data** | Relatively stable reference entities (Student, Class, ExpenseCategory) |
| **Event data** | Point-in-time or lifecycle records (Attendance, Enrollment status change, TeachingSession) |
| **Financial transaction data** | Immutable or append-only monetary records (Charge, Payment, Expense) |
| **Effective date** | Date from which a master-data version applies; preserves historical reporting |
| **Stable code** | Internal identifier (e.g. `status: active`) never stored as a translated label |
| **Cost B** | Agreed two-group cost architecture — see [04-entity-inventory.md](./04-entity-inventory.md) Finance section |
