# M0-T03 — Decision Log

**Date:** 2026-09-14

Physical schema decisions and deviations from M0-T02.

---

## 1. Attendance: No `student_id`

**M0-T02:** Listed `student_id` as denormalized convenience.  
**M0-T03:** **Removed.** Student identity flows through `enrollment_id → student`.  
**Reason:** Eliminates duplicate identity; enrollment is the historical context anchor.  
**Integrity:** `UNIQUE(teaching_session_id, enrollment_id)` + context trigger.

---

## 2. Table Naming: Singular

All tables use **singular** names (`student`, not `students`) aligned with entity names in domain docs.

---

## 3. `app_user` Physical Name

Logical **User** entity maps to table **`app_user`** because `USER` is a PostgreSQL reserved keyword.

---

## 4. Cross-Organization FK Strategy

**Primary pattern:** `UNIQUE(organization_id, id)` on parent + composite FK on child.

**Optional links** (`teacher.user_id`, schedule/session references): single-column FK with `ON DELETE SET NULL` where composite SET NULL would incorrectly null `organization_id`. Org match enforced via trigger on `teacher.user_id`.

---

## 5. FinancialAdjustment Sign Convention

Column: **`amount_delta`** (bigint)

| Sign | Meaning |
|------|---------|
| Positive | Increases amount owed |
| Negative | Decreases amount owed |

Reporting must not infer direction from `adjustment_type_code` alone.

---

## 6. CostGroup Lifecycle

On `organization` INSERT:
- Trigger inserts `cost_group` rows for `group_slot` 1 and 2
- `code` remains **NULL** — no guessed business names
- `UNIQUE(organization_id, group_slot)` prevents duplicates

---

## 7. ExpenseCategory Semantic Reparenting

**Rule:** If posted expenses exist, `cost_group_id` cannot change.

**Mechanism:** Trigger `prevent_expense_category_reparent`

**Business workflow:** Archive old category → create new category under target group.

**Cosmetic rename** of `display_name` allowed without trigger block.

---

## 8. Expense Cost Group Snapshot

`expense.cost_group_id` copied/validated against `expense_category.cost_group_id` at insert via trigger `validate_expense_cost_group`.

Protects historical reporting if category metadata changes (but not semantic reparenting — that is blocked).

---

## 9. Money Type

**VND and all amounts:** `bigint` (whole units)  
**Currency:** `currency_code text DEFAULT 'VND'` on monetary tables  
No `double precision` or `float` for money.

---

## 10. Timestamp Types

| Use | Type |
|-----|------|
| Business dates (enrollment, due date, incurred date) | `date` |
| Instants (created_at, session times, paid_at) | `timestamptz` |

---

## 11. `updated_at` Maintenance

Trigger function `set_updated_at()` applied to mutable master/event tables.

---

## 12. FinancialPeriod — Still Deferred

No physical table. Reporting filters by transaction dates.

---

## 13. Receivable / InvoiceLine — Still Absent

Confirmed not created. Invoice is a derived document over `charge` rows.

---

## 14. TuitionPlan Overlap

**Unresolved:** Exclusive effective periods per pricing scope (course vs class) not enforced in DB yet — scope rules need business confirmation. Documented rather than invented.

---

## 15. Status Representation

`text` + `CHECK` constraints instead of PostgreSQL ENUM types for easier future migrations.

---

## 16. LMS Tables

None created. No question, answer, exercise, or exam delivery tables.

---

## 17. RLS / Auth

Not implemented in M0-T03. Deferred to subsequent foundation task.

---

## 18. Seed Data Scope

Seeded:
- Global `permission` codes (29)
- Global `observation_indicator` codes (3)
- Dev organization fixture with admin/teacher/accountant roles (only if no org exists)

Not seeded:
- Cost B business names/codes
- Tuition plans
- Fake students/charges in production seed (tests create own fixtures)
