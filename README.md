# Olli

Operational management system for an English / language center.

## Status

**M0 — Foundation phase.** Domain model (M0-T02), PostgreSQL schema (M0-T03), Auth/RLS (M0-T04), and bilingual web application bootstrap (M0-T05) are implemented and verified locally.

## Documentation

- [M0 Foundation Index](./docs/m0/README.md)
- [Web Stack](./docs/m0/23-web-stack.md)
- [Auth Application Flow](./docs/m0/24-auth-application-flow.md)
- [i18n Foundation](./docs/m0/25-i18n-foundation.md)

## Local Setup

Requires [Docker Desktop](https://www.docker.com/products/docker-desktop/) and Node.js **>= 20.9** (22 LTS recommended).

```powershell
npm ci
npx supabase start
npm run db:verify          # 25 + 30 + 5 SQL gates, types
cp .env.example .env.local # then set publishable key from: npx supabase status
npm run dev
```

Configuration template: [`.env.example`](./.env.example)

### Verification pipeline

```powershell
npm ci
npm run db:verify          # Supabase: integrity + security + charge_balance + types
npm run lint
npm run typecheck
npm run build
npm run test:api           # 6 HTTP/API security scenarios
npm run test:app           # 8 Playwright application scenarios (requires running app)
```

Dev sign-in (local fixtures): `org-a-admin@olli.local` / `testpass123`

## Scope Summary

Olli connects students, guardians, teachers, classes, enrollments, attendance, learning evidence, and finance so management can understand **business performance** and **learning/service quality**.

This is **not** an LMS — it records management evidence; it does not deliver homework, exams, or lesson content.

## License

TBD
