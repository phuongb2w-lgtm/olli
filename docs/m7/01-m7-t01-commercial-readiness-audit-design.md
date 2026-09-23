# M7-T01 — Commercial Readiness Audit & Design Report

**Milestone:** M7 — Center Onboarding, Subscription & Commercial Readiness  
**Task:** M7-T01 — Audit & design gate (no implementation)  
**Baseline:** `main` @ `5eaecac` — `chore(m6): close center administration milestone`  
**Migration count at baseline:** 54  
**M1–M6:** CLOSED / PASS (M6 closeout: i18n 1891/1891, Playwright 196/196, `npm run verify` exit 0)

T01 introduces **documentation only**. Application behavior and schema are unchanged.

---

## A. Repository baseline

| Item | Value |
|------|--------|
| **SHA** | `5eaecaccffa1fef65655df65708d6ed362753693` (`5eaecac`) |
| **Branch** | `main` |
| **Working tree** | Clean at T01 start (no staged/unstaged changes before T01 docs) |
| **Migrations** | 54 files under `supabase/migrations/` |

**T01 verification performed:** branch/SHA, clean tree, migration count, targeted code/SQL inspection (organization bootstrap, entitlement, provisioning, auth gates, `/users`, settings). Full `npm run verify` was **not** re-executed in T01; M6-T08 closeout remains the trusted green baseline. Re-run `npm run verify` before M7-T08 closeout.

---

## B. Existing foundations

### B.1 Organization & automated bootstrap

| Concept | Location | Behavior |
|---------|----------|----------|
| `organization` | `20260914140000_m0_foundation.sql` | `name`, `default_locale` (`vi`\|`en`), `timezone` (default `Asia/Ho_Chi_Minh`), `currency_code` (default `VND`), `status` (`active`\|`inactive`) |
| Cost groups | `initialize_organization_cost_groups` trigger on INSERT | Two cost groups per new org |
| CRM reference catalogs | `initialize_organization_crm_reference_data` trigger (M3-T02) | Default lead sources/reasons per org |
| Access foundation | `trg_initialize_organization_access_foundation` (M6-T02) | Inserts `organization_entitlement` row; seeds five canonical role templates + permissions |

**Authenticated clients cannot create organizations.** RLS defines SELECT/UPDATE for same org only; there is **no** INSERT policy on `organization` (`docs/m6/01-center-administration-contract.md` §7.1).

### B.2 Primary Owner identity

| Concept | Location | Notes |
|---------|----------|-------|
| `organization_entitlement.primary_app_user_id` | M6-T02 migration | Nullable FK to org-scoped `app_user`; exactly one primary Owner intended |
| `organization_entitlement.primary_owner_limit` | CHECK `= 1` | DB-enforced constant |
| `is_primary_owner()` | M6-T02 | Active org, active member user, matches `primary_app_user_id` |
| `set_primary_owner_for_organization(org, app_user)` | M6-T02 | **service_role only**; used in seeds/tests |
| Owner-only permissions | `has_permission()` / `list_my_permissions()` | `center_account.manage`, `report.executive.*` via `is_primary_owner()`, not role graph alone |
| Owner lifecycle guards | M6-T05 triggers/RPCs | Cannot suspend/remove/demote primary Owner via staff lifecycle |

**Gap:** Assigning `center_manager` `user_role` to the Owner is **not** automatic. Seeds do this manually (`supabase/seed.sql`). Without that assignment, Owner still gets executive/account RPCs via `is_primary_owner()`, but lacks many `organization.update` / domain permissions carried by the template.

### B.3 Center settings & setup UX

| Surface | Status |
|---------|--------|
| `/settings` | Placeholder links; `organization.update` shows “organization foundation” text only — **no org profile editor** |
| `/crm/settings` | Operational CRM sources (existing M3) |
| Onboarding routes | **None** (`onboard*` paths not present) |
| First-login behavior | `getIdentityState()` → active shell if mapped + active user + active org; **no setup redirect** |

Organization metadata required by existing product semantics already exists on `organization` with sensible defaults; no separate “readiness” table exists.

### B.4 Staff seats & M6 entitlement

| Concept | Location | Notes |
|---------|----------|-------|
| `organization_entitlement.staff_limit` | Default **5** | Comment: runtime product authority, **not** billing |
| `count_member_staff_seats(org)` | M6-T02 | Counts `app_user` with `membership_status = member`, excluding primary Owner |
| Seat enforcement | `create_staff_membership_record`, provisioning finalize, lifecycle restore | Transactional `FOR UPDATE` on entitlement; `staff_seat_limit_exceeded` |
| Owner visibility | `fetch_center_account_administration` RPC + `/users` UI | Shows limit, usage, primary Owner card |
| RLS on entitlement | SELECT for primary Owner only | **No** authenticated UPDATE/INSERT/DELETE |

Staff limit today is **database-derived from `organization_entitlement.staff_limit`**, default 5 at row creation. Dev seed raises org A to 24 for test headroom only.

### B.5 Subscription / commercial representation

**No** tables or fields for:

- commercial plan catalog  
- center subscription lifecycle  
- provider-neutral billing metadata  
- trial/expiry/payment state  

`organization.status = inactive` is the only center-wide “off switch” wired into auth context (`current_app_user_id()` / `getIdentityState()` require active org).

Finance “billing contact” and tuition “billing frequency” are **guardian/enrollment** concepts (M1–M3), unrelated to SaaS subscription.

### B.6 Access guards (RBAC layer)

| Layer | Implementation |
|-------|----------------|
| Session | `src/proxy.ts` + Supabase session refresh |
| Identity | `src/lib/auth/get-identity-state.ts` — Auth JWT → `app_user` → org `status` |
| Protected shell | `src/app/(protected)/layout.tsx` — redirect login or `AccessDenied` |
| Permissions | RPC `has_permission`, RLS `is_active_app_user()` + permission codes |
| Owner admin | `/users` gated on `center_account.manage` (primary Owner only in practice) |
| Staff provisioning | Server action → `begin_staff_provisioning` (authenticated) + Admin API orchestration (service) |

**No middleware.ts**; Next 16 uses `src/proxy.ts` per M0 docs.

There is **no** second-layer check for “center subscription commercially active.”

### B.7 User provisioning (staff vs center)

| Flow | Mechanism |
|------|-----------|
| **Staff** | M6-T03 pipeline: Owner-initiated, idempotent, cross-system Auth + DB |
| **New center + Owner** | **Undefined product path** — manual SQL + `scripts/seed-auth-users.mjs` pattern in dev only |
| Auth user creation | `createAdminClient()` in staff orchestration only (`src/lib/staff-provisioning/orchestrate.ts`) |
| `app_user` INSERT | Revoked for `authenticated`; trusted/service paths only |

### B.8 Tests & fixtures

- SQL: `supabase/tests/m6_t02_*`, `m6_t03_*`, `m6_t05_*`, `m6_t06_*` cover owner, seats, provisioning, isolation.  
- E2E: `tests/e2e/m6-*`, full suite per M6 closeout.  
- `supabase/seed.sql` explicitly **not for production**.

---

## C. Gaps — what blocks a paying center today

### C.1 Required for M7 (commercial readiness)

1. **Production-safe center provisioning** — single trusted operation creating org + entitlement + canonical roles (already triggered) + Auth user + `app_user` + primary Owner + Owner `center_manager` assignment.  
2. **Subscription domain** — represent plan + center subscription status independently of M6 seat row.  
3. **Entitlement linkage** — RIUDA updates subscription/plan → effective `staff_limit` (and future caps) without Owner self-service mutation.  
4. **Commercial access enforcement** — orthogonal to RBAC; block mutations (and define staff login rules) when subscription is not usable.  
5. **Owner onboarding UX** — minimal setup (org name/locale/timezone as needed) and path into normal workspace.  
6. **Owner subscription/status UX** — plan name, subscription status, seat allowance/usage, restriction messaging (no checkout).  
7. **Operator boundary** — documented service_role RPCs/scripts for provision/activate/suspend/assign plan (no large back-office required for v1).

### C.2 Useful later (not blocking first commercial v1)

- Owner self-service password reset / invitation email product flows (M0 deferred).  
- Automated billing provider sync, invoices, checkout.  
- Explicit `organization.setup_completed_at` audit trail beyond inferred readiness.  
- Dedicated RIUDA admin UI (vs scripts + RPC).  
- Distinct “operational inactive” vs “commercial suspended” UX copy at org level.

### C.3 Explicitly unnecessary for M7

- Per-staff subscriptions, multi-Owner, Owner transfer, enterprise SSO.  
- Pricing amounts, tax, payment instruments.  
- Reopening M6 staff lifecycle or M1–M5 domain authorization semantics.  
- Replacing `organization_entitlement` with a single ambiguous “subscription” blob.

---

## D. Proposed canonical model

### D.1 Center onboarding model

**Trusted provisioning (RIUDA/operator or automated job using service_role + Auth Admin):**

```text
provision_center (trusted)
  → INSERT organization (name, locale, timezone, currency defaults)
  → triggers: cost groups, CRM seeds, access foundation (entitlement + roles)
  → INSERT organization_subscription (status = provisioning, default plan)
  → Auth Admin: create user (Owner email)
  → INSERT app_user (member, active)
  → set_primary_owner_for_organization
  → assign center_manager user_role to Owner (internal/trusted)
  → subscription status → active when operator confirms (or auto after Owner first login + setup)
```

**Owner first use (application layer):**

```text
Owner signs in (mapped app_user, active org)
  → optional: redirect if setup incomplete (primary Owner only)
  → complete minimal org profile (organization.update)
  → enter normal AppShell
  → staff creation remains optional (/users when ready)
```

**Readiness recommendation:** **Small explicit state** on subscription or organization extension:

- `setup_completed_at timestamptz NULL` on `organization` (or subscription row), set by Owner via one RPC/action when required fields confirmed.  
- **Tradeoff:** Inferring readiness from `name IS NOT NULL` is fragile (name always required on INSERT). Explicit timestamp avoids magic strings and supports “skip wizard on re-login” cheaply.  
- Avoid a large onboarding state machine; **two states** suffice: `setup_pending` / `setup_complete` derived from nullable timestamp.

### D.2 Subscription model (provider-neutral)

Four concepts stay separate:

| Layer | Purpose |
|-------|---------|
| **Plan definition** | What a commercial package *means* (code, display name, default staff seats, optional capability flags) — **no prices** |
| **Center subscription** | Which plan applies to which org, lifecycle status, effective dates |
| **Entitlement (runtime)** | Effective limits applied to the center — continues **`organization_entitlement`** as M6 authority for seats |
| **Seat usage** | M6 `count_member_staff_seats` — unchanged consumption semantics |

Relationship:

```text
commercial_plan.default_staff_seat_limit
        ↓ (trusted sync on plan assign / subscription activate)
organization_entitlement.staff_limit
        ↓ (M6 authoritative enforcement)
count_member_staff_seats / provisioning / lifecycle
```

Do **not** rename `organization_entitlement` to `subscription`. Extend with optional `commercial_plan_id` / `organization_subscription_id` FK for traceability, or sync via RPC only.

### D.3 Subscription lifecycle (minimal)

Recommended statuses on **`organization_subscription`**:

| Status | Owner sign-in | Staff sign-in | Read data | Mutations | `/users` | Reactivation | Historical data |
|--------|---------------|---------------|-----------|-----------|----------|--------------|-----------------|
| **provisioning** | Yes (setup) | No (no staff yet) | Yes (empty/minimal) | Owner: setup + profile only; block domain mutations until active | No staff to manage; Owner may view status | Operator activates | Preserved |
| **active** | Yes | Yes (RBAC) | Yes | Yes (RBAC) | Owner full | N/A | Preserved |
| **suspended** | Yes (status UX) | No (identity denied or read-only shell) | Yes | **No** (DB-enforced) | Owner read-only status; no new staff | Operator reactivates | **Never deleted** |
| **cancelled** | Yes (limited: export/status/contact copy) | No | Yes (read-only) | No | No provisioning | Manual new subscription row / reprovision policy T07 | **Never deleted** |

Notes:

- Do **not** introduce `past_due` until payment integration exists; suspension is operator-driven.  
- **`organization.status = inactive`** remains a separate RIUDA hard kill (already blocks all users via `current_app_user_id()`). Subscription suspension should use the **commercial layer** so Owner can still authenticate for status unless org is also inactive.

### D.4 Access enforcement architecture

Two independent questions (locked):

1. **RBAC:** `has_permission` / RLS — unchanged M1–M6 semantics.  
2. **Commercial entitlement:** new **`center_subscription_allows(p_mode)`** (name TBD) reading subscription status (+ optional setup gate).

| Layer | Role |
|-------|------|
| **Database / RPC** | **Authoritative** for mutations: call `assert_center_commercially_entitled('mutate')` at start of SECURITY DEFINER RPCs that already use `is_active_app_user()`. RLS optional secondary guard on INSERT/UPDATE policies. |
| **Server actions** | Same check before orchestration (fail fast, localized errors). |
| **Route/layout** | UX: redirect Owner to setup or status page; banner for suspended; **not** sole security boundary. |
| **Navigation** | Hide mutate nav items when read-only; Owner retains subscription/settings entry points. |

Do **not** fold subscription into `has_permission`. Do **not** rely only on client redirects.

**Staff vs Owner under suspension:** Implement by having `center_subscription_allows('staff_session')` false for non-owners while `center_subscription_allows('owner_session')` true — applied in `getIdentityState()` or a dedicated wrapper used by protected layout **without** breaking Owner status pages.

### D.5 M6 seat integration

- Keep **`staff_limit`** on `organization_entitlement` as the **only** value M6 enforcement reads.  
- M7 trusted RPC **`apply_plan_entitlement_to_organization(org_id)`** updates `staff_limit` from plan (default 5) on activate/plan change.  
- Owners **cannot** UPDATE entitlement (preserve M6-T06 isolation tests intent).  
- Never weaken `FOR UPDATE` seat checks in provisioning/lifecycle.

### D.6 Ownership & security invariants

- At most one primary Owner per org (`primary_app_user_id` + `primary_owner_limit = 1`).  
- At most one **commercially active** subscription row per org (partial unique index on `(organization_id)` WHERE status IN (`provisioning`,`active`,`suspended`)).  
- Subscription/plan mutation: **service_role / operator RPC only**, always scoped by `organization_id` parameter validated against caller role.  
- No authenticated UPDATE on subscription or entitlement tables.  
- Provisioning idempotency keys for center create (avoid duplicate orgs on retry).  
- Cross-org: all new RPCs must use `current_organization_id()` or explicit org argument with service_role audit, never client-supplied org alone for authenticated callers.

---

## E. Proposed schema (additive; not implemented in T01)

Suggested migration sequence (starting after baseline 54):

### E.1 `commercial_plan` (global catalog)

| Column | Type | Notes |
|--------|------|-------|
| `id` | uuid PK | |
| `code` | text UNIQUE | e.g. `base_center` — not a price tier |
| `display_name` | text | Owner-facing |
| `default_staff_seat_limit` | int NOT NULL DEFAULT 5 | Sync target for entitlement |
| `capabilities` | jsonb DEFAULT `{}` | Optional future flags; empty in M7 |
| `status` | text | `active` / `archived` |
| timestamps | timestamptz | |

Seed one default plan in migration (no pricing fields).

### E.2 `organization_subscription`

| Column | Type | Notes |
|--------|------|-------|
| `id` | uuid PK | |
| `organization_id` | uuid FK → organization | |
| `commercial_plan_id` | uuid FK → commercial_plan | |
| `status` | text | `provisioning`, `active`, `suspended`, `cancelled` |
| `effective_from` | date | |
| `effective_to` | date NULL | End of cancelled period |
| `provisioned_at` | timestamptz | |
| `activated_at` | timestamptz NULL | |
| `suspended_at` | timestamptz NULL | |
| `cancelled_at` | timestamptz NULL | |
| timestamps | timestamptz | |

Partial unique: one open subscription per org (see D.6).

### E.3 `organization` extension (optional)

| Column | Type | Notes |
|--------|------|-------|
| `setup_completed_at` | timestamptz NULL | Owner onboarding complete |

### E.4 `organization_entitlement` extension (optional FKs)

| Column | Type | Notes |
|--------|------|-------|
| `commercial_plan_id` | uuid NULL FK | Last applied plan |
| `organization_subscription_id` | uuid NULL FK | Active subscription link |

### E.5 Functions / RPCs (trusted unless noted)

| Function | Grant | Purpose |
|----------|-------|---------|
| `provision_customer_center(...)` | service_role | Atomic orchestration entry (org + subscription + owner membership steps) |
| `activate_organization_subscription(org_id)` | service_role | provisioning → active; sync entitlement |
| `suspend_organization_subscription(org_id)` | service_role | commercial suspend |
| `reactivate_organization_subscription(org_id)` | service_role | suspended → active |
| `assign_organization_plan(org_id, plan_id)` | service_role | Plan change + entitlement sync |
| `apply_plan_entitlement_to_organization(org_id)` | internal | Sets `staff_limit` from plan |
| `center_subscription_allows(p_mode text)` | authenticated | Modes: `owner_session`, `staff_session`, `mutate`, `read` |
| `assert_center_commercially_entitled(p_mode text)` | internal | Raises on violation |
| `fetch_owner_commercial_status()` | authenticated | Owner-only JSON: plan, status, seats (extends administration payload) |
| `complete_center_setup(...)` | authenticated | Primary Owner; sets `setup_completed_at`, validates org fields |

Integrate `assert_center_commercially_entitled('mutate')` incrementally in M7-T04 (high-risk RPCs first: provisioning, lifecycle, financial mutations) without changing permission codes.

---

## F. Proposed UX

| Route / surface | Audience | Purpose |
|-----------------|----------|---------|
| `/onboarding` (new) | Primary Owner, setup incomplete | Compact form: center name, default locale, timezone (reuse org fields); submit → `setup_completed_at` |
| `/settings` (extend) | Users with `organization.update` | Real org profile editor (today placeholder) |
| `/users` (extend) | Primary Owner | Add subscription/plan/status strip above existing seat summary (`CenterAccountSummary`) |
| `/account` or `/settings/subscription` (new, optional) | Primary Owner | Dedicated commercial status if `/users` too crowded — T06 decision |
| `/login` | Public | Unchanged |
| Access denied / subscription suspended | Staff | Clear message; contact Owner/RIUDA |

**Reuse:** `CenterAccountSummary`, `fetch_center_account_administration` patterns, `AccessDenied`, existing form components from academic/CRM settings.

**No:** checkout, invoices, card management, pricing page, upgrade purchase.

---

## G. Security model

| Threat | Mitigation |
|--------|------------|
| Cross-org subscription mutation | service_role-only RPCs; no authenticated GRANT on subscription tables; parameter validation |
| Owner modifies own `staff_limit` | No entitlement UPDATE for authenticated (existing); plan changes operator-only |
| Staff performs commercial actions | RPCs check `is_primary_owner()` for admin/commercial read surfaces |
| RPC bypass while suspended | `assert_center_commercially_entitled` at RPC entry; SQL tests direct `authenticated` calls |
| Stale subscription cache | Single source in Postgres; no client-side entitlement |
| Seat limit bypass under suspension | Provisioning/lifecycle already seat-check; add commercial assert before seat-consuming ops |
| Suspended center mutating via RLS | Extend policies or rely on RPC-only mutations for sensitive paths (prefer RPC assert + RLS read-only mode T04) |
| Duplicate primary Owner | Existing entitlement + triggers |
| Accidental multi-org provision | Idempotent `provision_customer_center` with external idempotency key; unique constraints on operator-supplied customer key (T02) |

Authoritative enforcement: **Postgres RPC + RLS**, with server actions mirroring for UX.

---

## H. Testing plan (M7 acceptance)

| Area | Coverage |
|------|----------|
| Center provisioning | SQL: new org has entitlement, roles, subscription row, Owner, center_manager role; idempotent retry |
| Primary Owner invariant | Single primary; cannot lifecycle-remove Owner (M6 regression) |
| Default entitlement | `staff_limit = 5` after provision unless plan overrides |
| Plan → entitlement sync | Changing plan updates limit; M6 seat tests still pass |
| Owner setup | Playwright: first Owner completes onboarding, lands on workspace |
| Subscription enforcement | SQL: suspended blocks `begin_staff_provisioning`, financial RPC mutate, staff session; Owner can open status |
| Staff under restriction | E2E: staff login denied or read-only per design |
| Direct RPC abuse | `m7_*_security_tests.sql` pattern from M6-T06 |
| Cross-org isolation | Subscription rows not visible across orgs |
| M6 seat regression | Full `m6_t03`, `m6_t05`, `m6_t06` remain in verify |
| Reactivation | suspended → active restores mutate |
| Data preservation | Suspend/cancel does not DELETE domain rows |
| i18n | EN/VI keys for onboarding + subscription status |
| Mobile | Owner status/onboarding at 390px |
| Milestone gate | Full `npm run verify` |

---

## I. Recommended task map (T02–T08)

### M7-T02 — Center provisioning & onboarding foundation

**Deliver:** Trusted `provision_customer_center` (service_role), Auth Admin wiring for **Owner** (mirror staff orchestration patterns), idempotency, production runbook/script, SQL tests for happy path + duplicate retry. Assign Owner `center_manager` in trusted path.

**Acceptance:** New org created without manual `seed.sql`; Owner can sign in and holds executive + org admin permissions; M6 tests unchanged.

### M7-T03 — Subscription & entitlement domain

**Deliver:** `commercial_plan`, `organization_subscription`, optional org/setup columns, entitlement FK/sync RPCs, default plan seed, operator activate/suspend/reactivate/assign plan RPCs.

**Acceptance:** Subscription status readable via SQL; `staff_limit` updates only through trusted apply; no authenticated DML on commercial tables.

### M7-T04 — Subscription access enforcement

**Deliver:** `center_subscription_allows` / assert helpers; integrate into mutation RPCs and critical server actions; staff vs Owner session rules; optional RLS read-only phase.

**Acceptance:** Suspended org cannot mutate domain data; Owner session + status fetch works; RBAC tests unchanged.

### M7-T05 — Owner onboarding & center setup UX

**Deliver:** `/onboarding` (or equivalent), `complete_center_setup`, redirect gate in protected layout for incomplete setup, minimal org form EN/VI.

**Acceptance:** Playwright: provisioned Owner completes setup once; skips when complete.

### M7-T06 — Owner subscription / commercial status UX

**Deliver:** Plan name, subscription status, seats used/limit, restriction banners; extend `/users` or dedicated route; i18n.

**Acceptance:** Owner sees accurate status; staff do not see operator controls; no payment UI.

### M7-T07 — Integration, security & production hardening

**Deliver:** `m7_t07_security_isolation_tests.sql`, operator documentation, provisioning script hardening, regression fixes, performance sanity on status RPC.

**Acceptance:** Security suite green; cross-org cases covered; M1–M6 smokes pass.

### M7-T08 — Final acceptance & milestone closeout

**Deliver:** Milestone acceptance SQL, E2E smoke for commercial paths, docs closeout, `npm run verify` exit 0.

**Acceptance:** Same bar as M6-T08 (i18n parity, Playwright full suite, verify).

**Boundary adjustments vs initial outline:** T02/T03 split **provisioning** from **subscription schema** so enforcement (T04) can land on stable RPCs. UX (T05/T06) deliberately follows enforcement to avoid cosmetic-only subscription UI.

---

## J. T01 verdict

**Ready to begin M7-T02:** **Yes**, with no prerequisite code blockers on `main` @ `5eaecac`.

The repository already provides strong M6 foundations (primary Owner, seat entitlement, staff provisioning, Owner `/users`). The missing pieces are **expected** and scoped to M7: trusted **center+Owner provisioning**, **subscription/plan persistence**, **commercial enforcement**, and **minimal Owner UX**.

**Blockers:** None requiring schema hotfix before T02. **Risk note:** Until T02 lands, production onboarding remains manual (SQL + Auth Admin + service_role RPCs), which is **unsafe** for customer rollout but acceptable for continued internal/dev use.

**T01 exit criteria met:** Audit grounded in codebase; canonical model preserves M1–M6; no speculative payment integration; no M7 implementation merged.
