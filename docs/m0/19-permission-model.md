# M0-T04 — Permission Model

**Date:** 2026-09-14

Authorization resolves through **Permission machine codes**, never English role display names.

```text
app_user → user_role → role → role_permission → permission.code
```

Lookup: `has_permission('permission.code')` (SECURITY DEFINER helper).

Reference data migration: `20260914140100_reference_data.sql` (34 permissions, 3 observation indicators).

---

## Audit: All 34 Permission Codes

| Code | Domain | Scope | Capability | Used by RLS | App-only |
|------|--------|-------|------------|-------------|----------|
| `organization.read` | Organization | read | View own organization record | yes | |
| `organization.update` | Organization | write | Update own organization metadata | yes | |
| `permission.read` | Access control | read | Read canonical permission catalog | yes | |
| `user.read` | Access control | read | View app users in own org | yes | |
| `user.manage` | Access control | admin | Create users, assign auth mapping, change status/org | yes | |
| `role.read` | Access control | read | View roles and role-permission mappings | yes | |
| `role.manage` | Access control | admin | Create/edit roles, assign permissions, assign user roles | yes | |
| `student.create` | Academic | write | Create students | yes | |
| `student.read` | Academic | read | View students | yes | |
| `student.update` | Academic | write | Update students | yes | |
| `guardian.create` | Academic | write | Create guardians / student-guardian links | yes | |
| `guardian.read` | Academic | read | View guardians | yes | |
| `guardian.update` | Academic | write | Update guardians | yes | |
| `teacher.create` | Academic | write | Create teachers | yes | |
| `teacher.read` | Academic | read | View teachers | yes | |
| `teacher.update` | Academic | write | Update teachers | yes | |
| `enrollment.create` | Academic | write | Create courses, classes, schedules, enrollments, sessions | yes | |
| `enrollment.read` | Academic | read | Read academic structure and enrollments | yes | |
| `enrollment.update` | Academic | write | Update academic structure | yes | |
| `attendance.record` | Academic | write | Record/update attendance | yes | |
| `attendance.read` | Academic | read | View attendance | yes | |
| `assessment.create` | Learning evidence | write | Create assessments | yes | |
| `assessment.read` | Learning evidence | read | View assessments and results | yes | |
| `assessment_result.record` | Learning evidence | write | Record/update assessment results | yes | |
| `observation.record` | Learning evidence | write | Record observations and ratings | yes | |
| `observation.read` | Learning evidence | read | View observations and progress evaluations | yes | |
| `progress_evaluation.record` | Learning evidence | write | Record progress evaluations | yes | |
| `charge.create` | Finance | write | Create charges, tuition plans, adjustments | yes | |
| `charge.read` | Finance | read | View charges and related read-only finance | yes | |
| `payment.record` | Finance | write | Record payments and allocations | yes | |
| `payment.read` | Finance | read | View payments and allocations | yes | |
| `expense.create` | Finance | write | Create expense categories and expenses | yes | |
| `expense.read` | Finance | read | View cost groups, categories, expenses | yes | |
| `report.read` | Reporting | read | Reserved for future reporting endpoints | | yes (M0) |

### Observation indicators (reference, not permissions)

| Code | Domain |
|------|--------|
| `concentration` | Teacher observation rating axis |
| `engagement` | Teacher observation rating axis |
| `participation` | Teacher observation rating axis |

---

## M0-T04 Additions (5 codes)

Original M0-T03 seed had 29 permissions. M0-T04 added access-control codes required for RLS on identity/role tables:

- `permission.read`
- `user.read`, `user.manage`
- `role.read`, `role.manage`

No speculative permissions were added beyond operational need.

---

## Role-Name Independence

Dev fixture roles (`admin`, `staff`) are **test labels only**. RLS never checks `role.code` or display names. Changing role composition in the database does not require rewriting policies.

---

## Global vs Organization Scope

| Entity | Scope | Client mutation |
|--------|-------|-----------------|
| `permission` | Global reference | SELECT only (with `permission.read`); no INSERT/UPDATE/DELETE policies |
| `observation_indicator` | Global reference | SELECT only |
| `role`, `role_permission`, `user_role` | Per organization | Gated by `role.*` permissions + org boundary |

---

## Teacher Authorization

Teacher capabilities come from Permission assignments via `app_user → user_role`, **not** from `teacher.user_id = current_app_user_id()` alone. Optional teacher↔user link is for profile/convenience only in M0.
