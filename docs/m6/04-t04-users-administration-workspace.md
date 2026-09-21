# M6-T04 — Owner `/users` administration workspace

Primary Owner workspace for center account administration: roster, seat usage, and trusted staff provisioning.

## Route authorization

| Surface | Rule |
|---------|------|
| `/users` page | `can("center_account.manage")` → `has_permission` + `is_primary_owner()` |
| Sidebar nav | `APP_NAV_ITEMS.users.anyOf = ["center_account.manage"]` |
| Read model RPC | `fetch_center_account_administration()` raises `permission_denied` unless `is_primary_owner()` |
| Create staff | `provisionStaffAccount` → T03 `begin_staff_provisioning` (Owner-only) |

Legacy `user.read` / `user.manage` **do not** gate `/users`.

## Account read model

**RPC:** `fetch_center_account_administration()` (`supabase/migrations/20260924100000_m6_t04_center_account_administration.sql`)

**Server wrapper:** `src/lib/center-accounts/fetch-center-account-administration.ts`

Returns:

- `staff_limit`, `staff_seats_used` (authoritative DB semantics)
- `primary_owner` — identity summary (no Auth ids)
- `staff` — member roster excluding primary Owner

Does **not** return Auth metadata, provisioning tokens, or permission graphs.

## Seat semantics

`staff_seats_used = count_member_staff_seats(organization_id)`:

- Includes `membership_status = member` staff excluding primary Owner
- `active`, `inactive`, and `locked` access all occupy a seat
- `removed` does not occupy a seat and is omitted from the default staff list

UI reads limits from RPC; does not hardcode seat caps.

## Primary Owner presentation

Dedicated summary card labeled **Primary Owner** / **Chủ sở hữu chính**. Not listed as an editable staff row. No T05 lifecycle actions.

## Staff provisioning UX

**Form:** `src/components/users/provision-staff-form.tsx`  
**Action:** `provisionStaffAccount` only (T03 opaque).

Fields: email, display name, canonical staff role (`accountant` | `consultant` | `academic_operations` | `teacher`), preferred locale. No password.

## Idempotency key lifetime

One logical create attempt uses one `crypto.randomUUID()` from first submit until:

- terminal success (key cleared, form reset), or
- explicit **Start a new request** after terminal/support errors.

Key stored in React state (survives rerenders and `useTransition`). Exposed to tests via `data-testid="provision-idempotency-key"`.

## Immutable payload while unresolved

On first submit, email / display name / role / locale are copied to `lockedPayload` and fields are disabled until:

- success,
- terminal/support error + **Start a new request**, or
- retryable completion.

Retries (including `provisioning_pending`) resubmit the **same** payload with the **same** key.

## Error UX

Mapping: `src/lib/staff-provisioning/provision-error-ux.ts` + `users.provision.errors.*` i18n.

| Class | Behavior |
|-------|----------|
| Retry | `provisioning_pending`, `auth_provisioning_failed`, `membership_provisioning_failed`, `compensation_pending`, `unknown` — **Continue setup** |
| Terminal | validation, seat limit, duplicates, conflicts — **Start a new request** |
| Support | `reconciliation_required` — safe support wording, no retry loop |

Success copy: account created / invitation **initiated** — not login or guaranteed email delivery.

## T05 boundary

T04 displays access/membership state only. No suspend, reactivate, remove, role change, or Owner transfer UI.

## Tests

- SQL: `supabase/tests/m6_t04_center_account_administration_tests.sql` (10)
- E2E: `tests/e2e/m6-users-administration.spec.ts`
- Dev fixtures: `m6-t04-*@olli.local` canonical non-Owner roles in `supabase/seed.sql` (test-only block)
