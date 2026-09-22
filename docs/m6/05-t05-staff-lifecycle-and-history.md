# M6-T05 — Staff lifecycle, role changes & historical integrity

Implementation closeout for the approved M6-T05 design. Completes the normal staff lifecycle after T03 provisioning and T04 Owner administration. No Auth ban/disable/delete. No Owner transfer. No M6-T06 work.

## Canonical dimensions

```text
Auth identity          = app_user.auth_user_id (preserved)
Application access     = app_user.status (active | inactive | locked)
Organization membership = app_user.membership_status (member | removed)
Staff seat occupancy   = member staff excluding primary Owner
Authorization role     = effective-dated user_role
Primary ownership      = organization_entitlement.primary_app_user_id
```

`locked` is reserved for system/security lock. Owner `/users` workflows do not suspend, reactivate, or remove locked accounts (`lifecycle_conflict`).

## Lifecycle operations

| Operation | Access | Membership | Seat | Canonical role |
|-----------|--------|------------|------|----------------|
| Suspend | `active` → `inactive` | stays `member` | 0 | stays current/active |
| Reactivate | `inactive` → `active` | stays `member` | 0 | same `user_role` row |
| Remove from center | `inactive` | `removed` | −1 | current assignment ended |
| Restore | `active` | `member` | +1 | new allowed staff role |
| Change role | unchanged | must be `member` | 0 | end previous, insert new |

Primary Owner is rejected on every mutation (`target_is_primary_owner`). Soft removal never `DELETE`s `app_user` or Auth.

## Identity gate

Usable identity requires:

```text
organization.status = active
AND app_user.status = active
AND app_user.membership_status = member
```

Updated in `current_app_user_id()`, `current_organization_id()`, and `getIdentityState()`. A malformed `removed + active` row cannot resolve as an active application identity.

## Auth-layer policy

PostgreSQL application state is authoritative. T05 does not ban, disable, delete, or detach Auth identities. T03 remains the only Auth + DB cross-system machine. Removed same-email provisioning now raises `removed_member_exists`.

## Audit / history

- Role history: existing effective-dated `user_role`
- Access/membership: append-only `staff_lifecycle_event` (`suspended`, `reactivated`, `removed`, `restored`) written inside the RPC transaction
- No lifecycle history UI in T05
- Authenticated INSERT/UPDATE/DELETE on `staff_lifecycle_event` is denied

## Concurrency and idempotency

Seat/membership operations lock `organization_entitlement` then the target `app_user`. Same-state retries are success no-ops and do not write a second lifecycle event. Restore of an already-member account with a different role is `lifecycle_conflict`.

## Security

Lifecycle RPCs are executable by `authenticated` but enforce active primary Owner, same-org target (cross-org → `target_not_found`), allowed staff roles only, and valid transitions. Sensitive `app_user` fields (`status`, `membership_status`, `organization_id`, `auth_user_id`) cannot be changed by direct authenticated DML: `protect_app_user_sensitive_fields` and `protect_primary_owner_app_user` run as `SECURITY INVOKER` so DEFINER RPCs (postgres) remain trusted while PostgREST `authenticated` updates are not. Authenticated table UPDATE is limited to `preferred_locale`, `display_name`, `updated_at`, and `updated_by`.

## T06 items explicitly deferred

- Auth ban/disable as defense-in-depth
- Relink of NULL `auth_user_id`
- Owner transfer
- Automatic `teacher.status` sync
- Generalized audit platform / history viewer
- Remaining RLS inventory beyond T05 lifecycle correctness
