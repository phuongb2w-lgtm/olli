# Olli

Operational management system for an English / language center.

## Status

**M0 — CLOSED / ACCEPTED.** Product & data foundation is complete. See [M0 Closeout](./docs/m0/29-m0-closeout.md).

## Documentation

- [M0 Foundation Index](./docs/m0/README.md)
- [Architecture Baseline (ADR)](./docs/m0/30-architecture-baseline.md)
- [Web Stack](./docs/m0/23-web-stack.md)
- [Auth Application Flow](./docs/m0/24-auth-application-flow.md)
- [i18n Foundation](./docs/m0/25-i18n-foundation.md)

## Fresh Clone Bootstrap

Requires [Docker Desktop](https://www.docker.com/products/docker-desktop/) and Node.js **>= 20.9** (22 LTS recommended).

```powershell
git clone <repository-url> olli
cd olli
npm ci
npx supabase start
copy .env.example .env.local
# Set NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY from: npx supabase status
npm run verify
npm run dev
```

No manual SQL editing. No Supabase Dashboard configuration. No hidden local-only files except ignored `.env.local`.

Configuration template: [`.env.example`](./.env.example)

### Local test fixtures (development only)

These accounts exist **only** in local dev seed data. They are **not** production credentials and must never be deployed:

| Email | Password | Purpose |
|-------|----------|---------|
| `org-a-admin@olli.local` | `testpass123` | Org A admin (all permissions) |
| `org-a-staff@olli.local` | `testpass123` | Org A read-only staff |
| `unmapped@olli.local` | `testpass123` | Auth user without app_user mapping |

Production bootstrap does **not** depend on these fixtures.

## Verification

Unified foundation gate:

```powershell
npm run verify
```

Individual suites:

```powershell
npm run db:verify          # 25 + 30 + 5 + 6 SQL gates, db lint, types
npm run test:i18n          # vi/en key parity
npm run test:env           # secrets / env audit
npm run lint
npm run typecheck
npm run build
npm run test:api           # 6 HTTP/API security scenarios
npm run test:app           # 8 Playwright application scenarios
```

**Target:** 80/80 scenario tests + lint + typecheck + build + db lint.

## Scope Summary

Olli connects students, guardians, teachers, classes, enrollments, attendance, learning evidence, and finance so management can understand **business performance** and **learning/service quality**.

This is **not** an LMS — it records management evidence; it does not deliver homework, exams, or lesson content.

## License

TBD
