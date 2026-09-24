# M8 — Observability Contract

**T01 state:** No Sentry, Datadog, OpenTelemetry, or structured logging library in application code. Failures surface as Next.js server logs and Supabase Dashboard logs only.

## Minimum production monitoring (target)

| Signal | Source | Alert threshold (initial) |
|--------|--------|---------------------------|
| **App availability** | HTTP GET health endpoint (M8-T07) | 2 consecutive failures / 5 min |
| **5xx rate** | Host platform metrics | Above baseline |
| **Auth sign-in failures** | Supabase Auth logs | Spike vs 24h median |
| **PostgREST / RPC errors** | Supabase API logs | Sustained 5xx or policy errors |
| **Migration apply failure** | Deploy pipeline | Any failure = page |
| **Database connectivity** | Health check queries `select 1` via publishable or server ping | Failure |

## Application errors

| Layer | Current | Target |
|-------|---------|--------|
| Server Actions | Thrown errors → Next default handling | M8-T07 — consistent log shape (request id, org id if known, action name); no stack traces to client |
| Client | Generic error states in forms | Preserve; no sensitive leakage |
| Provisioning | `ok: false` + code string | Log server-side with `requestId` |

## Sensitive error leakage

- Product already maps auth errors to coarse codes (`invalid_credentials`, `network`).
- **Do not** expose `SUPABASE_SECRET_KEY`, raw PostgREST bodies, or SQL detail to browsers in M8 hardening.

## Deployment health checks

Post-deploy (see runbook):

1. `GET /login` — 200
2. Health route (to add) — DB reachable
3. Optional: remote `npm run test:api` against staging with service credentials in CI

## Log retention

- **App host:** per provider default (7–30 days).
- **Supabase:** per plan.
- **Operator actions** (provision center, activate subscription): recommend append-only ops log spreadsheet until operator UI exists (M8-T08).

## Gap register

| Gap | M8 task |
|-----|---------|
| No `/health` or `/api/health` | M8-T07 |
| No error reporting SaaS | M8-T07 (choose one vendor or host-native) |
| No auth failure dashboard | M8-T07 Supabase + optional export |
| CI does not alert on verify failure beyond GitHub email | M8-T09 |
