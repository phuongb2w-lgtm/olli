# M0 — Foundation Documentation

English Language Center Management Web App (**Olli**)

## Milestone M0 Tasks

| Task | Document | Status |
|------|----------|--------|
| M0-T01 | Product Contract & Foundation Audit | **Complete** (`294e6d3`) |
| M0-T02 | Canonical Domain Model | **Complete** (`b1ff5c4`) |
| M0-T03 | PostgreSQL Data Foundation | **Complete** (`ca1e1c6`) |
| M0-T04 | Identity, Permissions & RLS | **Complete — pending review** |

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
- `supabase/migrations/20260914140000_m0_foundation.sql`
- `supabase/tests/m0_integrity_tests.sql`
- `scripts/db-verify.ps1`

---

## M0-T04 Deliverables

| Section | File |
|---------|------|
| Auth identity model | [18-auth-identity-model.md](./18-auth-identity-model.md) |
| Permission model | [19-permission-model.md](./19-permission-model.md) |
| RLS policy matrix | [20-rls-policy-matrix.md](./20-rls-policy-matrix.md) |
| Security tests | [21-security-tests.md](./21-security-tests.md) |
| M0-T04 decisions | [22-m0-t04-decisions.md](./22-m0-t04-decisions.md) |

**Executable artifacts:**
- `supabase/migrations/20260914140100_reference_data.sql` (production-safe)
- `supabase/migrations/20260914140200_auth_identity.sql`
- `supabase/migrations/20260914140300_rls_helpers_and_grants.sql`
- `supabase/migrations/20260914140400_rls_policies.sql`
- `supabase/migrations/20260914140500_charge_amount_immutability.sql`
- `supabase/seed.sql` (**dev only — never deploy to production**)
- `supabase/tests/m0_security_tests.sql`
- `scripts/supabase-verify.ps1`
- `types/database.generated.ts`

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

## Rebaseline

M0-T02/M0-T03 already incorporated finance and learning-evidence foundation work. **M0-T04** adds Identity / Permission / RLS on the real local Supabase stack — not a repeat of T03 schema work.

---

## Database Quick Start

```powershell
npm install

# Generic PostgreSQL compatibility (25 integrity tests)
npm run db:verify:postgres

# Full local Supabase stack (25 integrity + 30 security tests)
npm run db:verify:supabase
```

Requires Docker Desktop. Olli local Supabase uses ports **54421–54424** (see `supabase/config.toml`).

---

## Next Step

Review M0-T04 security architecture, then proceed to **M0-T05** (application bootstrap — scope TBD after review).
