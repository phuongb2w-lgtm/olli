# Olli

Operational management system for an English / language center.

## Status

**M0 — Foundation phase.** Domain model (M0-T02), PostgreSQL schema (M0-T03), and Auth/RLS security foundation (M0-T04) are implemented and verified locally. No application UI yet.

## Documentation

- [M0 Foundation Index](./docs/m0/README.md)
- [Auth Identity Model](./docs/m0/18-auth-identity-model.md)
- [Permission Model](./docs/m0/19-permission-model.md)
- [RLS Policy Matrix](./docs/m0/20-rls-policy-matrix.md)
- [Security Tests](./docs/m0/21-security-tests.md)

## Database Setup

Requires [Docker Desktop](https://www.docker.com/products/docker-desktop/).

```powershell
npm install

# Generic PostgreSQL (schema + 25 integrity tests)
npm run db:verify:postgres

# Local Supabase stack (25 integrity + 30 security tests)
npm run db:verify:supabase
```

Configuration template: [`.env.example`](./.env.example)

Regenerate TypeScript types after schema changes:

```powershell
npm run db:types
```

Output: [`types/database.generated.ts`](./types/database.generated.ts) (do not hand-edit).

## Scope Summary

Olli connects students, guardians, teachers, classes, enrollments, attendance, learning evidence, and finance so management can understand **business performance** and **learning/service quality**.

This is **not** an LMS — it records management evidence; it does not deliver homework, exams, or lesson content.

## License

TBD
