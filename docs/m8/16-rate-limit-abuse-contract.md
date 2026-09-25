# M8-T07 — Rate Limiting & Abuse Protection Contract

**Task:** M8-T07  
**Risk addressed:** [M-03 — Application abuse / credential stuffing surface](./09-risk-register.md) (repository scope)  
**Status:** Implemented in repository; **live** rate-limit behavior on Vercel + Supabase Cloud still requires production/staging exercise.

## Abuse-surface audit (summary)

| Tier | Examples in Olli | M8-T07 action |
|------|------------------|---------------|
| **A — sensitive / high abuse** | Sign-in, password reset, staff invite (Auth email), Owner staff lifecycle | **Enforced** (app layer + Postgres counters) |
| **B — authenticated mutation** | Finance, CRM, teaching, academic RPCs via Server Actions | **Not globally throttled** — RLS/RBAC + existing idempotency remain primary; limits would block normal bulk center work |
| **C — expensive read** | Executive / intelligence RPCs | **Not rate-limited in T07** — prefer query efficiency; no masking inefficient SQL with throttles |
| **D — ordinary read** | Lists, detail pages | No app rate limits |

### Overlaps (not replaced by rate limiting)

- Staff provisioning **idempotency keys** and processing tokens (`staff_provisioning_request`) — duplicate protection unchanged.
- Staff lifecycle **state guards** and seat invariants — authorization/lifecycle unchanged.
- Supabase Auth **platform** throttles — complementary; Olli does not expose account existence via reset rate limits.

## Enforcement architecture

```
Browser → Next.js Server Action → src/lib/rate-limit/enforce.ts (server-only)
         → Supabase service_role RPC consume_app_rate_limit
         → app_rate_limit_bucket (Postgres, atomic upsert per bucket_key)
         → underlying operation (Auth / RPC) only if allowed
```

- **Not used for production authority:** in-memory `Map`, process counters, filesystem, or per-serverless-instance state.
- **Authorization:** RLS/RBAC and Server Action gates run independently; a under-limit request without permission still fails authorization.
- **Blocked requests:** do not reveal whether the caller would otherwise have been authorized (password reset always returns the same submitted UX).

## Protected actions

| Action key | Surface | Tier | Window | Max | Fail mode |
|------------|---------|------|--------|-----|-----------|
| `auth.sign_in.ip` | `signIn` | A | 15 min | 30 | Fail-open on limiter DB error |
| `auth.sign_in.account` | `signIn` (normalized email hash) | A | 15 min | 15 | Fail-open |
| `auth.password_reset.ip` | `requestPasswordReset` | A | 1 h | 8 | **Fail-closed** (still anti-enumeration UX) |
| `auth.update_password.user` | `updatePassword` | A | 1 h | 12 | Fail-open |
| `staff.provision.org` | `provisionStaffAccount` | A | 1 h | 25 / org+actor | **Fail-closed** |
| `staff.lifecycle.org_actor` | staff lifecycle Server Actions | A | 15 min | 80 / org+actor | **Fail-closed** |
| `onboarding.complete_center_setup.user` | `completeCenterSetup` | A | 1 h | 15 / app user | Fail-open |

Policy source: `src/lib/rate-limit/policy.ts`.

## Rate-limit keys (server-built only)

- **Sign-in:** `v1:auth.sign_in.ip:{sha256(ip)}` and `v1:auth.sign_in.account:{sha256(normalized email)}`.
- **Password reset:** IP fingerprint only (never bucket by raw email in client-visible flows).
- **Staff provision / lifecycle:** `org:{uuid}:actor:{app_user uuid}` hashed into bucket subject.
- **Center setup:** `app_user:{uuid}` hashed.

### IP signal (when present)

On Vercel, the app trusts the **first** comma-separated hop in `x-forwarded-for`, else `x-real-ip`. Values are **hashed** before storage; raw IPs are not persisted in `app_rate_limit_bucket`.

## Storage & cleanup

- Table: `public.app_rate_limit_bucket` (`bucket_key`, `window_started_at`, `attempt_count`, `updated_at`).
- RPC: `consume_app_rate_limit` (service_role only), `purge_stale_app_rate_limit_buckets` (default retention 7 days).
- Grants: no `anon` / `authenticated` access to table or RPCs.

## User experience

- Localized `auth.rateLimited` and domain-specific keys under `users.*` / `onboarding.errors`.
- Password reset: rate limit → same `{ submitted: true }` response (anti-enumeration).
- Sign-in: `rate_limited` error without exposing thresholds.

## Observability

Structured `console.info` JSON: `{ category: "rate_limit", action, allowed, infrastructure_failure? }` — no passwords, tokens, or emails.

## Test / E2E accommodation

Playwright webserver sets `OLLI_RATE_LIMIT_DISABLED=1` so hundreds of fixture sign-ins are not blocked by IP buckets. Production and Vercel must **not** set this variable. Dedicated `test:rate-limit` and SQL tests still prove enforcement.

## Verification (repository)

```bash
npm run test:rate-limit          # Node smokes (9)
npm run db:verify                # includes supabase/tests/m8_t07_rate_limit_tests.sql (14)
npm run test:security
npm run verify
```

## Live / external gates (still pending)

- Real client IP forwarding on production hostname
- Concurrent abuse behavior under multi-instance Vercel
- WAF / edge limits (optional defense-in-depth)

## Deployment prerequisites

- Migration `20260929100000_m8_t07_app_rate_limiting.sql` applied (**migration count 59** after T07).
- `SUPABASE_SECRET_KEY` available to Server Actions host (existing M8-T05 contract).
