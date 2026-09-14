# M0 — Foundation Documentation

English Language Center Management Web App (**Olli**)

## Milestone M0 Tasks

| Task | Document | Status |
|------|----------|--------|
| M0-T01 | Product Contract & Foundation Audit | **Complete** (baseline `294e6d3`) |
| M0-T02 | Canonical Domain Model & Relational Foundation | **Complete — pending review** |
| M0-T03 | Physical Schema Implementation | Not started |

---

## M0-T01 Deliverables

| Section | File |
|---------|------|
| A. Repository Audit | [01-repository-audit.md](./01-repository-audit.md) |
| B. Product Contract | [02-product-contract.md](./02-product-contract.md) |
| C. Domain Map | [03-domain-map.md](./03-domain-map.md) |
| D. Preliminary Entity Inventory | [04-entity-inventory.md](./04-entity-inventory.md) ⚠ superseded in part by M0-T02 |
| E. Foundation Risks | [05-foundation-risks.md](./05-foundation-risks.md) |
| F. M0-T02 Input | [06-m0-t02-input.md](./06-m0-t02-input.md) ⚠ superseded by M0-T02 output |

---

## M0-T02 Deliverables

| Section | File |
|---------|------|
| Canonical domain model (all entities) | [07-canonical-domain-model.md](./07-canonical-domain-model.md) |
| Entity relations & cardinality | [08-entity-relations.md](./08-entity-relations.md) |
| Finance model decisions | [09-finance-model.md](./09-finance-model.md) |
| Learning evidence model | [10-learning-evidence-model.md](./10-learning-evidence-model.md) |
| ER diagram (Mermaid) | [11-er-diagram.md](./11-er-diagram.md) |
| Scenario validation (14 cases) | [12-domain-validation.md](./12-domain-validation.md) |

---

## Key Principles (Locked)

1. **Not an LMS** — management evidence only  
2. **Business performance + learning quality** — connectable data model  
3. **Historical truth** — no silent rewriting of past records  
4. **Bilingual (vi/en)** — stable codes, localized presentation  
5. **Cost B** — exactly two cost groups per org; **business names pending**  
6. **Canonical data ≠ presentation** — compute aggregates, don't store dashboard blobs  
7. **Charge is sole source of debt** — no Receivable/InvoiceLine duplication  

---

## M0-T01 → M0-T02 Corrections

| Topic | M0-T01 | M0-T02 |
|-------|--------|--------|
| Cost B group names | Assumed `operating`, `teacher_direct` | **Not canonical** — use `group_slot` (1, 2) |
| Finance chain | Charge → Receivable → InvoiceLine → Payment | Charge → PaymentAllocation ← Payment |
| FinancialPeriod | Listed as required | **Deferred** |
| ClassSchedule | Implicit | **Explicit entity** |
| LocalePreference | Separate entity | Fields on User + Organization |
| Learning evidence | Suggested deferral | **Fully modelled in M0-T02** |

---

## Next Step

Review and lock M0-T02 canonical model, then proceed to **M0-T03** physical PostgreSQL schema per recommendations in [07-canonical-domain-model.md](./07-canonical-domain-model.md).
