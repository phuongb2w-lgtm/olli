# M0-T01 — Repository Audit

**Task:** M0-T01 Product Contract & Foundation Audit  
**Date:** 2026-09-14  
**Status:** Complete (greenfield baseline)

---

## Executive Summary

The repository at `D:\Olli` is a **greenfield project**. No application source code, configuration, database schema, tests, or runtime dependencies exist yet. Only default Git hook samples are present under `.git/hooks/`. There is no committed history, no framework selection, and no architectural decisions encoded in the codebase.

This audit establishes the **starting baseline** for M0. There are no existing patterns to preserve and no working code at risk of conflict. All product and domain decisions must be introduced deliberately in subsequent M0 tasks.

---

## Current Technical Baseline

| Area | Status | Notes |
|------|--------|-------|
| **Framework / runtime** | Not present | No `package.json`, `requirements.txt`, `go.mod`, or equivalent |
| **Frontend architecture** | Not present | No UI framework, pages, components, or routing |
| **Backend architecture** | Not present | No API server, services, or business logic layer |
| **Database / persistence** | Not present | No schema, migrations, ORM config, or seed data |
| **Authentication** | Not present | No auth provider, session, or identity model |
| **Routes / pages** | Not present | No web routes or page definitions |
| **Domain models / types** | Not present | No entity classes, TypeScript types, or DTOs |
| **Localization / i18n** | Not present | No translation files, locale config, or i18n library |
| **Financial logic** | Not present | No tuition, receivable, payment, or expense code |
| **Tests** | Not present | No unit, integration, or E2E test suites |
| **Environment / config** | Not present | No `.env.example`, config files, or deployment manifests |
| **Documentation** | Not present (prior to M0-T01) | No README, ADRs, or product specs |
| **CI/CD** | Not present | No GitHub Actions, pipelines, or lint/format config |

---

## Inspected Paths

| Path | Finding |
|------|---------|
| `D:\Olli\` (root) | Empty — no application files |
| `D:\Olli\.git\hooks\` | Default Git sample hooks only (`*.sample`) |
| `D:\Olli\docs\` | Did not exist prior to M0-T01 |
| All glob patterns for `*.json`, `*.ts`, `*.tsx`, `*.js`, `*.py`, `*.sql`, `*.md`, `*.env*` | Zero matches |

---

## Duplicated or Placeholder Architecture

**None found.** The repository contains no placeholder modules, scaffolded layers, or conflicting architectural experiments.

---

## Conflicts with M0 Product Model

**None from existing code.** Because the repository is empty, there are no legacy UI assumptions, hard-coded Vietnamese domain values, flattened expense models, or LMS-style features to reconcile.

### Pre-implementation risks (not code conflicts)

These are **process risks** to address before M0-T02:

1. **Cost B architecture not documented in-repo** — The task references a previously agreed two-group cost model. That agreement is not present in this repository or accessible project history. M0-T01 documents the assumed structure and flags it for confirmation (see [05-foundation-risks.md](./05-foundation-risks.md)).
2. **Technology stack undecided** — Framework choice (frontend, backend, database) is open. M0-T02/T03 should not assume a stack until explicitly chosen.
3. **Git repository state** — `.git` hook samples exist but repository initialization may be incomplete (no commits detected during audit). Version control hygiene should be confirmed before M0-T02.

---

## Recommended Technical Direction (Informational — Not Decided in M0-T01)

The following are **recommendations for future tasks**, not decisions made in this audit:

| Concern | Recommendation |
|---------|----------------|
| i18n from M0 | Choose a stack with first-class locale support; store UI strings outside business logic |
| Historical truth | Prefer relational DB with explicit transaction/event tables and effective-dated master data |
| Reporting | Design domain model for queryability; defer materialized views/caches until needed |
| API readiness | Separate domain layer from presentation even in a monolith |

No framework is selected in M0-T01 per task constraints.

---

## Audit Conclusion

**Baseline:** Empty greenfield repository.  
**Risk level:** Low for code conflicts; **medium** for undocumented prior agreements (Cost B, role model, enrollment rules).  
**Action:** Proceed to product contract and domain foundation documentation; lock Cost B definition before M0-T02 relational modelling.
