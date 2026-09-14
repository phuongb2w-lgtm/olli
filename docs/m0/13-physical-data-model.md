# M0-T03 — Physical Data Model

**Date:** 2026-09-14  
**PostgreSQL:** 15 (Supabase-compatible)  
**Migration:** `supabase/migrations/20260914140000_m0_foundation.sql`

---

## Naming Convention

| Choice | Decision |
|--------|----------|
| Table names | **Singular** `snake_case` (`student`, `enrollment`, `charge`) |
| Column names | `snake_case` |
| Logical User entity | Physical table **`app_user`** (PostgreSQL `USER` is reserved) |
| Primary keys | `uuid` via `gen_random_uuid()` |
| Money (VND) | `bigint` — whole currency units, no floating point |
| Business dates | `date` |
| Instants | `timestamptz` |

---

## Table Inventory (32 physical tables)

Includes 30 canonical domain tables + 2 global reference tables.

| # | Table | Domain | Scope |
|---|-------|--------|-------|
| 1 | `organization` | Organization | Tenant root |
| 2 | `permission` | Access | **Global** |
| 3 | `observation_indicator` | Learning | **Global** |
| 4 | `app_user` | Access | Organization-owned |
| 5 | `role` | Access | Organization-owned |
| 6 | `role_permission` | Access | Via role |
| 7 | `user_role` | Access | Organization-owned |
| 8 | `student` | People | Organization-owned |
| 9 | `guardian` | People | Organization-owned |
| 10 | `student_guardian` | People | Organization-owned |
| 11 | `teacher` | People | Organization-owned |
| 12 | `course` | Academic | Organization-owned |
| 13 | `class` | Academic | Organization-owned |
| 14 | `class_schedule` | Academic | Organization-owned |
| 15 | `enrollment` | Academic | Organization-owned |
| 16 | `class_teacher_assignment` | Academic | Organization-owned |
| 17 | `teaching_session` | Academic | Organization-owned |
| 18 | `attendance` | Academic | Organization-owned |
| 19 | `assessment` | Learning | Organization-owned |
| 20 | `assessment_result` | Learning | Organization-owned |
| 21 | `teacher_observation` | Learning | Organization-owned |
| 22 | `observation_rating` | Learning | Organization-owned |
| 23 | `progress_evaluation` | Learning | Organization-owned |
| 24 | `tuition_plan` | Finance | Organization-owned |
| 25 | `charge` | Finance | Organization-owned |
| 26 | `financial_adjustment` | Finance | Organization-owned |
| 27 | `payment` | Finance | Organization-owned |
| 28 | `payment_allocation` | Finance | Organization-owned |
| 29 | `cost_group` | Finance | Organization-owned |
| 30 | `expense_category` | Finance | Organization-owned |
| 31 | `expense` | Finance | Organization-owned |

**Derived view (not stored):** `charge_balance`

**Explicitly absent:** `receivable`, `invoice_line`, `financial_period`

---

## Global vs Organization-Owned

| Table | Classification | Reason |
|-------|----------------|--------|
| `permission` | Global | Authorization capabilities are system-defined |
| `observation_indicator` | Global | Controlled indicator codes (`concentration`, etc.) |
| All other business tables | Organization-owned | Tenant data with `organization_id` |

---

## Archive / Lifecycle Strategy

| Category | Mechanism |
|----------|-----------|
| Master data (Student, Guardian, Teacher, Course, Class, ExpenseCategory) | `status` CHECK + soft values (`inactive`, `archived`) |
| Events / transactions | Terminal status (`completed`, `void`, `finalized`); **no hard delete** |
| Financial posted records | Immutable; corrections via new adjustment/allocation rows |
| CostGroup | Cannot hard-delete; exactly 2 slots per org via trigger |

---

## M0-T02 Amendments in Physical Schema

| Topic | M0-T03 Decision |
|-------|-----------------|
| Attendance `student_id` | **Removed** — student identified via `enrollment_id` |
| User table name | **`app_user`** |
| Optional FK without composite SET NULL | `teacher.user_id`, `class_schedule_id`, `teaching_session_id` use single-column FK + org validation trigger where needed |
| FinancialAdjustment column | **`amount_delta`** (signed bigint) |
| CostGroup initialization | **AFTER INSERT trigger** on `organization` creates slots 1 and 2 |

See [17-m0-t03-decisions.md](./17-m0-t03-decisions.md) for full decision log.
