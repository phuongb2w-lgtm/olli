# M0-T06 — Public Schema Security Surface Inventory

**Generated:** 2026-09-14 14:50:39.642184+00 (from live local Supabase)

This document is the M0 security baseline for regression comparison. Any future view exposed through the Data API must undergo explicit RLS / `security_invoker` review.

## Summary

| Category | Count |
|----------|------:|
| Tables | 31 |
| Views | 1 |
| Custom functions | 16 |

## Tables (31)

| Object | RLS | FORCE RLS |
|--------|-----|-----------|
| `app_user` | yes | yes |
| `assessment` | yes | yes |
| `assessment_result` | yes | yes |
| `attendance` | yes | yes |
| `charge` | yes | yes |
| `class` | yes | yes |
| `class_schedule` | yes | yes |
| `class_teacher_assignment` | yes | yes |
| `cost_group` | yes | yes |
| `course` | yes | yes |
| `enrollment` | yes | yes |
| `expense` | yes | yes |
| `expense_category` | yes | yes |
| `financial_adjustment` | yes | yes |
| `guardian` | yes | yes |
| `observation_indicator` | yes | yes |
| `observation_rating` | yes | yes |
| `organization` | yes | yes |
| `payment` | yes | yes |
| `payment_allocation` | yes | yes |
| `permission` | yes | yes |
| `progress_evaluation` | yes | yes |
| `role` | yes | yes |
| `role_permission` | yes | yes |
| `student` | yes | yes |
| `student_guardian` | yes | yes |
| `teacher` | yes | yes |
| `teacher_observation` | yes | yes |
| `teaching_session` | yes | yes |
| `tuition_plan` | yes | yes |
| `user_role` | yes | yes |


## Views (1)

| View | security_invoker |
|------|------------------|
| `charge_balance` | true |


## Custom Functions (16)

| Function | Security | Owner | search_path | anon EXECUTE | authenticated EXECUTE |
|----------|----------|-------|-------------|--------------|----------------------|
| `current_app_user_id()` | DEFINER | postgres | public | no | yes |
| `current_organization_id()` | DEFINER | postgres | public | no | yes |
| `has_permission(p_code text)` | DEFINER | postgres | public | no | yes |
| `initialize_organization_cost_groups()` | INVOKER | postgres | — | yes | yes |
| `is_active_app_user()` | DEFINER | postgres | public | no | yes |
| `prevent_expense_category_reparent()` | INVOKER | postgres | — | yes | yes |
| `protect_app_user_sensitive_fields()` | DEFINER | postgres | public | yes | yes |
| `protect_charge_amount()` | INVOKER | postgres | — | yes | yes |
| `protect_completed_session_teacher()` | INVOKER | postgres | — | yes | yes |
| `protect_finalized_assessment_result()` | INVOKER | postgres | — | yes | yes |
| `set_own_preferred_locale(p_locale text)` | DEFINER | postgres | public | no | yes |
| `set_updated_at()` | INVOKER | postgres | — | yes | yes |
| `validate_attendance_context()` | INVOKER | postgres | — | yes | yes |
| `validate_expense_cost_group()` | INVOKER | postgres | — | yes | yes |
| `validate_payment_allocations()` | INVOKER | postgres | — | yes | yes |
| `validate_teacher_user_org()` | INVOKER | postgres | — | yes | yes |


## Exposure Rules (M0)

- **anon:** no table SELECT/INSERT/UPDATE/DELETE; helper RPC EXECUTE revoked except where noted.
- **authenticated:** DML gated by RLS; narrow helper RPC grants only.
- **Normal users:** no hard DELETE policies in M0 foundation.
- **Future views:** must set `security_invoker = true` unless explicitly reviewed otherwise.

## Regeneration

```powershell
npm run db:inventory
```

Requires local Supabase running with migrations applied.
