# Olli

Operational management system for an English / language center.

## Status

**M0 — Foundation phase.** Canonical domain model (M0-T02) and PostgreSQL data foundation (M0-T03) are documented and migration-ready. No application UI yet.

## Documentation

- [M0 Foundation Index](./docs/m0/README.md)
- [Physical Data Model](./docs/m0/13-physical-data-model.md)
- [Database Constraints](./docs/m0/14-database-constraints.md)
- [Integrity Tests](./docs/m0/16-data-integrity-tests.md)

## Database Setup

Requires [Docker Desktop](https://www.docker.com/products/docker-desktop/).

```powershell
powershell -ExecutionPolicy Bypass -File scripts/db-verify.ps1
```

This resets a local PostgreSQL 15 container, applies migrations, seeds reference data, and runs 25 integrity tests.

Configuration template: [`.env.example`](./.env.example)

## Scope Summary

Olli connects students, guardians, teachers, classes, enrollments, attendance, learning evidence, and finance so management can understand **business performance** and **learning/service quality**.

This is **not** an LMS — it records management evidence; it does not deliver homework, exams, or lesson content.

## License

TBD
