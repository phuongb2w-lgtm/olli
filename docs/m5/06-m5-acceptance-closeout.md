# M5-T09 — Management Intelligence Acceptance & Closeout

**Task:** M5-T09  
**Baseline (T08 accepted):** `b6a063f` — `chore(m5): harden management intelligence`  
**Closeout commit:** `7849edb` — `chore(m5): close management intelligence milestone`  
**Result:** **PASS — M5 CLOSED**

---

## 1. Milestone objective

M5 delivers a **management intelligence and executive reporting layer** over canonical M1–M4 operational data. Reporting RPCs compose domain read models; they do not introduce parallel business truth.

| Domain | Tasks | Status |
|--------|-------|--------|
| Foundation, roles, semantics | T01 / T01.1 | CLOSED |
| Finance intelligence | T02 | CLOSED |
| Academic & quality intelligence | T03 | CLOSED |
| CRM & admissions intelligence | T04 / T04.1 | CLOSED |
| Teaching operations intelligence | T05 | CLOSED |
| Executive cross-domain overview | T06 | CLOSED |
| Executive exceptions & follow-up | T07 | CLOSED |
| UX, permissions, i18n, performance | T08 | CLOSED |
| Final acceptance & closeout | T09 | CLOSED |

Out of scope (not introduced): HR/payroll, LMS hosting, AI recommendations, predictive analytics, opaque scoring, teacher/consultant/room ranking, new scheduling engine, altered finance/CRM/academic core semantics.

---

## 2. Canonical semantics (locked)

### Finance

- **Cash collected ≠ recognized revenue**; recognition follows enrollment recognition configuration/events.
- **Receivables** remain point-in-time outstanding balances, distinct from cash.
- **Consultant revenue** uses approved declaration/review flows only.

### CRM / Admissions

- Productivity and funnel metrics are **event-based** (`lead_status_history`, conversion timestamps).
- Current `lead.status` is not historical truth.
- **Cohort** and **conversion-in-period** attribution follow M3/M5-T04 contracts.
- No consultant ranking/scoring surfaces.

### Academic / Quality

- Draft → submitted → reviewed/finalized workflows retain M5-T03 meaning.
- Academic Operations review is authoritative where required.
- Teacher draft data is not silently promoted to executive truth.
- No teacher ranking/scoring.

### Teaching Operations

- **Projected** vs **materialized** sessions remain distinct.
- **Delivered** = `status = completed` only; cancelled is not delivered.
- Operational date from current `scheduled_start_at` in organization timezone.
- Current `teacher_id` / `room_id` authoritative; `occurrence_date` is provenance/dedup.
- Change metrics use append-only `teaching_session_change.occurred_at`.
- No room utilization percentage without a canonical denominator.

### Executive composition

- `/executive` is a **composition layer** only (`get_executive_overview` delegates to domain RPCs).
- Domain blocks must **byte-match** standalone intelligence RPCs for the same period.

### Exceptions & follow-up

- Source-domain exception detection is independent of `executive_exception_follow_up` state.
- Resolved/dismissed follow-up does **not** suppress a live source exception.
- `build_executive_exception_key` provides stable identity; history is auditable via `list_executive_exception_follow_up_history`.

---

## 3. Major routes

| Audience | Routes |
|----------|--------|
| Center Manager | `/executive`, `/executive/admissions`, `/executive/quality`, `/executive/operations`, `/executive/exceptions`, domain workspaces |
| Accountant | `/finance/*` (no default executive) |
| Consultant | `/crm/my-work`, `/crm/leads`, `/crm/reports` |
| Academic Operations | `/academic/review`, `/operations/*` (no executive unless granted) |
| Teacher | `/operations/my-teaching`, class session execution (scoped) |

Reporting period query params: `start`, `end`, `compare` (shared contract via `src/lib/reporting/period-contract.ts`).

---

## 4. RBAC matrix (canonical)

| Surface | Manager | Accountant | Consultant | Academic Ops | Teacher |
|---------|---------|------------|------------|--------------|---------|
| Executive overview | ✓ (`report.executive.read`) | ✗ | ✗ | ✗ | ✗ |
| Executive exceptions | ✓ | ✗ | ✗ | ✗ | ✗ |
| Finance intelligence | ✓ | ✓ (finance perms) | ✗ | ✗ | ✗ |
| CRM intelligence | ✓ | ✗ | ✓ (`lead.read`) | per lead perms | ✗ |
| Academic review / quality | ✓ | ✗ | ✗ | ✓ (review/read) | scoped record/read |
| Operations intelligence | ✓ | ✗ | ✗ | ✓ (`enrollment.read`) | scoped my teaching |
| My Teaching | ✓ | ✗ | ✗ | optional | ✓ |

Dev seed mapping: `admin` → Manager; `staff` → mixed read (not a product role); dedicated M5 fixture users for consultant/academic/teacher E2E.

---

## 5. M5 migrations

**Total repository migrations:** 49  
**Latest M5 migration:** `20260921100000_m5_t08_worklist_summary_efficiency.sql`

M5 added 11 migrations (T01 through T08). Fresh `supabase db reset` applies all 49 cleanly (verified in T09).

No duplicate reporting truth tables; follow-up is isolated in `executive_exception_follow_up` with org-scoped uniqueness on `exception_key`.

---

## 6. Acceptance artifacts (T09)

| Artifact | Purpose |
|----------|---------|
| `supabase/tests/m5_milestone_acceptance_tests.sql` | 16 cross-domain SQL acceptance scenarios |
| `tests/e2e/m5-acceptance.spec.ts` | Role smoke + EN/VI executive walkthrough |
| Domain suites `m5_t01` … `m5_t08` | Retained; not duplicated in T09 suite |

---

## 7. Verification summary (final T09 run)

| Gate | Result |
|------|--------|
| Fresh DB reset + all migrations (49) | PASS |
| M5 milestone acceptance SQL | **16 / 16 PASS** |
| M5 domain SQL (T01–T08 incl. hardening) | PASS (e.g. T07 39/39, T08 17/17) |
| M0–M4 regression SQL | PASS (full `db:verify:supabase` chain) |
| i18n EN/VI parity | **1801 / 1801** keys |
| lint / typecheck / build | PASS |
| Node smoke + API security | PASS |
| Playwright (`test:app`) | **180 / 180 passed** (~12.6m, 1 worker) |
| `npm run verify` | **exit 0** (2026-09-21 local, post stack stabilization) |

### T09 infrastructure note

Local Supabase intermittently failed health checks on `studio` / `edge_runtime` / `pg_meta` (502 / unhealthy; Studio container logs showed port **3000** conflict with host Next.js). **`npx supabase start --ignore-health-check`** (already in `scripts/supabase-verify.ps1`) restores **API_URL** and auth seed when Postgres/Kong/Auth are usable. No migration or product semantic changes were required.

### T09 E2E stabilization (no assertion weakening)

Deterministic test fixes only: wait for localized sign-out after locale switch (VI `đăng xuất`); strict-mode section headings (`level: 2`); operational calendar materialized/projected assertions via `data-entry-type`; SL-7 student list smoke uses `HV001` search after heavy DB verify; extended timeouts on slow executive/quality navigation under full suite load.

---

## 8. Performance (T08 baseline retained)

- T08 worklist summary RPC avoids unbounded per-row history loads.
- Executive overview composes four domain RPCs once each (no duplicated formulas in UI).
- Teacher-scoped reads remain bounded via existing M4/M5 RPC filters.

---

## 9. Technical debt

**Blocking:** none at closeout.

**Non-blocking:**

- Production role templates (Teacher/Consultant/Accountant) still configured manually vs seed `admin`/`staff`.
- `/users` management UI remains foundation-level.
- `report.read` permission placeholder unused in product navigation.
- Academic teacher confirmation workflow gap documented in T01 (teacher data canonical immediately).

---

## 10. T08 entry record

M5-T08 accepted at `b6a063f` on `main` with clean tree, domain hardening tests (17), E2E hardening (8), and full verify green prior to T09 closeout work.

**M5 — CLOSED.** Do not begin M6 unless explicitly requested.
