# M6 — Center Administration Contract

**Milestone:** M6 — Center Administration, Users & Access Control  
**Task:** M6-T01 — Audit, Security Contract & Execution Plan  
**Baseline:** `main` @ `8d84fb5` (M5 closed)  
**Status:** Contract documented; implementation begins at M6-T02 (authorized separately)

This document is the canonical implementation contract for M6. It inventories the repository as audited at T01 and defines target architecture. **T01 introduces no production schema, backend, or UI changes.**

---

## 1. Milestone objective

M6 delivers **center-level user and access administration** on top of existing Supabase Auth, `app_user`, org-scoped roles, permissions, and RLS. It must **not** alter accepted M1–M5 business semantics (finance recognition, CRM attribution, teaching sessions, executive KPI definitions, etc.).

M6 explicitly **does not** include: SaaS billing, payment gateways, payroll/HR modules, performance rankings, SSO expansion, multi-primary-owner product flows, organization hierarchy, or a user-facing primary-owner transfer workflow.

---

## 2. Current schema inventory

### 2.1 Organization & access (M0)

| Object | Location | Notes |
|--------|----------|-------|
| `organization` | `supabase/migrations/20260914140000_m0_foundation.sql` | `status` `active` \| `inactive`; no owner or entitlement columns |
| `app_user` | same | One org per user; `email`, `display_name`, `status` `active` \| `inactive` \| `locked`; audit `created_by` / `updated_by` |
| `app_user.auth_user_id` | `supabase/migrations/20260914140200_auth_identity.sql` | FK → `auth.users`, `ON DELETE SET NULL` |
| `role` | M0 foundation | Org-scoped free-form `code`; not product enums |
| `role_permission` | M0 foundation | M:N role ↔ global `permission` |
| `user_role` | M0 foundation | Effective dating; `status` `active` \| `ended` |
| `permission` | M0 + M2–M5 migrations | Global catalog; idempotent `INSERT` in migrations |

**Organization bootstrap triggers (production):**

- Cost groups: `initialize_organization_cost_groups()` on `organization` INSERT (M0, extended M2-T02).
- CRM reference: `initialize_organization_crm_reference_data()` on `organization` INSERT (`20260914142300_m3_t02_core_crm_data_foundation.sql`).

**Not present:** canonical role template initialization, primary owner column, seat/entitlement table.

### 2.2 Application permission registry

- TypeScript catalog: `src/lib/permissions/codes.ts` (65 codes including M5 executive and academic review codes).
- M0 baseline: `supabase/migrations/20260914140100_reference_data.sql`.
- Later additions: M2 finance, M3 CRM, M4 (via enrollment/operations permissions), M5 reporting (`20260914143800_m5_t01_reporting_foundation.sql`, `20260920100000_m5_t07_executive_exception_follow_up.sql`, etc.).

### 2.3 Historical attribution (representative)

Domain tables reference `app_user.id` (often composite FK with `organization_id`) with **`ON DELETE RESTRICT`** on critical paths, for example:

- CRM: `lead`, `lead_assignment`, activities (`20260914142300_m3_t02_core_crm_data_foundation.sql`, `20260914142500_m3_t04_lead_assignment_ownership.sql`).
- Finance: payments, revenue, declarations, personnel costing (`20260914141900_m2_t06_revenue_recognition.sql`, `20260914142000_m2_t07_personnel_costing.sql`, M5 declaration tables).
- Academic: assessments, review metadata (`20260914144100_m5_t03_academic_quality.sql`).
- Operations: session change history (`20260914143500_m4_t06_session_operations.sql`).

Teaching attribution often uses `teacher.id`; optional `teacher.user_id` → `app_user` (`20260914140000_m0_foundation.sql`, `validate_teacher_user_org`).

**Name collision:** `enrollment_recognition_entitlement()` in M2 is **revenue recognition**, not login seats (`20260914141900_m2_t06_revenue_recognition.sql`).

### 2.4 Dev-only fixtures

- `supabase/seed.sql`: roles `admin`, `staff`, `student_reader`, `no_student` — **not** product role codes.
- Auth users: `scripts/seed-auth-users.mjs` (GoTrue Admin API, service/secret key).

---

## 3. Current auth architecture

| Layer | Implementation |
|-------|----------------|
| Public config | `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` (`docs/m0/24-auth-application-flow.md`) |
| Server session | `src/lib/supabase/server.ts` — user JWT only, no secret key |
| Identity gate | `src/lib/auth/get-identity-state.ts` — `getClaims()` → `app_user` by `auth_user_id`; requires `status = 'active'` |
| Org context | `current_organization_id()` from active `app_user` (`20260914140300_rls_helpers_and_grants.sql`) |
| Authorization | `has_permission(code)` + RLS policies (`20260914140400_rls_policies.sql`) |
| UX permission check | `src/lib/permissions/can.ts` → RPC `has_permission` |
| Nav visibility | `list_my_permissions()` + `src/lib/navigation/app-navigation.ts` |

**Elevated credentials:** Auth Admin / service role exist only in **fixture and acceptance scripts** (e.g. `scripts/seed-auth-users.mjs`, `scripts/m1-acceptance-scenario.mjs`), not in `src/`.

**Gap:** No Supabase Edge Functions under `supabase/functions/`; no server actions for staff provisioning.

---

## 4. Primary Owner invariant (target)

### 4.1 Conceptual separation (locked for M6)

```text
organization membership identity
    +
primary ownership invariant
    +
authorization role / template
```

- Assigning a powerful **authorization role** must **never** by itself make a user the **subscribed primary Owner**.
- Changing or removing an authorization role must **not** silently transfer organization ownership.

Final column/table naming is **deferred to M6-T02**, but the invariant is fixed now.

### 4.2 Product rules (M6)

| Rule | Requirement |
|------|-------------|
| Primary Owner count | Exactly **one** per organization |
| Demotion | Primary Owner **cannot** be demoted via normal staff role management |
| Suspension | Primary Owner **cannot** be suspended via normal staff lifecycle actions |
| Removal | Primary Owner **cannot** be removed via normal `/users` actions |
| Self-promotion | Staff **cannot** promote themselves or another staff account to primary ownership |
| Transfer | **No** user-facing primary-owner transfer in M6; future transfer = RIUDA break-glass or separately scoped feature |

### 4.3 Relationship to Center Manager role

The **primary Owner** is the subscribed account RIUDA associates with the center. The **Center Manager / Owner-Admin** authorization template grants full center administration including Executive Overview. In production, the primary Owner must hold that template (or equivalent enforced capability set), but **holding consultant/accountant/teacher templates must not imply ownership**.

T02 must implement DB/RPC enforcement; RLS alone is insufficient (see §16).

---

## 5. Role model

### 5.1 Five canonical product roles (unchanged)

1. Center Manager / Owner-Admin  
2. Accountant  
3. Consultant  
4. Academic Operations  
5. Teacher  

No HR role. No custom role builder in M6.

### 5.2 Current physical model

- `role(organization_id, code)` is **free-form** per org (`20260914140000_m0_foundation.sql`).
- Product bundles documented in `src/lib/workspaces/role-contracts.ts` and `docs/m5/01-role-workspace-contracts.md`.
- RLS never checks role names; only `has_permission` (`docs/m0/19-permission-model.md`).

### 5.3 Target (T02)

- **Product-defined templates** for the five roles, initialized for every organization deterministically and idempotently.
- Normal center users **must not** mutate canonical templates to grant Executive or Owner-administration capabilities to staff roles.
- T02 chooses safest representation (e.g. immutable template flag, system role codes, RPC-only `role_permission` changes for canonical roles) based on existing architecture.

### 5.4 Dev seed mapping (non-production)

| Seed code | Nearest canonical role |
|-----------|-------------------------|
| `admin` | Center Manager (all permissions) |
| `staff` | Mixed read-only (not a product role) |

See `supabase/seed.sql`, `docs/m5/03-permission-role-audit.md`.

---

## 6. Permission model

### 6.1 Resolution chain

```text
app_user → user_role → role → role_permission → permission.code
```

Helper: `has_permission(p_code)` (`20260914140300_rls_helpers_and_grants.sql`).

### 6.2 Executive boundary (M5, preserved)

- Cross-domain Executive Overview: `report.executive.read` (minimum); follow-up: `report.executive.follow_up.manage`.
- Comment on permission table: executive gate for Center Manager (`20260914143800_m5_t01_reporting_foundation.sql`).
- UI example: `src/app/(protected)/executive/page.tsx`.

**M6 requirement:** Primary Owner / Center Manager is the **only** account entitled to Executive Overview. Defense must not rely on nav hiding alone (§16).

### 6.3 Access-control permissions (current)

| Code | Typical use today |
|------|-------------------|
| `user.read` | RLS: list org `app_user` rows |
| `user.manage` | Insert/update users; sensitive field trigger |
| `role.read` | View roles / assignments |
| `role.manage` | Create roles, edit `role_permission`, assign `user_role` |

Sensitive fields on `app_user`: `protect_app_user_sensitive_fields` (`20260914140300_rls_helpers_and_grants.sql`).

### 6.4 Known gaps (carried to T02)

See §21.

---

## 7. Production role-template mechanism (current vs target)

### 7.1 Current behavior

| Path | Roles / permissions |
|------|---------------------|
| New org via authenticated API | **No** INSERT policy on `organization` — orgs not created via normal client API |
| After org INSERT | Cost groups + CRM seeds only |
| Production migrations | Global `permission` rows only |
| Real center onboarding | **Undefined in repo** — requires RIUDA/service provisioning outside app RLS |
| Local dev | Manual `seed.sql` roles |

### 7.2 Target (T02)

- `seed_organization_canonical_roles(organization_id)` (name TBD): idempotent, creates five roles + fixed permission graphs.
- Trigger or explicit call on organization creation (align with existing CRM/cost init pattern).
- Migration backfill for existing organizations.
- Template migration strategy for **future permission additions** without overwriting owner-customized **non-canonical** data (if any exists — today centers should not rely on custom roles in production).

---

## 8. Organization entitlement & seat semantics

### 8.1 Product authority: `organization_entitlement`

**Do not** name the persistence model `organization_subscription`. M6 is not SaaS billing.

**Target table (T02):** one row per organization, e.g.:

| Concept | Default | Notes |
|---------|---------|-------|
| `staff_limit` | 5 | Staff seat cap (excludes primary Owner unless T02 defines otherwise) |
| Primary owner limit | 1 | Exactly one primary Owner |
| Future RIUDA updates | — | May change `staff_limit` without altering M1–M5 domain tables |

Runtime **product authority** for seats is entitlement data, not billing tables.

### 8.2 Authentication status ≠ seat membership status

```text
authentication status  !=  seat membership status
```

| State | Access | Occupies staff seat? |
|-------|--------|----------------------|
| Active login | Yes | Yes (if staff membership active) |
| Suspended / locked / inactive access | No | **Yes** — seat **not** released |
| Role change (e.g. Consultant → Academic Ops) | Per new role | **Yes** — same membership |
| **Removed from center** (canonical removal) | No | **No** — seat released |

**Anti-abuse:** Suspend five staff → create five more → reactivate old staff must **not** exceed entitlement. Only **removal from the center** releases a seat.

### 8.3 Staff membership lifecycle (target)

Distinct concepts T02 must represent (exact columns TBD, may extend beyond `app_user.status`):

1. **Active access** — may authenticate (subject to Auth + `app_user` + roles).
2. **Suspended / locked access** — cannot operate; membership and seat retained.
3. **Removed membership** — no longer a center member; **`app_user.id` preserved** for history; seat released.

Historical `app_user` identity remains after removal (`docs/m0/18-auth-identity-model.md`).

### 8.4 Concurrent enforcement

Seat checks must be **race-safe** (transaction + row lock on entitlement or membership counter). UI-only checks are insufficient.

---

## 9. Trusted provisioning architecture

### 9.1 Boundary (required)

```text
Client
  → trusted application boundary (Server Action / Route Handler / orchestrating RPC)
  → authorization + organization entitlement check
  → Auth user provisioning (Admin API, server-only secret)
  → application membership + role assignment
```

- Browser/client **must not** hold service-role or Auth Admin credentials (`docs/m0/20-rls-policy-matrix.md`, `docs/m0/24-auth-application-flow.md`).
- Actor identity and organization scope **server-derived** (`current_app_user_id()`, `current_organization_id()`), never from client-supplied org UUIDs alone.

**Implementation:** M6-T03 (not T02). T02 may add schema and non-Auth RPC stubs; Auth Admin wiring in T03.

### 9.2 Not a single native ACID transaction

Supabase Auth Admin and PostgreSQL provisioning **cross system boundaries**. They cannot be one database transaction.

T03 must design for:

| Requirement | Purpose |
|-------------|---------|
| Idempotent provisioning | Safe retries |
| Deterministic correlation | Auth user ↔ `app_user` (e.g. idempotency key, reserved email, explicit link step) |
| Partial failure handling | Auth succeeds, DB fails → compensation/cleanup |
| Reverse incomplete state | DB row without Auth, orphaned Auth without membership |
| No duplicate membership | Same request retried |
| Race-safe entitlement | Seat reservation under concurrency |
| Secrets only in trusted server | Never in client bundles (`scripts/env-secrets-audit.mjs`) |

**Product semantics:** one logical “create staff account” operation; **implementation** must document and test failure branches.

### 9.3 Current partial path (insufficient)

RLS allows `app_user` INSERT with `user.manage` without creating Auth users (`20260914140400_rls_policies.sql`). Dev Auth creation remains `scripts/seed-auth-users.mjs` only.

---

## 10. Staff lifecycle (target semantics)

| Operation | Target behavior |
|-----------|-----------------|
| Create / provision | T03 trusted boundary + entitlement check |
| Activate | Auth + active membership + role assignment |
| Assign / change role | End prior `user_role`; assign new; **no** historical attribution rewrite |
| Suspend access | Disable login; **retain seat** |
| Reactivate | Restore access; verify still within entitlement if membership was never removed |
| Remove from center | End membership, release seat, disable Auth; **preserve** `app_user.id` |
| Delete Auth user | Existing: `auth_user_id` SET NULL; history preserved (`20260914140200_auth_identity.sql`) |

Primary Owner excluded from suspend/remove/demote via normal UI (§4).

---

## 11. Role-change semantics

**Authorization (current)** is computed from active `user_role` → permissions (`has_permission`).

**Historical authorship (immutable)** uses `app_user.id` at time of action (CRM assignment history, declarations, approvals, session changes, attendance/review authorship, finance audit columns).

Rules:

- Consultant → Academic Operations: CRM leads remain attributed to original consultant user ids; no rewrite of `lead_assignment` or conversion attribution (`20260919100000_m5_t04_1_consultant_conversion_semantics.sql` cohort semantics).
- Teacher suspended: historical `teaching_session` / `teacher` records remain visible (`protect_completed_session_teacher` in M0 foundation).
- Accountant suspended: prior approvals remain (`ON DELETE RESTRICT` FKs).

M6 role administration must **only** affect future authorization, not past domain facts.

---

## 12. Suspension semantics

- **Access:** `has_permission` requires `app_user.status = 'active'` (`20260914140300_rls_helpers_and_grants.sql`); inactive users fail identity helpers.
- **Application gate:** `get-identity-state.ts` treats non-`active` as denied (TS types omit `locked` but DB allows `locked` — align in T07).
- **Seat:** suspension **does not** release entitlement seat (§8.2).
- **Primary Owner:** not suspendable via normal staff actions (§4).

Optional T03/T05: Auth-level ban/disable in addition to application status.

---

## 13. Deletion / removal semantics

- **No hard delete** of `app_user` for operational staff removal: widespread `ON DELETE RESTRICT` on domain FKs.
- RLS: no DELETE policies on identity tables in M0 matrix (`docs/m0/20-rls-policy-matrix.md`).
- **Product “delete staff”** → **removal from center** (membership end + Auth disable), not row DELETE.
- Auth account deletion: optional; if performed, `auth_user_id` nulls; `app_user` and history remain (`docs/m0/18-auth-identity-model.md`).

---

## 14. Historical-reference preservation

Preservation is already enforced by schema + triggers (finalized assessments, completed session teachers, immutable lead assignment via RPC, append-only assignment history). M6 must **not** introduce cascades or updates that rewrite provenance when staff are removed or roles change.

---

## 15. Organization isolation

Every user-administration operation must be scoped to the actor’s organization.

- RLS: `organization_id = current_organization_id()` on identity tables (`20260914140400_rls_policies.sql`).
- Tests: cross-org role manage denied (`supabase/tests/m0_security_tests.sql` scenario 22).
- Trusted backend must re-validate org on every provisioning and role mutation; reject forged org/user ids.

Center A Owner must never list, modify, suspend, or inspect Center B users or entitlement.

---

## 16. RLS / server authorization & Executive defense-in-depth

### 16.1 Layers

| Layer | Responsibility |
|-------|------------------|
| Route / Server Component | `can()` checks (UX + first gate) |
| RLS | Org boundary + permission on tables |
| SECURITY DEFINER RPCs | Internal `has_permission` + domain rules (pattern: `assign_lead()`, executive RPCs) |

Menu hiding is **not** authorization (`docs/m5/01-role-workspace-contracts.md`).

### 16.2 Executive invariant (T02/T06)

Must prevent bypass via:

- Direct grant of `report.executive.read` to staff roles
- Mutating canonical role permission graphs
- Direct RPC invocation without primary-owner check
- Forged organization or user identifiers

**Target:** combine `report.executive.read` checks with **`is_primary_owner()`** (or equivalent) inside executive RPCs and harden role graph mutations — exact design in T02.

### 16.3 Current escalation risk

Any holder of `role.manage` may insert `role_permission` including `report.executive.read` (`20260914140400_rls_policies.sql`). M0 test 20 covers staff **without** `role.manage` only (`supabase/tests/m0_security_tests.sql`).

---

## 17. `/users` target UX (T04)

**Owner administration workspace**, not a general staff directory.

Target capabilities for primary Owner:

- View staff; distinguish primary Owner from staff
- Role, access state, **seat usage** (e.g. `3 / 5` staff seats — occupancy per §8)
- Create staff (T03 provisioning)
- Assign/change **allowed staff roles** (not Owner template; not executive escalation)
- Suspend / reactivate (staff only)
- Remove staff per removal semantics (§13)

### 17.1 Current gap (documented; fix T02/T04)

Navigation and `/users` gate on `user.read` **or** `user.manage` (`src/lib/navigation/app-navigation.ts`, `src/app/(protected)/users/page.tsx`). Dev `staff` role includes `user.read` (`supabase/seed.sql`).

**Direction:** Do not overload generic identity-read permission with account administration. Accountant, Consultant, Academic Operations, and Teacher must not gain center account-administration access because another feature needs identity display.

---

## 18. Expected database changes (T02+)

Non-exhaustive; **not implemented in T01**:

- `organization_entitlement` (one row per org, `staff_limit`, primary owner limit semantics)
- Primary ownership marker (column or membership kind) + constraints (max one primary)
- Staff membership / seat occupancy model distinct from access status
- Canonical role seed function + org trigger/backfill
- RPCs: role assignment with forbidden permission sets; optional membership removal
- Constraints/triggers: block executive permission on staff templates; block primary Owner demotion/suspend/remove via direct DML
- Harden `auth_user_id` assignment (INSERT/UPDATE validation)
- SQL tests under `supabase/tests/m6_*`

---

## 19. Expected trusted-backend changes (T03+)

- Server-only module using secret key for Auth Admin (create/update/disable users)
- Idempotent provisioning orchestration with compensation documented in §9.2
- Owner-only API surface for staff lifecycle
- Audit logging (T03/T05 — format TBD)

No Edge Function required if Next.js server boundary is sufficient; decision in T03.

---

## 20. Test strategy

| Phase | Focus |
|-------|--------|
| T02 | SQL: entitlement concurrency, one primary owner, canonical role idempotency, executive grant denial for staff |
| T03 | Provisioning idempotency, partial-failure simulation, seat limit |
| T04–T07 | Playwright: Owner `/users`; denial for non-Owner roles |
| T08 | Milestone acceptance SQL + e2e (pattern: `supabase/tests/m5_milestone_acceptance_tests.sql`, `tests/e2e/m5-acceptance.spec.ts`) |

Extend `supabase/tests/m0_security_tests.sql` patterns for self-promotion and cross-org admin.

---

## 21. Permission gaps for M6-T02 normalization

**Do not rename permission codes in T01/T02 without explicit task.** T02 planning inventory:

| Category | Items | Evidence |
|----------|-------|----------|
| Placeholder | `report.read` | Unused in nav; executive uses `report.executive.read` (`docs/m5/03-permission-role-audit.md`) |
| App-unused | `progress_evaluation.record` | RLS only; no `src/` usage |
| Bundle vs UI gap | `assessment.create`, `teacher.create` | Used in UI/actions; absent from academic_ops minimal bundle in `role-contracts.ts` |
| Over-broad dev seed | `user.read` on `staff` | `supabase/seed.sql` |
| Admin surface conflation | `user.read` opens `/users` nav | `app-navigation.ts` |
| Escalation | `role.manage` + `role_permission` INSERT | Can grant `report.executive.read` |
| Self-service role assign | Users with `role.manage` | Not covered by test 20 (staff without manage) |

Recommended T02 outcomes: Owner-only administration permission (or narrow `user.manage`), split identity read for CRM/ops pickers vs `/users`, template-locked canonical roles, RPC-only graph changes for templates.

---

## 22. Task breakdown (M6-T02 – T08)

```text
M6-T01 — Audit, Security Contract & Execution Plan          [this document]

M6-T02 — Owner, Entitlement, Canonical Roles & Permission Foundation
         organization_entitlement; primary owner invariant; seat vs access;
         canonical five-role init; permission graph hardening;
         anti self-promotion; anti staff executive escalation;
         idempotent org role initialization; NO Auth Admin provisioning

M6-T03 — Trusted Staff Provisioning & Account Lifecycle
         Auth Admin boundary; idempotency; partial failure; seat reservation

M6-T04 — Owner `/users` Administration Workspace
         list, seats, create/suspend/reactivate/remove; Owner distinct UI

M6-T05 — Suspension, Removal, Role Changes & Historical Integrity
         role transitions; removal semantics; attribution preservation tests

M6-T06 — Security, RLS & Organization-Isolation Hardening
         executive defense-in-depth; RPC inventory; cross-org regression

M6-T07 — UX, i18n, Integration & Regression Hardening
         nav permission fix; locked status; e2e matrix by role

M6-T08 — Final Acceptance & Milestone Closeout
```

---

## 23. Risks

| Risk | Mitigation phase |
|------|------------------|
| Production orgs without canonical roles | T02 backfill + init trigger |
| Privilege escalation via `role.manage` | T02 RPC + template locks |
| Cross-boundary provisioning failures | T03 idempotency + compensation |
| Seat bypass via suspend/create cycle | T02 membership vs access model |
| Executive access leak | T02/T06 `is_primary_owner` + RPC checks |
| Orphan `app_user` without Auth | T03 linking rules |

---

## 24. Non-goals (M6)

Payroll; HR module; employee/teacher/consultant ranking; timekeeping; SaaS payment gateway; invoice billing engine for RIUDA; public signup redesign; multiple primary owners; org hierarchy/branches; SSO/social login expansion; custom role builder; AI; unrelated UI redesign; user-facing primary-owner transfer.

---

## 25. T01 audit references

Pre-implementation audit approved with architectural corrections (entitlement naming, seat semantics, cross-boundary provisioning, no M6 owner transfer UI, T02 scope expansion). Baseline verification: `main` @ `8d84fb5`, clean working tree.

---

## Appendix A — Code & doc index

| Area | Path |
|------|------|
| Schema foundation | `supabase/migrations/20260914140000_m0_foundation.sql` |
| Auth link | `supabase/migrations/20260914140200_auth_identity.sql` |
| RLS helpers | `supabase/migrations/20260914140300_rls_helpers_and_grants.sql` |
| RLS policies | `supabase/migrations/20260914140400_rls_policies.sql` |
| Role contracts | `src/lib/workspaces/role-contracts.ts` |
| Navigation | `src/lib/navigation/app-navigation.ts` |
| Users placeholder | `src/app/(protected)/users/page.tsx` |
| M5 closeout | `docs/m5/06-m5-acceptance-closeout.md` |
