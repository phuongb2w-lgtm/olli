# M0 — Foundation Documentation

English Language Center Management Web App (**Olli**)

## Milestone M0 Tasks

| Task | Document | Status |
|------|----------|--------|
| M0-T01 | Product Contract & Foundation Audit | **Complete** (`294e6d3`) |
| M0-T02 | Canonical Domain Model | **Complete** (`b1ff5c4`) |
| M0-T03 | PostgreSQL / Supabase Data Foundation | **Complete — pending review** |
| M0-T04 | TBD | Not started |

---

## M0-T01 Deliverables

| Section | File |
|---------|------|
| A. Repository Audit | [01-repository-audit.md](./01-repository-audit.md) |
| B. Product Contract | [02-product-contract.md](./02-product-contract.md) |
| C. Domain Map | [03-domain-map.md](./03-domain-map.md) |
| D. Preliminary Entity Inventory | [04-entity-inventory.md](./04-entity-inventory.md) |
| E. Foundation Risks | [05-foundation-risks.md](./05-foundation-risks.md) |
| F. M0-T02 Input | [06-m0-t02-input.md](./06-m0-t02-input.md) |

---

## M0-T02 Deliverables

| Section | File |
|---------|------|
| Canonical domain model | [07-canonical-domain-model.md](./07-canonical-domain-model.md) |
| Entity relations | [08-entity-relations.md](./08-entity-relations.md) |
| Finance model | [09-finance-model.md](./09-finance-model.md) |
| Learning evidence | [10-learning-evidence-model.md](./10-learning-evidence-model.md) |
| ER diagram | [11-er-diagram.md](./11-er-diagram.md) |
| Scenario validation | [12-domain-validation.md](./12-domain-validation.md) |

---

## M0-T03 Deliverables

| Section | File |
|---------|------|
| Physical data model | [13-physical-data-model.md](./13-physical-data-model.md) |
| Database constraints | [14-database-constraints.md](./14-database-constraints.md) |
| Database indexes | [15-database-indexes.md](./15-database-indexes.md) |
| Integrity tests | [16-data-integrity-tests.md](./16-data-integrity-tests.md) |
| M0-T03 decisions | [17-m0-t03-decisions.md](./17-m0-t03-decisions.md) |

**Executable artifacts:**
- `supabase/migrations/20250914140000_m0_foundation.sql`
- `supabase/seed.sql`
- `supabase/tests/m0_integrity_tests.sql`
- `scripts/db-verify.ps1`

---

## Key Principles (Locked)

1. **Not an LMS** — management evidence only  
2. **Historical truth** — no silent rewriting of past records  
3. **Charge is sole debt source** — no Receivable/InvoiceLine  
4. **Cost B** — two structural slots per org; business names pending  
5. **Bilingual presentation** — stable machine codes in DB  
6. **Tenant integrity** — composite FK pattern prevents cross-org references  

---

## Database Quick Start

```powershell
# Requires Docker Desktop
powershell -ExecutionPolicy Bypass -File scripts/db-verify.ps1
```

Runs: migrate → seed → 25 integrity tests.

---

## Next Step

Review M0-T03 physical schema, then proceed to **M0-T04** (recommended: application bootstrap + RLS/auth integration).
