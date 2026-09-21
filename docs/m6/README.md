# M6 — Center Administration, Users & Access Control

M6 turns existing authentication, organization, role, and permission foundations into complete **center-level user administration** without redesigning accepted M1–M5 business domains.

**Commercial model (product):** one primary subscribed Owner/Admin per center; default entitlement of five staff logins (six logins total including Owner). RIUDA/Olli manages entitlement; the center Owner manages staff inside the center. M6 does **not** implement external billing or payment-provider integration.

## Milestone status

| Task | Document | Status |
|------|----------|--------|
| M6-T01 | [Center administration contract](./01-center-administration-contract.md) | **Complete** (pending owner acceptance of closeout) |
| M6-T02 | [Access foundation implementation](./02-t02-access-foundation-implementation.md) | **Complete** (pending owner acceptance) |
| M6-T03 | [Trusted staff provisioning](./03-t03-trusted-staff-provisioning.md) | **Complete** (pending owner acceptance) |
| M6-T04 | Owner `/users` administration workspace | Not started |
| M6-T05 | Suspension, removal, role changes & historical integrity | Not started |
| M6-T06 | Security, RLS & organization-isolation hardening | Not started |
| M6-T07 | UX, i18n, integration & regression hardening | Not started |
| M6-T08 | Final acceptance & milestone closeout | Not started |

**M6 — OPEN** (T03 provisioning implemented). Do not begin M6-T04 until explicitly authorized.

## Task sequence

| Task | Focus |
|------|--------|
| M6-T01 | Audit, security contract & execution plan |
| M6-T02 | Owner, entitlement, canonical roles & permission foundation |
| M6-T03 | Trusted staff provisioning & account lifecycle |
| M6-T04 | Owner `/users` administration workspace |
| M6-T05 | Suspension, removal, role changes & historical integrity |
| M6-T06 | Security, RLS & organization-isolation hardening |
| M6-T07 | UX, i18n, integration & regression hardening |
| M6-T08 | Final acceptance & milestone closeout |

## Canonical operating roles (unchanged from M5)

1. **Center Manager / Owner-Admin** — full center administration; only role entitled to cross-domain Executive Overview
2. **Accountant** — finance workspace
3. **Consultant** — CRM / admissions workspace
4. **Academic Operations** — students, classes, operations, academic review
5. **Teacher** — teaching-focused workspace

There is **no HR role**. M6 does not introduce a custom role builder.

## Foundation document (T01)

- [01 — Center administration contract](./01-center-administration-contract.md)

## Related M5 contracts (preserved)

- [M5 role & workspace contracts](../m5/01-role-workspace-contracts.md)
- [M5 permission / role audit](../m5/03-permission-role-audit.md)
- [M0 auth identity model](../m0/18-auth-identity-model.md)
- [M0 permission model](../m0/19-permission-model.md)
- [M0 RLS policy matrix](../m0/20-rls-policy-matrix.md)
