# M0-T05 — API Security Smoke Tests

**Script:** `scripts/api-security-smoke.mjs`  
**Run:** `npm run test:api` (requires local Supabase + dev seed)

## Method

Uses the real Supabase HTTP boundary:

1. Local publishable key
2. GoTrue password sign-in → JWT
3. PostgREST requests with authenticated JWT

Secret/service credentials are used **only** in `scripts/seed-auth-users.mjs` for fixture setup — not for the six data API scenarios.

## Scenarios (6/6)

| ID | Assertion |
|----|-----------|
| API-1 | Unauthenticated publishable-key request cannot read Student |
| API-2 | Org A admin reads Org A Student |
| API-3 | Org A admin cannot read Org B Student |
| API-4 | Org A admin cannot read Org B Charge |
| API-5 | Staff without `student.create` cannot insert Student |
| API-6 | Admin with permission can PATCH own organization (rolled back) |
