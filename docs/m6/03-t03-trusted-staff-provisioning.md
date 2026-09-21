# M6-T03 — Trusted staff provisioning

Cross-system staff login provisioning: Primary Owner session → durable request → Auth Admin → transactional membership, auth link, and canonical role.

## Trusted boundary

- **Server Action:** `provisionStaffAccount` in `src/app/actions/staff-provisioning.ts`
- **Orchestration:** `src/lib/staff-provisioning/orchestrate.ts` (`import "server-only"`)
- **Admin client:** `src/lib/supabase/admin.ts` with `SUPABASE_SECRET_KEY` only on the server

No Edge Functions. No browser exposure of service credentials (`scripts/env-secrets-audit.mjs`).

## Database trust split

| Step | Caller | Function |
|------|--------|----------|
| Begin intent | `authenticated` (Owner JWT) | `begin_staff_provisioning(...)` |
| Execution claim | `authenticated` | `claim_provisioning_auth_execution(request_id)` |
| Record Auth correlation | `service_role` | `record_provisioning_auth_created(request_id, auth_user_id, processing_token)` |
| Finalize membership | `service_role` | `finalize_staff_provisioning(request_id)` |
| Compensation markers | `service_role` | `mark_provisioning_compensated`, `mark_provisioning_reconciliation_required` |

T02 `create_staff_membership_record` remains **service_role only**.

## Finalizer parameter surface

**`finalize_staff_provisioning(p_request_id uuid)` only.** Org, email, Owner, role, and `auth_user_id` are read from `staff_provisioning_request` after `auth_created_by_this_request = true`.

## Processing-token generation

**`claim_provisioning_auth_execution`** sets `processing_token = gen_random_uuid()` in PostgreSQL and returns it to the Server Action orchestrator. The browser never supplies the initial token.

## Lease policy

Fixed **`interval '5 minutes'`** via `_m6_provisioning_lease_interval()` — not client-configurable. Documented in `src/lib/staff-provisioning/constants.ts` as `PROVISIONING_LEASE_MINUTES = 5`.

If `auth_user_id` is not yet persisted but a valid lease is held, a **new claim** is allowed only when `processing_started_at` is older than **30 seconds** (crash-recovery staleness), so concurrent same-key callers still see `provisioning_pending` under an active lease.

## Auth correlation metadata

Non-secret `user_metadata.olli_provisioning_request_id = <request UUID>`. Not authorization. PostgreSQL request row is authoritative for org, Owner, role, and seat.

## Bounded reconciliation policy

Auth lookup without `auth_user_id` on the row uses paginated **`listUsers`** only (no `getUserByEmail` in `@supabase/auth-js` 2.116.0). Cap: **`MAX_AUTH_RECONCILIATION_PAGES = 5`**, **`AUTH_RECONCILIATION_PER_PAGE = 200`**. If no correlated user is found within the cap → **`reconciliation_required`** (no blind create, no email-only adoption).

## State model

```text
requested → auth_pending → auth_created → membership_pending → completed
```

Terminal/recovery: `failed`, `compensation_pending`, `compensated`, `reconciliation_required`.

## Cross-system order

1. `begin_staff_provisioning`
2. `claim_provisioning_auth_execution` (→ `auth_pending`)
3. Auth Admin invite (production) or `createUser` (local when `OLLI_STAFF_PROVISION_USE_INVITE=false`)
4. Verify metadata + email via Admin `getUserById`
5. `record_provisioning_auth_created`
6. `finalize_staff_provisioning(request_id)`
7. On membership failure after correlated Auth → Admin `deleteUser` only if metadata proves request ownership, then `mark_provisioning_compensated`

## Duplicate email policy

- Same org active member → `member_already_exists` (except same completed request)
- Same org removed → reject (T05 reactivation)
- Unrelated Auth same email → `identity_conflict`
- Auth correlated to same request → resume
- Auth linked to another `app_user` → `identity_conflict`

## T04 API contract

`provisionStaffAccount({ email, displayName, canonicalRole, idempotencyKey, preferredLocale? })` → `{ ok, appUserId?, error? }` with stable error codes in `src/lib/staff-provisioning/errors.ts`.

## Production email

Production prefers **`inviteUserByEmail`**. Repository does not configure production SMTP; deploy Supabase Auth mail separately. Local tests use Inbucket / `createUser` with confirmed email.

## Tests

- SQL: `supabase/tests/m6_t03_staff_provisioning_tests.sql` (10)
- Integration: `scripts/staff-provisioning-smoke.mjs` (same-key race, crash recovery, final-seat race, privilege denial)

## Same-key eventual convergence

Concurrent calls may return `provisioning_pending` on the loser; retry with the same idempotency key converges to one Auth user, one `app_user`, one seat, one role.
