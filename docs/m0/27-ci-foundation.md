# M0-T05 — CI Foundation

**Workflow:** `.github/workflows/foundation-ci.yml`

## Triggers

- Push to `main`
- Pull requests targeting `main`

## Steps

1. `npm ci`
2. Start local Supabase
3. `supabase db reset`
4. `node scripts/seed-auth-users.mjs`
5. Apply `supabase/seed.sql`
6. SQL gates: 25 integrity + 30 security + 5 charge_balance
7. `npm run db:types`
8. `npm run lint`
9. `npm run typecheck`
10. `npm run build`
11. `npm run test:api`
12. Playwright application smoke (8)

No production credentials. Local Supabase only.
