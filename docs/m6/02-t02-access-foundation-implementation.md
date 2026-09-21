# M6-T02 — Owner, entitlement & canonical access foundation

Implementation closeout for the approved M6-T02 design (with mandatory corrections). Database and authorization foundation only; no Auth Admin provisioning, no `/users` product UI, no owner-transfer UI.

## Delivered

- **`organization_entitlement`**: `staff_limit` (default 5), `primary_owner_limit` (1), nullable `primary_app_user_id` (FK to org-scoped `app_user`).
- **`app_user.membership_status`**: `member` | `removed` (seat vs access; access remains `app_user.status`).
- **Canonical role templates** per org: `center_manager`, `accountant`, `consultant`, `academic_operations`, `teacher` — immutable to centers via REVOKE + trigger guards (`is_trusted_schema_mutation_role()`; no session GUC bypass).
- **Owner-only permissions** (`report.executive.read`, `report.executive.follow_up.manage`, `center_account.manage`): effective only when `is_primary_owner()` is true; excluded from canonical `role_permission` rows; `has_permission()` / `list_my_permissions()` special-case.
- **`is_primary_owner()`**: requires active org, active user, `membership_status = member`, match on `primary_app_user_id`.
- **Trusted-only functions** (REVOKE from `authenticated` / `anon`; `service_role` where noted): `initialize_organization_access_foundation`, `set_primary_owner_for_organization`, `create_staff_membership_record`, `_m6_apply_canonical_role_permissions`.
- **`create_staff_membership_record`**: transactional seat enforcement (entitlement `FOR UPDATE`, count, insert) — not granted to `authenticated`.
- **`assign_canonical_staff_role`**: primary owner only; staff templates only; rejects `center_manager` for non-owner targets.
- **`fetch_app_user_identity_labels`**: safe identity projection; CRM queries use this instead of broad `app_user` SELECT.
- **RLS/grants**: no authenticated `app_user` INSERT; tightened `app_user` SELECT; entitlement read for primary owner; no authenticated writes on canonical `role` / `role_permission` / `user_role`.
- **Seed**: canonical roles from org trigger; primary owner via `set_primary_owner_for_organization`; dev `admin`/`staff` product roles removed; `fixture_readonly` for legacy read smokes.
- **SQL tests**: `supabase/tests/m6_t02_access_foundation_tests.sql` (23 scenarios); wired in `scripts/supabase-verify.ps1`.

## Explicitly not in T02

- Supabase Auth Admin user creation, invitations, passwords.
- `/users` administration UI, suspension/remove UX, owner transfer UI.
- Billing / subscription provider integration.
- M6-T03 work.

## Technical debt carried forward

- `user.read` / `user.manage` may remain on legacy paths; `/users` admin must use `center_account.manage` (T04+).
- `identity.read` introduced where low-churn; full field minimization on all screens is T04/T06 scope where deferred.

## Superseded test expectations

- **M5-T01 test 1** naming still references “seed all-permissions”; executive access for org A admin is now **primary-owner-derived**, not role-graph on `center_manager`.
- **M0 security tests**: canonical role mutation expects `insufficient_privilege` (not GUC bypass).
- **M2+ SQL bootstraps**: use `test_fixture_insert_app_user` / primary owner assignment where authenticated `app_user` INSERT is revoked.
- **M6-T02 test 13**: uses disposable app user so seed staff retains teacher-only CRM denial in smokes.
- **CRM-27 smoke**: candidate names use ASCII seed student `Student A` for stable HTTP/API matching on Windows local Docker (SQL identity suite still covers Vietnamese matching).
- **M1-T08 e2e session execution**: org-a-staff is canonical **teacher** (`attendance.record`); test now expects attendance controls visible (supersedes “staff cannot mark attendance” under legacy dev `staff` role).
- **M5-T08 e2e test 7**: executive sub-routes wait for period controls / longer heading timeout (timing hardening, not permission change).
