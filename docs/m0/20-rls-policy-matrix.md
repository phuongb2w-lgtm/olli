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
| `current_app_user_id()` | Usable `app_user.id` for `auth.uid()` (M6-T05: active org, `status = active`, `membership_status = member`) |
| `current_organization_id()` | Trusted org from usable identity |
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
| `app_user` | ✓ | ✗ | **S**; **UPDATE** limited columns† | self or **`is_primary_owner()`** | **Revoked** | self† or `user.manage`‡ | — | same org; sensitive fields via RPC only |
| `role` | ✓ | ✗ | **S only** (M6-T02) | `role.read` | **Revoked** | **Revoked** | `role.read` | same org |
| `role_permission` | ✓ | ✗ | **S only** | `role.read` | **Revoked** | **Revoked** | `role.read` | role in same org |
| `user_role` | ✓ | ✗ | **S only** | self or `role.read` | **Revoked** | **Revoked** | `role.read` | assignments via RPC |
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

† **M6-T05 `app_user` UPDATE grant:** `preferred_locale`, `display_name`, `updated_at`, `updated_by` only.
‡ Legacy `user.manage` RLS path; canonical templates exclude it. Sensitive columns blocked by trigger regardless.

**Historical:** Pre-M6 matrix listed `user.read` on `app_user` SELECT. Live policy uses Owner/self (M6-T02). `user.read` in the permission catalog is legacy/orphan.

---

## M6 — Identity & center administration (current)

Legend unchanged. Migrations: `20260922100000_m6_t02_*`, `20260923100000_m6_t03_*`, `20260925100000_m6_t05_*`.

| Table | RLS FORCE | authenticated GRANT | SELECT | INSERT/UPDATE/DELETE | Notes |
|-------|-----------|---------------------|--------|----------------------|-------|
| `organization_entitlement` | ✓ | S | **`is_primary_owner()`** + Org | none | Seat limit / primary Owner pointer |
| `staff_provisioning_request` | ✓ | S | **`is_primary_owner()`** + Org | none (RPC + `service_role`) | T03 pipeline state |
| `staff_lifecycle_event` | ✓ | S | **`is_primary_owner()`** + Org | **none** | Append-only via lifecycle RPCs |

**Lifecycle / role graph writes (authenticated EXECUTE, DEFINER authorization):**

- `suspend_staff_member`, `reactivate_staff_member`, `remove_staff_from_center`, `restore_removed_staff`
- `assign_canonical_staff_role`
- `begin_staff_provisioning`, `claim_provisioning_auth_execution`
- `fetch_center_account_administration` (Owner read model including `removed_staff`)

**service_role only (no authenticated EXECUTE):** `finalize_staff_provisioning`, `record_provisioning_auth_created`, compensation markers, `set_primary_owner_for_organization`, `create_staff_membership_record`, internal `_m6_*` helpers.

---

## Layered Security

RLS complements (does not replace) M0-T03 integrity:

- Composite FKs prevent cross-org relational inconsistency
- Triggers enforce finalized assessment results, completed session teacher, charge amount immutability, payment allocation totals, expense/category alignment

Security tests verify both layers under `authenticated` role with JWT context.

---

## Service Role

Supabase `service_role` bypasses RLS. **Never** embed service-role secrets in client code or committed env files. Administrative operations belong in trusted server contexts only.
