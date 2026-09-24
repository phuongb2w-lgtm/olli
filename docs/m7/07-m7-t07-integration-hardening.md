# M7-T07 — Integration & production hardening

## Scope

Cross-task integration of M7-T02–T06: state consistency, landing-path hardening, restricted-route onboarding guard, regression coverage, and milestone-level documentation.

## Changes (T07)

### Routing

- **Restricted layout** now calls `fetch_session_commercial_access` and redirects Primary Owners with `requires_center_setup` to `/onboarding`, preventing bypass via `/subscription-status` while provisioning/setup is pending.
- **`sessionRequiresOnboardingRedirect()`** extracted alongside `resolveAuthenticatedLandingPath()` for shared UX semantics.

### Verification

- SQL: `supabase/tests/m7_t07_commercialization_integration_tests.sql` (10 cross-domain cases).
- E2E: `tests/e2e/m7-commercialization-integration.spec.ts` (4 integration flows).
- Smoke: `scripts/subscription-commercial-smoke.mjs` asserts new centers have `setup_completed_at` NULL after provisioning.

### Documentation

- [06 — Commercialization milestone contract](./06-m7-commercialization-milestone-contract.md)

## Non-goals (unchanged)

No payment, checkout, operator console, or settings profile editor.

## Regression

Full `npm run verify` including all M7 SQL suites and Playwright (212+ tests).
