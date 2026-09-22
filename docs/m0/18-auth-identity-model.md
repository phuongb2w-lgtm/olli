# M0-T04 — Auth Identity Model

**Date:** 2026-09-14
**M6-T05 / M6-T06:** Usable application identity and sensitive-field rules below reflect the current canonical model.

Supabase Auth identity and Olli application identity are related but **not the same business concept**.

---

## Canonical Chain

```text
auth.users
    ↓  (optional, unique)
app_user.auth_user_id
    ↓
app_user.id          ← stable Olli domain PK
    ↓ optional
teacher.user_id      ← business entity, not Auth
```

**Not in M0 Auth scope:** Student, Guardian (no portal auth yet).

---

## Mapping Column

| Column | Type | Constraint | Behavior |
|--------|------|------------|----------|
| `app_user.auth_user_id` | `uuid` | `UNIQUE`, FK → `auth.users(id)` | `ON DELETE SET NULL` |

Migration: `20260914140200_auth_identity.sql`

### Why separate IDs?

1. **Stable references** — sessions, charges, audit columns reference `app_user.id`, not Auth lifecycle.
2. **Auth lifecycle isolation** — removing a Supabase Auth account must not delete business history.
3. **Application access gate** — when identity is not *usable* (see below), RLS helpers return no organization context.

---

## Usable application identity (current)

A JWT may still map to an `app_user` row while the **application** treats the session as non-operational. Usable identity requires **all** of:

```text
organization.status = 'active'
AND app_user.status = 'active'
AND app_user.membership_status = 'member'
```

Implemented in `current_app_user_id()` and `current_organization_id()` (M6-T05, SECURITY DEFINER, `SET search_path = public`).

**Never trust** client-supplied `organization_id` for authorization.

The Next.js gate `getIdentityState()` applies the same usable-identity rule for UX routing.

### Auth vs application access

| State | Auth account | Application access |
|-------|--------------|-------------------|
| Suspended staff (`inactive`, `member`) | May still exist | **Denied** — helpers NULL |
| Removed from center (`removed`, any status) | May still exist | **Denied** |
| Malformed `removed` + `active` | May still exist | **Denied** — membership in gate |

Staff lifecycle mutations (suspend, remove, restore, role change) use **trusted SECURITY DEFINER RPCs** (M6-T05), not direct PostgREST updates to sensitive columns.

---

## Auth Deletion Semantics

When `auth.users` row is deleted:

| Preserved | Blocked |
|-----------|---------|
| `app_user` row | Login / usable identity |
| Historical `created_by` / `updated_by` | Operational SELECT/INSERT/UPDATE via RLS |
| Financial transactions | New sessions for that identity |
| Teacher business records | |
| Role assignment history | |

**Chosen behavior:** `ON DELETE SET NULL` on `auth_user_id`. Application access becomes impossible; Olli identity and audit trail remain intact.

**Do not** cascade-delete business history from Auth events.

---

## Organization Context (Trusted)

For M0–M6, each `app_user` belongs to **one** organization. Organization context is derived only from **usable** identity (see above).

**Never trust** client-supplied `organization_id` (forms, URL, local storage, JWT custom claims) for authorization.

---

## Sensitive Field Protection (current)

`protect_app_user_sensitive_fields` and `protect_primary_owner_app_user` are **`SECURITY INVOKER`** triggers (M6-T05).

Authenticated PostgREST callers **cannot** change:

- `organization_id`
- `auth_user_id`
- `status`
- `membership_status`

Changes to those fields occur only through **trusted paths** (e.g. lifecycle RPCs running as the function owner, where `is_trusted_schema_mutation_role()` applies).

**Historical note:** Early M0 used `user.manage` and `olli.bypass_app_user_guard` on an older trigger shape. Those bypasses are **not** part of the live model after M6-T05.

### Column-limited self-service UPDATE

`authenticated` may `UPDATE` only on `app_user`: `preferred_locale`, `display_name`, `updated_at`, `updated_by` (plus RLS: own row or legacy `user.manage` path on non-sensitive columns — centers normally use profile fields only).

---

## Test Identities (Local Dev Only)

Fixture domain: `@olli.local` — **never use real personal emails.**

| Auth UUID | App user | Org | Role fixture |
|-----------|----------|-----|--------------|
| `a1111111-…` | Org A Admin (primary Owner) | A | `center_manager` canonical |
| `a2222222-…` | Org A Staff | A | canonical staff template |
| `b1111111-…` | Org B Admin (primary Owner) | B | `center_manager` canonical |
| `b2222222-…` | Org B Staff | B | canonical staff template |
| `c1111111-…` | *(unmapped)* | — | no app_user |
| `a3333333-…` | Disabled User | A | inactive status |

Defined in `supabase/seed.sql` (development only).

---

## Permission catalog note

`user.read` remains in the global permission catalog but is **not** used by live `app_user` RLS after M6-T02 (Owner/self model + `identity.read` projection RPC). Treat as legacy/orphan for documentation; do not use for new features.
