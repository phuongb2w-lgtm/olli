# M0 — Architecture Decision Record (Baseline)

**Status:** Accepted at M0 closeout  
**Audience:** Onboarding reference for M1+ development

---

## Product

Olli is an **operational management system** for an English / language center. It is **not an LMS**. It records management evidence (attendance, assessments, observations, finance) — it does not deliver homework, exams, or lesson content.

---

## Web Application

| Decision | Choice |
|----------|--------|
| Framework | Next.js 16 App Router |
| Language | TypeScript |
| Repository | Single monorepo |
| Auth transport | Supabase Auth (JWT) via `@supabase/ssr` |
| Server mutations | Server Actions (narrowly scoped) |
| Styling | Tailwind CSS 4 |

---

## Database

| Decision | Choice |
|----------|--------|
| Engine | PostgreSQL 15 via Supabase |
| Schema ownership | SQL migrations in `supabase/migrations/` |
| Types | Generated `types/database.generated.ts` (never hand-edited) |
| Tenant key | `organization_id` on all operational tables |

**Canonical types workflow:**

```
migration → db reset → verification → regenerate types → typecheck → build
```

---

## Identity

| Concept | Rule |
|---------|------|
| `auth.users` | Supabase Auth identity (sign-in boundary) |
| `app_user` | Stable Olli application identity |
| Mapping | Optional `app_user.auth_user_id → auth.users.id` |
| Teacher | Separate entity; optional `teacher.user_id` link for profile only |

Auth identity and application identity are **deliberately separate**. Removing an Auth mapping must not delete historical `app_user` records.

---

## Authorization

| Rule | Detail |
|------|--------|
| Mechanism | Permission **machine codes** (`student.read`, etc.) |
| Enforcement | PostgreSQL RLS policies calling `has_permission()` |
| Role labels | Display/test labels only — **never authoritative** |
| Helper functions | `current_app_user_id()`, `current_organization_id()`, `has_permission()`, `is_active_app_user()` |

See [19-permission-model.md](./19-permission-model.md) for the canonical 34-permission registry.

---

## Tenant Isolation

- Every operational row is scoped by `organization_id`.
- Composite FK patterns prevent cross-org references.
- RLS derives org context from `auth.uid() → app_user`, never from client input.
- No function accepts arbitrary tenant/org ID from the client for authorization.

---

## Learning Evidence

Management evidence only: attendance, assessments, teacher observations, progress evaluations. No content delivery, no student homework workflow in M0.

---

## Finance

| Decision | Detail |
|----------|--------|
| Debt source | `charge` table only |
| Payment allocation | N:M via `payment_allocation` |
| Adjustments | Append-oriented `financial_adjustment` history |
| No Receivable table | Outstanding balance derived via `charge_balance` view |
| No InvoiceLine table | Charges carry line semantics directly |
| Money storage | `numeric` in database; locale-specific presentation via `Intl` |

---

## Cost B

Exactly **two structural group slots** per organization (`cost_group` with slot 1 and 2). Business labels and codes are an **open business decision** — no guessed names in M0.

---

## Internationalization

| Rule | Detail |
|------|--------|
| Locales | `vi` + `en` first-class |
| Machine codes | Stored in DB; never identified through translated text |
| URL strategy | No `/vi/` or `/en/` path prefixes |
| Locale precedence (authenticated) | `app_user.preferred_locale → organization.default_locale → cookie → vi` |
| Locale precedence (login) | cookie → vi |
| Persistence | `set_own_preferred_locale()` RPC + cookie; no service credential |
| Formatting | Shared `Intl` helpers in `src/lib/formatting/index.ts` |

---

## History & Mutability

Historical facts are **never silently overwritten** by current master state. Domains use status transitions, archive, or reversal/correction — not hard DELETE. Normal application users receive **no hard DELETE capability** in M0.

---

## Views & Data API

Any view exposed through PostgREST must:

1. Set `security_invoker = true` (unless explicitly reviewed otherwise)
2. Undergo RLS review against underlying tables
3. Revoke `anon` SELECT

`charge_balance` is the M0 reference implementation.

---

## Security-Definer Functions

All custom SECURITY DEFINER functions require:

- Fixed `search_path = public`
- No arbitrary SQL execution
- No client-supplied tenant/user ID for authorization scope
- Explicit EXECUTE grants (authenticated only where intended; anon revoked)

See [32-security-surface-inventory.md](./32-security-surface-inventory.md) for the live inventory.

---

## Testing Baseline (M0 closeout)

| Suite | Scenarios |
|-------|----------:|
| Domain integrity | 25 |
| RLS security | 30 |
| charge_balance | 5 |
| Data API security | 6 |
| Application smoke | 8 |
| Locale persistence | 6 |
| **Total** | **80** |

Unified command: `npm run verify`
