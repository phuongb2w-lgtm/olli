# M6-T08 — Center Administration Acceptance & Closeout

**Task:** M6-T08  
**Baseline (T07 accepted):** `ac3aa71` — `feat(m6): harden center administration ux`  
**Closeout commit:** `chore(m6): close center administration milestone` (SHA in T08 report / `git log -1` on `main` after closeout)  
**Result:** **PASS — M6 CLOSED**

---

## 1. Milestone objective

M6 delivers **center-level user administration** (Owner/Admin, staff entitlement, provisioning, lifecycle, `/users` workspace, security isolation) without altering accepted M1–M5 domain semantics.

| Task | Focus | Status |
|------|--------|--------|
| T01 | Contract & execution plan | CLOSED |
| T02 | Owner, entitlement, canonical roles & permissions | CLOSED |
| T03 | Trusted staff provisioning | CLOSED |
| T04 | Owner `/users` administration workspace | CLOSED |
| T05 | Staff lifecycle & historical integrity | CLOSED |
| T06 | Security, RLS & org isolation | CLOSED |
| T07 | UX, i18n, integration & regression hardening | CLOSED |
| T08 | Final acceptance & closeout | CLOSED |

Out of scope (deferred): Owner transfer, auth-layer disable UI, audit-log UI, teacher-profile auto-sync, legacy `user.read` cleanup, expanded seat purchasing UX, external billing integration.

---

## 2. Canonical semantics (locked)

### Center account model

- One primary subscribed **Owner/Admin** per center (`is_primary_owner`).
- Default entitlement: **5 staff seats** in addition to the Owner (6 logins total).
- Center Owner administers staff; RIUDA/Olli manages center subscription entitlement.

### Authorization

- `/users` administration is **Owner-only** (`center_account.manage` / primary owner checks).
- UI visibility is not the security boundary; server actions and RPC/RLS remain authoritative.

### Lifecycle

- Distinct states: **active**, **inactive**, **locked**, **removed** with accepted transition matrix (T05/T07).
- Removed staff restore consumes a seat; full-seat restore returns localized product error without mutating roster.

### Owner invariants

- No Owner deletion, suspension, transfer, or multiple primary Owners introduced in M6.

---

## 3. M6 migrations

**Total repository migrations:** 54  
**M6 migrations (5):**

- `20260922100000_m6_t02_owner_entitlement_access_foundation.sql`
- `20260922110000_m6_t02_harden_test_fixture_grants.sql`
- `20260923100000_m6_t03_trusted_staff_provisioning.sql`
- `20260924100000_m6_t04_center_account_administration.sql`
- `20260925100000_m6_t05_staff_lifecycle.sql`

Fresh `supabase db reset` + `scripts/supabase-verify.ps1` applies all 54 migrations and seeds cleanly.

---

## 4. Acceptance artifacts

| Artifact | Purpose |
|----------|---------|
| `supabase/tests/m6_t02_access_foundation_tests.sql` | 25 — owner, entitlement, roles |
| `supabase/tests/m6_t03_staff_provisioning_tests.sql` | 10 — Auth Admin boundary, idempotency |
| `supabase/tests/m6_t04_center_account_administration_tests.sql` | 10 — `/users` RPC contract |
| `supabase/tests/m6_t05_staff_lifecycle_tests.sql` | 56 — lifecycle & seat rules |
| `supabase/tests/m6_t06_security_isolation_tests.sql` | 18 — cross-org / executive defense |
| `tests/e2e/m6-users-administration.spec.ts` | Owner workspace, provisioning UX |
| `tests/e2e/m6-staff-lifecycle.spec.ts` | Lifecycle matrix, mobile, full-seat restore |

---

## 5. Verification summary (T08 final run)

| Gate | Result |
|------|--------|
| Fresh DB reset + migrations (54) | PASS |
| M6-T02 SQL | **25 / 25** |
| M6-T03 SQL | **10 / 10** |
| M6-T04 SQL | **10 / 10** |
| M6-T05 SQL | **56 / 56** |
| M6-T06 SQL | **18 / 18** |
| M0–M5 regression SQL (full `db:verify`) | PASS |
| i18n EN/VI parity | **1891 / 1891** keys |
| lint / typecheck / build | PASS |
| Node smoke + API security + M1/M3/M5 acceptance | PASS |
| Playwright (`test:app`) | **196 / 196** passed |
| `npm run verify` | **exit 0** |

### T08 infrastructure notes

- **`supabase db lint`:** One early T08 `npm run verify` attempt failed immediately after seed when `supabase db lint` returned non-zero on Windows despite JSON warnings-only output; immediate re-run of `db:verify` passed. No product or migration change required; canonical verify script unchanged.
- **Playwright full-seat restore E2E:** Stabilized seat-usage polling after provisioning so the org-C capacity scenario does not over-fill before the victim account step (`tests/e2e/m6-staff-lifecycle.spec.ts`).

---

## 6. Technical debt

**Blocking:** none at closeout.

**Non-blocking / deferred:**

- Owner transfer, auth ban/disable UX, audit-log UI (per T01/T07).
- Modal refactor for lifecycle confirmations (inline regions retained).
- Legacy `user.read` permission cleanup.
- Automatic teacher-profile synchronization on role assignment.
- Production role templates vs dev seed `admin`/`staff` mapping.

---

## 7. T07 entry record

M6-T07 accepted at `ac3aa71` on `main` with UX/i18n hardening, `requireCenterAccountAdmin()` server-action gate, mobile lifecycle E2E, and full verify green prior to T08 closeout.

**M6 — CLOSED.**
