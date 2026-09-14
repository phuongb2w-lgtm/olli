# M0 — Foundation Documentation

English Language Center Management Web App (**Olli**)

## Milestone Status

| Task | Document | Status |
|------|----------|--------|
| M0-T01 | Product Contract & Foundation Audit | **Complete** (`294e6d3`) |
| M0-T02 | Canonical Domain Model | **Complete** (`b1ff5c4`) |
| M0-T03 | PostgreSQL Data Foundation | **Complete** (`ca1e1c6`) |
| M0-T04 | Identity, Permissions & RLS | **Complete** (`83168e6`) |
| M0-T05 | Web Application & i18n Bootstrap | **Complete** |
| M0-T06 | Foundation Closeout & Release Baseline | **Complete** |

**M0 — CLOSED / ACCEPTED.** See [29-m0-closeout.md](./29-m0-closeout.md).

---

## Document Index

### Product

| Document | Description |
|----------|-------------|
| [02-product-contract.md](./02-product-contract.md) | Product scope and boundaries |
| [03-domain-map.md](./03-domain-map.md) | Domain map |
| [33-open-decisions.md](./33-open-decisions.md) | Intentionally unresolved business decisions |

### Canonical Model

| Document | Description |
|----------|-------------|
| [07-canonical-domain-model.md](./07-canonical-domain-model.md) | Canonical entities and rules |
| [08-entity-relations.md](./08-entity-relations.md) | Entity relationships |
| [09-finance-model.md](./09-finance-model.md) | Finance domain model |
| [10-learning-evidence-model.md](./10-learning-evidence-model.md) | Learning evidence model |
| [11-er-diagram.md](./11-er-diagram.md) | ER diagram |
| [12-domain-validation.md](./12-domain-validation.md) | Domain scenario validation |
| [31-status-code-registry.md](./31-status-code-registry.md) | Machine status/type registry |

### Physical Database

| Document | Description |
|----------|-------------|
| [13-physical-data-model.md](./13-physical-data-model.md) | Physical schema |
| [14-database-constraints.md](./14-database-constraints.md) | Constraints |
| [15-database-indexes.md](./15-database-indexes.md) | Indexes |
| [16-data-integrity-tests.md](./16-data-integrity-tests.md) | Integrity test documentation |

### Security

| Document | Description |
|----------|-------------|
| [18-auth-identity-model.md](./18-auth-identity-model.md) | Auth vs app_user model |
| [19-permission-model.md](./19-permission-model.md) | **Canonical 34-permission registry** |
| [20-rls-policy-matrix.md](./20-rls-policy-matrix.md) | RLS policy matrix |
| [21-security-tests.md](./21-security-tests.md) | Security test documentation |
| [32-security-surface-inventory.md](./32-security-surface-inventory.md) | Public schema security baseline |

### Web Application

| Document | Description |
|----------|-------------|
| [23-web-stack.md](./23-web-stack.md) | Next.js stack |
| [24-auth-application-flow.md](./24-auth-application-flow.md) | Application auth flow |
| [26-api-security-smoke.md](./26-api-security-smoke.md) | API security smoke tests |
| [27-ci-foundation.md](./27-ci-foundation.md) | CI pipeline |
| [30-architecture-baseline.md](./30-architecture-baseline.md) | **M0 architecture ADR** |

### i18n

| Document | Description |
|----------|-------------|
| [25-i18n-foundation.md](./25-i18n-foundation.md) | Locale, formatting, namespaces |

### Testing

| Document | Description |
|----------|-------------|
| [16-data-integrity-tests.md](./16-data-integrity-tests.md) | 25 domain integrity scenarios |
| [21-security-tests.md](./21-security-tests.md) | 30 RLS scenarios |
| [26-api-security-smoke.md](./26-api-security-smoke.md) | 6 API scenarios |
| [27-ci-foundation.md](./27-ci-foundation.md) | CI + unified verify |

### Closeout

| Document | Description |
|----------|-------------|
| [29-m0-closeout.md](./29-m0-closeout.md) | **M0 closeout report** |
| [30-architecture-baseline.md](./30-architecture-baseline.md) | Locked architecture decisions |
| [31-status-code-registry.md](./31-status-code-registry.md) | Status code contract |
| [32-security-surface-inventory.md](./32-security-surface-inventory.md) | Security inventory |
| [33-open-decisions.md](./33-open-decisions.md) | Open decision register |

### Historical / Superseded Notes

These remain for decision history but are superseded by closeout documents where noted:

| Document | Notes |
|----------|-------|
| [01-repository-audit.md](./01-repository-audit.md) | M0-T01 preliminary audit |
| [04-entity-inventory.md](./04-entity-inventory.md) | Superseded by [07-canonical-domain-model.md](./07-canonical-domain-model.md) |
| [05-foundation-risks.md](./05-foundation-risks.md) | M0-T01 risk register (historical) |
| [06-m0-t02-input.md](./06-m0-t02-input.md) | M0-T02 input (historical) |
| [17-m0-t03-decisions.md](./17-m0-t03-decisions.md) | M0-T03 decision log |
| [22-m0-t04-decisions.md](./22-m0-t04-decisions.md) | M0-T04 decision log |
| [28-m0-t05-decisions.md](./28-m0-t05-decisions.md) | M0-T05 decision log |

---

## Key Principles (Locked)

1. **Not an LMS** — management evidence only
2. **Historical truth** — no silent rewriting of past records
3. **Charge is sole debt source** — no Receivable/InvoiceLine
4. **Cost B** — two structural slots per org; business names pending
5. **Bilingual presentation** — stable machine codes in DB
6. **Tenant integrity** — composite FK pattern + RLS org isolation
7. **Permission codes, not role names** — authorization via `has_permission()`
8. **Auth ≠ app_user** — stable Olli identity with optional Auth mapping

---

## Verification

```powershell
npm run verify    # Full foundation gate (80/80 + lint + typecheck + build)
npm run db:verify # SQL suites only (requires Docker + Supabase)
```

Requires Docker Desktop. Olli local Supabase uses ports **54421–54424** (see `supabase/config.toml`).

---

## M1 Boundary

M0 is closed. The recommended first business milestone is **M1 — Student & Guardian Operations** (list, create/edit, lifecycle, guardian relationships, search, permissions, bilingual UX). Do not implement M1 features until explicitly scoped.
