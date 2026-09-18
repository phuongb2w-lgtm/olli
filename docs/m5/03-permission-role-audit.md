# M5-T01 — Permission & Role Audit

## Implementation model

- **52+ permission codes** in `permission` table (M0–M4 + M5 additions)
- **Roles** are org-scoped labels composing permissions via `role_permission`
- **RLS / RPC** call `has_permission(code)` — never role names
- **Dev seed roles:** `admin`, `staff`, `student_reader`, `no_student` (not product role names)

## M5 additions (T01)

| Code | Purpose |
|------|---------|
| `report.executive.read` | Center-wide executive / management intelligence |
| `consultant_revenue.declare` | Consultant Declare Revenue |
| `consultant_revenue.review` | Accountant review (Approve / Reject / Return) |

Existing `report.read` remains a placeholder; executive boundary uses `report.executive.read`.

## Mapping: canonical role → permissions

See `src/lib/workspaces/role-contracts.ts` for machine-readable bundles.

### Center Manager

Uses full permission composition. Minimum distinguishing permission: `report.executive.read`. Dev `admin` role receives all permissions including M5 additions.

### Accountant

Finance domain: `charge.*`, `payment.*`, `payment.reverse`, `expense.*`, `asset.*`, `revenue.*`, `personnel_cost.*`, `class_economics.read`, `cost_allocation.manage` (optional), `consultant_revenue.review`.

Does **not** automatically receive `report.executive.read`.

### Consultant

`lead.read`, `lead.create`, `lead.update`, `lead.assign`, `lead.convert`, `consultant_revenue.declare`. Optional: not `lead.manage_sources` unless also manager.

Personal data scoped by `consultant_user_id` on declarations and lead ownership.

### Academic Operations

`student.*`, `guardian.*`, `teacher.read`, `enrollment.*`, read access to attendance/assessment/observation. Session mutations via `enrollment.update`.

### Teacher

`attendance.record`, `attendance.read`, `assessment.read`, `assessment_result.record`, `observation.record`, `observation.read`, `enrollment.read` (session context).

## Seed role mapping (dev fixtures)

| Seed role | Nearest canonical role | Notes |
|-----------|------------------------|-------|
| `admin` | Center Manager | All permissions |
| `staff` | Mixed read-only | Not a product role; cross-domain reads without write |
| `student_reader` | Partial | Student list only |
| `no_student` | None operational | Org read only |

## Gaps identified (T01)

1. No production seed roles named Teacher / Consultant / Accountant — centers configure via Manager UI (future).
2. Academic confirmation workflow not yet modeled — teacher data is canonical immediately.
3. `progress_evaluation.record` permission unused in application UI.
4. User management UI is foundation placeholder at `/users`.

## Protected routes (representative)

| Route | Permission gate |
|-------|-----------------|
| `/executive` | `report.executive.read` |
| `/finance/*` | Finance read permissions (layout) |
| `/crm/*` | `lead.read` (layout partial) |
| `/operations/*` | `enrollment.read` |
| `/students/*` | `student.read` |
| `/users` | `user.read` / `user.manage` |
| `/settings` | `organization.update`, `role.read`, or `lead.manage_sources` |

Navigation visibility uses `list_my_permissions()` + `APP_NAV_ITEMS` filter; routes enforce independently.
