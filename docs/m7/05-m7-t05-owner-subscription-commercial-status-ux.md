# M7-T05 — Owner Subscription / Commercial Status UX

## Scope

Owner-only subscription and commercial status surface built on authoritative M7-T03/T04 contracts. No new commercial lifecycle semantics, payment flows, or operator mutations in the UI.

## Authoritative read

- RPC: `fetch_owner_commercial_status()` (primary Owner / operational owner per T04).
- Staff seat **used** count: `count_member_staff_seats` via RPC payload.
- Staff seat **limit**: `organization_entitlement.staff_limit` via RPC payload.
- **Remaining** seats: display-only difference in UI (`limit - used`), not a separate entitlement source.

## Routes

| Route | Audience | Shell |
|-------|----------|--------|
| `/subscription` | Primary Owner with normal commercial access | Protected (`AppShell`) |
| `/subscription-status` | Primary Owner while commercially restricted | Restricted |

Non-owners receive localized denial on `/subscription` (UX guard + RPC `permission_denied`).

## Navigation

Sidebar item **Subscription** (`/subscription`) visible when `center_account.manage` is granted (primary Owner only in product).

## i18n

All copy under `commercial.*` and `shell.subscription` in EN/VI.

## Verification

- SQL: `supabase/tests/m7_t05_owner_subscription_status_ux_tests.sql` (6 cases)
- E2E: `tests/e2e/m7-owner-subscription.spec.ts`
- Regressions: M7-T04 commercial access E2E, M6 `/users`, full `npm run verify`

## Non-goals (T05)

Checkout, invoices, card vault, self-service activate/suspend/cancel/plan change, pricing pages.
