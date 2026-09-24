# M7-T08 — Commercialization / Subscription — Final Acceptance & Closeout

**Task:** M7-T08  
**Baseline (T07 accepted):** `2d77205a701797cf46fb8158b3e91f400b75d647` — `chore(m7): harden commercialization integration for T07`  
**Closeout commit:** `chore(m7): close commercialization milestone` — see §9 for final SHA after commit  
**Result:** **PASS — M7 CLOSED**

---

## 1. Milestone objective

M7 adds the **commercialization layer** for small-center SaaS operation: trusted center provisioning, provider-neutral subscription and entitlement, DB-authoritative commercial access, Owner commercial status UX, and Primary Owner first-use onboarding—without changing accepted M1–M6 domain semantics or introducing payment/checkout scope.

| Task | Focus | Status |
|------|--------|--------|
| T01 | Commercial readiness audit & design gate | CLOSED |
| T02 | Trusted center + primary Owner provisioning | CLOSED |
| T03 | Subscription & entitlement domain | CLOSED |
| T04 | Commercial access enforcement | CLOSED |
| T04.1 | Regression stabilization | CLOSED |
| T05 | Owner subscription / commercial status UX | CLOSED |
| T06 | Owner onboarding & center setup UX | CLOSED |
| T07 | Integration & production hardening | CLOSED |
| T08 | Final acceptance & milestone closeout | CLOSED |

Authoritative integration reference: [06 — Commercialization milestone contract](./06-m7-commercialization-milestone-contract.md).

---

## 2. Final authoritative state machine (summary)

- **Subscription:** `provisioning → active`; `active → suspended | cancelled`; `suspended → active | cancelled`; **`cancelled` is terminal** (operator/service_role RPCs only).
- **Entitlement:** `organization_entitlement.staff_limit` synchronized from plan/subscription; seat usage via M6 `count_member_staff_seats`.
- **Commercial access:** `has_permission()` / `is_active_app_user()` gated on **active** subscription for normal use; session UX via `fetch_session_commercial_access()` (not authorization).
- **Onboarding:** `setup_completed_at` NULL + allowed subscription → `requires_center_setup`; `complete_center_setup()` one-time; suspended/cancelled cannot complete setup.
- **Landing (UX):** onboarding → restricted Owner/staff surfaces → normal workspace (see contract doc).

---

## 3. M7 migrations

**Total repository migrations:** 58  
**M7 migrations (4):**

| Migration | Task |
|-----------|------|
| `20260926100000_m7_t02_trusted_center_owner_provisioning.sql` | T02 provisioning graph, idempotency |
| `20260927100000_m7_t03_subscription_entitlement_domain.sql` | Plan, subscription, entitlement, operator RPCs |
| `20260928100000_m7_t04_commercial_access_enforcement.sql` | Session access, RBAC commercial gate |
| `20260928110000_m7_t06_owner_onboarding_center_setup.sql` | `setup_completed_at`, onboarding RPCs, backfill |

Ordering is chronological; no duplicate or future-dated M7 migrations. T04.1 and T07 required **no** additional schema. Existing orgs: backfill + seed set `setup_completed_at` so fixtures do not re-enter onboarding.

---

## 4. Acceptance matrix

Each row maps milestone acceptance to authoritative implementation and automated evidence.

| Area | Acceptance criterion | Evidence |
|------|---------------------|----------|
| **Provisioning** | Service orchestration creates org, Primary Owner, provisioning subscription, entitlement (staff_limit 5), setup incomplete | T02 SQL (8), `test:center-provisioning`, T07 SQL #2, smoke SC-4/SC-7 |
| **Idempotency** | Retry does not duplicate org/commercial graph | T02 SQL, center provisioning smoke CP-5 |
| **Subscription lifecycle** | All allowed transitions; invalid rejected; cancelled terminal | T03 SQL (18), `test:subscription-commercial` |
| **Entitlement sync** | Plan/lifecycle changes sync `organization_entitlement.staff_limit` | T03 SQL #8–9, T05 SQL #3 |
| **Staff seats** | Used count = M6 semantics; `/users` and status RPC agree | T05 SQL #3, M6-T04/T05 SQL, integration E2E seat scenario |
| **Commercial access** | Suspended/cancelled/provisioning block normal RBAC; reactivation restores | T04 SQL (20), `test:commercial-access`, commercial-access E2E |
| **Direct routes** | RPC/mutations denied when restricted | T04 SQL #11–12, integration E2E bypass tests |
| **Owner status UX** | `fetch_owner_commercial_status`; staff denied; no operator EXECUTE for Owner | T05 SQL (6), owner-subscription E2E |
| **Owner onboarding** | One-time setup; staff/suspended/cancelled denied | T06 SQL (8), onboarding E2E |
| **Landing priority** | Setup before restricted Owner surfaces | T07 SQL, `resolveAuthenticatedLandingPath`, restricted layout, integration E2E |
| **Owner/staff boundaries** | Staff no onboarding; staff no owner commercial RPC | T06 SQL #6, T05 SQL #2, T04 session tests |
| **Operator boundaries** | Owner cannot suspend/activate/cancel via authenticated EXECUTE | T03 SQL #16, T05 SQL #6, subscription smoke SC-2 |
| **Existing centers** | Backfilled setup complete; active normal use | T06 SQL #1, T07 SQL #1, seed |
| **Reactivation** | Preserves setup and roster | T04 SQL #15–16, commercial-access E2E |
| **M1–M6 regression** | Full `db:verify` + verify chain | `scripts/supabase-verify.ps1`, `npm run verify` |

### Milestone scenario checklist (T08)

| # | Scenario | Matrix / suite |
|---|----------|----------------|
| 1 | New center provisions successfully | T02, smoke CP-4 |
| 2 | Primary Owner created correctly | T02, T07 |
| 3 | Subscription starts provisioning | T03, smoke SC-4 |
| 4 | Entitlement & staff limit initialized | T02/T03, smoke |
| 5 | New Owner routed to onboarding | T07, onboarding E2E |
| 6 | Setup complete while still provisioning-restricted | T07 SQL, integration E2E |
| 7 | Operator activation enables normal use, keeps setup | T03 #7, T07, smoke SC-5 |
| 8 | Active setup-incomplete forced onboarding | T06/T07, onboarding E2E |
| 9 | Active setup-complete → normal workspace | T07 #1, landing helpers |
| 10 | Staff never enters Owner onboarding | T06 #6 |
| 11 | Staff cannot access Owner subscription management | T05 #2, routes/guards |
| 12 | Suspended Owner restricted UX | T04, commercial-access E2E |
| 13 | Suspended staff blocked from workspace | T04, E2E |
| 14 | Suspended: no onboarding or `/users` bypass | T06 #7, T04 |
| 15 | Reactivation restores access, preserves state | T04 #15–16, E2E |
| 16 | Cancelled terminal | T03 #14 |
| 17 | Cancelled no bypass | T04, T06 #8 |
| 18 | Seat display matches enforcement | T05 #3, M6 + integration E2E |
| 19 | Full-seat create/restore rejected | M6-T05, users E2E |
| 20 | Direct URL cannot bypass gates | T04, T07 E2E |
| 21 | Existing centers not forced onboarding | T06 #1, T07 #1 |
| 22 | M1–M6 operational behavior intact | Full verify |

---

## 5. Acceptance artifacts

| Artifact | Purpose |
|----------|---------|
| `supabase/tests/m7_t02_center_provisioning_tests.sql` | Provisioning & idempotency |
| `supabase/tests/m7_t03_subscription_entitlement_tests.sql` | Lifecycle & entitlement (18) |
| `supabase/tests/m7_t04_commercial_access_tests.sql` | Access enforcement (20) |
| `supabase/tests/m7_t05_owner_subscription_status_ux_tests.sql` | Owner commercial read (6) |
| `supabase/tests/m7_t06_owner_onboarding_center_setup_tests.sql` | Onboarding (8) |
| `supabase/tests/m7_t07_commercialization_integration_tests.sql` | Cross-task integration (10) |
| `scripts/center-provisioning-smoke.mjs` | End-to-end provisioning smoke |
| `scripts/subscription-commercial-smoke.mjs` | Subscription lifecycle + SC-7 setup state |
| `scripts/commercial-access-smoke.mjs` | Session access smoke |
| `tests/e2e/m7-commercial-access.spec.ts` | Restricted routing E2E |
| `tests/e2e/m7-owner-subscription.spec.ts` | Owner status surfaces |
| `tests/e2e/m7-owner-onboarding.spec.ts` | Onboarding flow |
| `tests/e2e/m7-commercialization-integration.spec.ts` | T07 integration E2E (4) |

---

## 6. Security boundaries (T08 review)

Reviewed at closeout (no schema changes required):

- **SECURITY DEFINER** provisioning, subscription operator RPCs, `fetch_session_commercial_access`, `fetch_owner_commercial_status`, onboarding RPCs: EXECUTE grants limited to intended roles; operator mutations not granted to `authenticated`.
- **Primary Owner** onboarding and operational reads use `is_operational_primary_owner()` where defined; normal RBAC uses commercial-active gating.
- **UI redirects** in protected/restricted layouts are UX-only; RLS, `has_permission()`, and RPC guards remain authoritative.
- **Staff** cannot invoke Owner commercial status or complete center setup; **Owner** cannot invoke operator lifecycle RPCs.

---

## 7. Routes & surfaces (final)

| Surface | Audience | Shell |
|---------|----------|--------|
| `/onboarding` | Primary Owner, setup required | Minimal onboarding layout |
| `/subscription` | Owner, normal use + `center_account.manage` | Protected AppShell |
| `/subscription-status` | Primary Owner, commercially restricted | Restricted layout |
| `/commercial-access` | Restricted staff | Restricted layout |
| `/users` | Owner administration | Protected; commercial + RBAC enforced on mutations |

---

## 8. Deferred scope (explicitly not M7)

Payment processing, checkout, recurring billing, invoices, billing history, payment cards, public pricing, self-service plan purchase, upgrade/downgrade purchase, operator commercial console UI, full organization profile `/settings` editor. These are **not** blockers for M7 closeout.

---

## 9. Verification summary (T08 final run)

| Gate | Result |
|------|--------|
| Branch `main`, baseline SHA `2d77205…` | Confirmed |
| Working tree clean at start | Confirmed |
| Migrations | **58** |
| Fresh DB reset + `npm run db:verify` | PASS |
| M7-T02 SQL | PASS (8 cases) |
| M7-T03 SQL | PASS (18 cases) |
| M7-T04 SQL | PASS (20 cases) |
| M7-T05 SQL | PASS (6 cases) |
| M7-T06 SQL | PASS (8 cases) |
| M7-T07 SQL | PASS (10 cases) |
| M6 regression (via db:verify) | PASS |
| M0–M5 regression SQL | PASS |
| API security + provisioning + staff + subscription + commercial smokes | PASS |
| `npm run test:i18n` | PASS (1953 / 1953) |
| lint / typecheck / build | PASS |
| `npm run test:types:stale` | PASS |
| M7 Playwright (4 specs) | PASS |
| Full Playwright | **216 / 216** |
| `npm run verify` | **exit 0** (T08 final acceptance run) |
| `npm run test:types:stale` | PASS |

**Closeout commit SHA:** recorded in git history as `chore(m7): close commercialization milestone` (see final report / `git log -1` on `main`).

---

## 10. Technical debt

**Blocking:** none at closeout.

**Non-blocking / deferred:**

- Organization profile `/settings` editor (long-term; onboarding is not settings).
- Timezone field remains free-text with IANA hint where applicable.
- Windows: set `PLAYWRIGHT_BROWSERS_PATH=%LOCALAPPDATA%\ms-playwright` for reliable E2E.
- Full `npm run verify` duration (~30–45 min). T08 observed intermittent flakes in **M5-T06 executive overview SQL** (fresh reset), **OA-5 operations-analytics smoke**, and **M5-T07 executive-exceptions E2E** under long chains; immediate re-run of the failing gate passed. Final T08 acceptance used one green `npm run verify` (exit 0).

---

## 11. T07 entry record

M7-T07 accepted at `2d77205a701797cf46fb8158b3e91f400b75d647` with restricted-layout onboarding guard, T07 SQL/E2E, milestone contract doc, and full verify green prior to T08 closeout.

**M7 — COMMERCIALIZATION / SUBSCRIPTION — CLOSED / PASS.**
