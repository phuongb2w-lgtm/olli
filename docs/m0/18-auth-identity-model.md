# M0-T04 — Auth Identity Model

**Date:** 2026-09-14

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
3. **Application access gate** — when `auth_user_id` is NULL or `app_user.status != 'active'`, RLS helpers return no organization context.

---

## Auth Deletion Semantics

When `auth.users` row is deleted:

| Preserved | Blocked |
|-----------|---------|
| `app_user` row | Login / `auth.uid()` resolution |
| Historical `created_by` / `updated_by` | Operational SELECT/INSERT/UPDATE via RLS |
| Financial transactions | New sessions for that identity |
| Teacher business records | |
| Role assignment history | |

**Chosen behavior:** `ON DELETE SET NULL` on `auth_user_id`. Application access becomes impossible; Olli identity and audit trail remain intact.

**Do not** cascade-delete business history from Auth events.

---

## Organization Context (Trusted)

For M0, each `app_user` belongs to **one** organization. Active organization is derived only from database state:

```text
auth.uid()
  → app_user.auth_user_id
  → app_user.organization_id   (status = 'active')
```

Implemented in `current_organization_id()` (SECURITY DEFINER, fixed `search_path`).

**Never trust** client-supplied `organization_id` (forms, URL, local storage, JWT custom claims) for authorization.

---

## Sensitive Field Protection

`protect_app_user_sensitive_fields` trigger blocks changes to `organization_id`, `auth_user_id`, and `status` unless caller has `user.manage` permission (or `olli.bypass_app_user_guard` is set for bootstrap/tests).

Ordinary users may update safe profile fields on their own row per RLS policy.

---

## Test Identities (Local Dev Only)

Fixture domain: `@olli.local` — **never use real personal emails.**

| Auth UUID | App user | Org | Role fixture |
|-----------|----------|-----|--------------|
| `a1111111-…` | Org A Admin | A | admin (all permissions) |
| `a2222222-…` | Org A Staff | A | staff (read-only subset) |
| `b1111111-…` | Org B Admin | B | admin |
| `b2222222-…` | Org B Staff | B | staff |
| `c1111111-…` | *(unmapped)* | — | no app_user |
| `a3333333-…` | Disabled User | A | inactive status |

Defined in `supabase/seed.sql` (development only).
