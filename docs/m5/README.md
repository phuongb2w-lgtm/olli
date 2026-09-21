# M5 — Management Intelligence & Executive Reporting

M5 builds a management-intelligence layer over canonical M1–M4 operational data. Reporting must not become a second source of truth.

## Task sequence

| Task | Focus |
|------|--------|
| M5-T01 | Reporting foundation, role/workspace contracts, KPI semantics |
| M5-T02 | Financial & class economics intelligence |
| M5-T03 | Academic / teaching quality intelligence |
| M5-T04 | CRM, admissions & consultant productivity intelligence |
| M5-T05 | Teaching operations & resource intelligence |
| M5-T06 | Center Manager executive overview |
| M5-T07 | Period comparison, drill-down & management exceptions |
| M5-T08 | Role-based reporting UX, permissions, i18n & performance |
| M5-T09 | Final cross-domain acceptance & closeout |

**M5 closed (T09).** See [06-m5-acceptance-closeout.md](./06-m5-acceptance-closeout.md).

**Successor milestone:** [M6 — Center Administration](../m6/README.md) (**OPEN**, T01 contract).

## Canonical operating roles

1. **Center Manager** — full access; only role with complete executive reporting
2. **Accountant** — finance operational workspace
3. **Consultant** — admissions/sales workspace
4. **Academic Operations** — academic administration workspace
5. **Teacher** — teaching session workspace (simplest UI)

There is **no separate HR role**. User management belongs to the Center Manager.

## Foundation documents (T01)

- [Role & workspace contracts](./01-role-workspace-contracts.md)
- [Reporting semantics](./02-reporting-semantics.md)
- [Permission / role audit](./03-permission-role-audit.md)
- [Data-entry flow audit](./04-data-entry-flow-audit.md)
- [Semantic boundaries (T01.1)](./05-semantic-boundaries.md)

## Code contracts

- `src/lib/workspaces/role-contracts.ts` — five-role workspace bundles
- `src/lib/navigation/app-navigation.ts` — permission-aware navigation
- `src/lib/reporting/period-contract.ts` — local date / timezone period handling
- `src/lib/reporting/kpi-namespaces.ts` — stable KPI identifiers
- `supabase/migrations/20260914143800_m5_t01_reporting_foundation.sql` — DB foundation
