# M7 — Center Onboarding, Subscription & Commercial Readiness

M7 adds the **productization layer** required to provision and operate Olli as a small-center SaaS product, on top of the operational product delivered in M1–M6.

**Commercial baseline (locked):**

- One customer center has one primary subscribed Owner/Admin account.
- Base entitlement: Owner plus up to **5** staff accounts (M6 seat enforcement remains canonical).
- Staff accounts are created and managed by the center Owner.
- RIUDA/Olli manages **center-level** subscription/entitlement, not per-staff billing.
- M7 does **not** reinterpret M1–M6 domain semantics.

## Milestone status

| Task | Document | Status |
|------|----------|--------|
| M7-T01 | [Commercial readiness audit & design gate](./01-m7-t01-commercial-readiness-audit-design.md) | **Complete** |
| M7-T02 | [Trusted center + primary Owner provisioning](./02-m7-t02-trusted-center-owner-provisioning.md) | **Complete** |
| M7-T03 | [Subscription & entitlement domain](./03-m7-t03-subscription-entitlement-domain.md) | **Complete** |
| M7-T04 | [Commercial access enforcement](./04-m7-t04-commercial-access-enforcement.md) | **Complete** |
| M7-T04.1 | [Regression stabilization](./04.1-m7-t04-regression-stabilization.md) | **Complete** |
| M7-T05 | [Owner subscription / commercial status UX](./05-m7-t05-owner-subscription-commercial-status-ux.md) | **Complete** |
| M7-T06 | Owner onboarding & center setup UX | Implemented |
| M7-T07 | Integration, security & production hardening | Planned |
| M7-T08 | Final acceptance & milestone closeout | Planned |

## Task sequence

| Task | Focus |
|------|--------|
| M7-T01 | Repository audit, canonical commercial architecture, task map |
| M7-T02 | Trusted center + primary Owner provisioning (production-safe) |
| M7-T03 | Provider-neutral plan, subscription, entitlement linkage |
| M7-T04 | Subscription vs RBAC enforcement (DB-authoritative) |
| M7-T05 | Owner-facing subscription & seat status surface |
| M7-T06 | Minimal Owner first-use / center setup flow |
| M7-T07 | Security, operator boundaries, regression hardening |
| M7-T08 | Acceptance SQL, API, Playwright, `npm run verify` closeout |

## Foundation document (T01)

- [01 — M7-T01 audit & design report](./01-m7-t01-commercial-readiness-audit-design.md)

## Related contracts (preserved)

- [M6 — Center administration](../m6/README.md) (CLOSED)
- [M6 center administration contract](../m6/01-center-administration-contract.md)
- [M6 access foundation](../m6/02-t02-access-foundation-implementation.md)
- [M0 auth application flow](../m0/24-auth-application-flow.md)
- [M0 RLS policy matrix](../m0/20-rls-policy-matrix.md)

## Explicit M7 non-goals (milestone scope)

Payment processing, public pricing, checkout, invoices, taxation, automated billing emails, marketing site integration, Owner transfer, per-staff billing, multiple primary Owners, enterprise SSO, feature marketplace, mobile apps, and a large RIUDA super-admin portal are **out of scope** unless a later milestone explicitly opens them.
