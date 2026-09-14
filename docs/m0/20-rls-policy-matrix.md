# M0-T04 — RLS Policy Matrix

**Date:** 2026-09-14

Canonical access-control reference for organization-owned tables exposed through Supabase Data API.

**Default posture:** RLS **ENABLED + FORCE** on all listed tables. Deny unless explicitly allowed. `anon` has **no** operational grants.

Migration: `20260914140400_rls_policies.sql`  
Helpers/grants: `20260914140300_rls_helpers_and_grants.sql`

---

## Helpers

| Function | Purpose |
|----------|---------|
| `current_app_user_id()` | Active `app_user.id` for `auth.uid()` |
| `current_organization_id()` | Trusted org from active app_user |
| `has_permission(text)` | Permission code check via role chain |
| `is_active_app_user()` | Shorthand for resolved active identity |

All are `SECURITY DEFINER` with `SET search_path = public`.

**M0-T05 amendment:** `EXECUTE` granted to `authenticated` only (not `anon`). Removed blanket `GRANT EXECUTE ON ALL FUNCTIONS`. Direct RPC is intentional for `has_permission` (UX) and identity helpers used during RLS evaluation.

---

## Grant Summary

| Role | Tables | Operations |
|------|--------|------------|
| `anon` | all public operational | **none** (REVOKE ALL) |
| `authenticated` | operational tables | SELECT, INSERT, UPDATE (no DELETE in M0) |
| `authenticated` | `charge_balance` view | SELECT only |
| `anon` | `charge_balance` view | **none** |

**M0-T05 amendment:** `charge_balance` uses `security_invoker = true` so underlying charge/payment/adjustment RLS applies. See `20260914140600_m0_t05_security_hardening.sql`.

DELETE policies are intentionally omitted in M0; historical truth prefers status transitions and constraints over hard deletes.

---

## Matrix (Exposed Tables)

Legend: **Org** = `organization_id = current_organization_id()` and `is_active_app_user()`.

| Table | RLS | anon | auth grant | SELECT | INSERT | UPDATE | Permission(s) | Org rule |
|-------|-----|------|------------|--------|--------|--------|---------------|----------|
| `organization` | ✓ | ✗ | S,U | same org | — | same org | `organization.read` / `.update` | own org only |
| `app_user` | ✓ | ✗ | S,I,U | self or `user.read` | `user.manage` | self* or `user.manage` | `user.*` | same org; trigger guards sensitive fields |
| `role` | ✓ | ✗ | S,I,U | `role.read` | `role.manage` | `role.manage` | `role.*` | same org |
| `role_permission` | ✓ | ✗ | S,I,U | `role.read` | `role.manage` | `role.manage` | `role.*` | role must belong to same org |
| `user_role` | ✓ | ✗ | S,I,U | self or `role.read` | `role.manage` | `role.manage` | `role.*` | same org |
| `permission` | ✓ | ✗ | S | `permission.read` | — | — | read-only catalog | global |
| `observation_indicator` | ✓ | ✗ | S | `observation.read` | — | — | read-only catalog | global |
| `student` | ✓ | ✗ | S,I,U | `student.read` | `student.create` | `student.update` | student.* | Org |
| `guardian` | ✓ | ✗ | S,I,U | `guardian.read` | `guardian.create` | `guardian.update` | guardian.* | Org |
| `student_guardian` | ✓ | ✗ | S,I,U | `guardian.read` | `guardian.create` | `guardian.update` | guardian.* | Org |
| `teacher` | ✓ | ✗ | S,I,U | `teacher.read` | `teacher.create` | `teacher.update` | teacher.* | Org |
| `course` | ✓ | ✗ | S,I,U | `enrollment.read` | `enrollment.create` | `enrollment.update` | enrollment.* | Org |
| `class` | ✓ | ✗ | S,I,U | `enrollment.read` | `enrollment.create` | `enrollment.update` | enrollment.* | Org |
| `class_schedule` | ✓ | ✗ | S,I,U | `enrollment.read` | `enrollment.create` | `enrollment.update` | enrollment.* | Org |
| `enrollment` | ✓ | ✗ | S,I,U | `enrollment.read` | `enrollment.create` | `enrollment.update` | enrollment.* | Org |
| `class_teacher_assignment` | ✓ | ✗ | S,I,U | `enrollment.read` | `enrollment.create` | `enrollment.update` | enrollment.* | Org |
| `teaching_session` | ✓ | ✗ | S,I,U | `enrollment.read` | `enrollment.create` | `enrollment.update` | enrollment.* | Org + M0-T03 triggers |
| `attendance` | ✓ | ✗ | S,I,U | `attendance.read` | `attendance.record` | `attendance.record` | attendance.* | Org |
| `assessment` | ✓ | ✗ | S,I,U | `assessment.read` | `assessment.create` | `assessment.create` | assessment.* | Org |
| `assessment_result` | ✓ | ✗ | S,I,U | `assessment.read` | `assessment_result.record` | same | result.record | Org + finalized trigger |
| `teacher_observation` | ✓ | ✗ | S,I,U | `observation.read` | `observation.record` | same | observation.* | Org |
| `observation_rating` | ✓ | ✗ | S,I,U | `observation.read` | `observation.record` | same | observation.* | Org + parent observation org check |
| `progress_evaluation` | ✓ | ✗ | S,I,U | `observation.read` | `progress_evaluation.record` | same | progress.* | Org |
| `tuition_plan` | ✓ | ✗ | S,I,U | `charge.read` | `charge.create` | `charge.create` | charge.* | Org |
| `charge` | ✓ | ✗ | S,I,U | `charge.read` | `charge.create` | `charge.create` | charge.* | Org + amount immutability trigger |
| `financial_adjustment` | ✓ | ✗ | S,I,U | `charge.read` | `charge.create` | `charge.create` | charge.* | Org |
| `payment` | ✓ | ✗ | S,I,U | `payment.read` | `payment.record` | same | payment.* | Org |
| `payment_allocation` | ✓ | ✗ | S,I,U | `payment.read` | `payment.record` | same | payment.* | Org |
| `cost_group` | ✓ | ✗ | S | `expense.read` | — | — | expense.read | Org (read-only via API) |
| `expense_category` | ✓ | ✗ | S,I,U | `expense.read` | `expense.create` | `expense.create` | expense.* | Org |
| `expense` | ✓ | ✗ | S,I,U | `expense.read` | `expense.create` | `expense.create` | expense.* | Org + category/group triggers |

\* Self-update on `app_user` excludes sensitive fields (see doc 18).

---

## Layered Security

RLS complements (does not replace) M0-T03 integrity:

- Composite FKs prevent cross-org relational inconsistency
- Triggers enforce finalized assessment results, completed session teacher, charge amount immutability, payment allocation totals, expense/category alignment

Security tests verify both layers under `authenticated` role with JWT context.

---

## Service Role

Supabase `service_role` bypasses RLS. **Never** embed service-role secrets in client code or committed env files. Administrative operations belong in trusted server contexts only.
