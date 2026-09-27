# Consultant Workspace V2 — T01 Audit

**Date:** 2026-09-27  
**Baseline:** `main` @ `c2d2d3d28fbb7d0e47581792e887139fea6ca2e0`  
**Migration count:** 59 (`supabase/migrations/`, latest `20260929100000_m8_t07_app_rate_limiting.sql`)  
**Purpose:** Map Consultant Workspace V2 requirements onto existing Olli M0–M8 architecture. **No implementation in T01.**  
**T01 gate:** **CLOSED / PASS** (final product decisions locked in [design contract](./02-t01-consultant-workspace-v2-design-contract.md)).

**Upstream contracts:** [M3 CRM](../m3-crm-admissions-domain-contract.md), [M1 Student/Guardian](../m1/01-student-guardian-product-contract.md), [M2 Finance](../m2-finance-domain-contract.md), [M5 Role workspaces](../m5/01-role-workspace-contracts.md), [M5 Semantic boundaries](../m5/05-semantic-boundaries.md), [M6 Access](../m6/02-t02-access-foundation-implementation.md)

---

## A. Repository baseline (T01 verification)

| Item | Value |
|------|--------|
| **Starting SHA** | `c2d2d3d28fbb7d0e47581792e887139fea6ca2e0` |
| **Branch** | `main` |
| **Working tree** | Clean at audit start (no staged/unstaged changes before T01 docs) |
| **Migrations** | 59 |
| **Verification run** | `npm run typecheck` — pass; `npm run test:smoke:static` — pass |
| **Full `npm run verify`** | Not re-run in T01 (M7/M8 closeout remains trusted baseline; re-run before first implementation merge) |

---

## B. Current Consultant / CRM architecture

### B.1 Navigation and routes

| Surface | Path | Gate | Behavior today |
|---------|------|------|----------------|
| Sidebar “Admissions” | `/crm/leads` | `lead.read` | Paginated lead list, filters, link to lead detail |
| CRM subnav | `/crm/my-work` | `lead.read` | Personal KPIs, work queue, declaration summary |
| CRM subnav | `/crm/reports` | `lead.read` | Consultant-facing reporting (period filters) |
| CRM subnav | `/crm/settings` | `lead.manage_sources` | Sources/campaigns (managers) |
| Lead detail | `/crm/leads/[id]` | `lead.read` | Pipeline UI, conversion, identity resolution |
| Finance (Accountant) | `/finance/consultant-revenue` | `consultant_revenue.review` | Review table; **no approve/reject UI in app** (RPC exists) |
| Students (Academic Ops) | `/students/*` | `student.read` | **Consultants excluded** by default role template |

Implementation: `src/lib/navigation/app-navigation.ts`, `src/components/crm/crm-nav.tsx`, `src/app/(protected)/crm/*`.

There is **no** unified “my students” grid. Consultants operate across **Lead domain** (pre-conversion) and must use conversion to reach **Student** records they cannot list under `/students`.

### B.2 Domain inventory (reusable)

| Domain | Tables / RPCs | Consultant relevance |
|--------|---------------|----------------------|
| **Lead** | `lead`, `transition_lead_status()`, RLS + `lead.*` | Pre-enrollment rows; `assigned_user_id` = ownership |
| **Lead candidate** | `lead_candidate`, identity resolution RPCs | Prospective learner name/DOB; `is_primary_candidate` |
| **Lead contact** | `lead_contact` | Guardian-like contacts pre-conversion |
| **Lead assignment** | `lead_assignment` | History; `crm_lead_cohort_consultant_user_id()` for attribution |
| **Lead conversion** | `convert_lead()`, `lead_conversion*` | Creates/links `student`, `guardian`, `enrollment` |
| **Student** | `student`, Server Actions | `given_name`, `family_name`, `student_code`, `status`, `date_of_birth` |
| **Guardian** | `guardian`, `student_guardian` | Primary/billing flags; max one primary (app-enforced) |
| **Course / Class** | M1 academic | Authoritative catalog; consultants must not invent courses |
| **Enrollment** | `enrollment` | Lifecycle separate from lead |
| **Enrollment financial terms** | `enrollment_financial_terms`, schedule RPCs, `activate_enrollment_financial_terms` | Authoritative tuition obligation |
| **Charge / Payment** | `charge`, `payment`, `payment_allocation`, `charge_balance`, `record_payment()` | Canonical money |
| **Receivable** | Derived via `charge_balance` | Remaining obligation |
| **Revenue recognition** | `revenue_recognition_event` | Accounting revenue ≠ consultant sales |
| **Consultant declarations** | `consultant_revenue_declaration`, `declare_consultant_revenue()`, `review_consultant_revenue_declaration()` | **Org-level amount + date + description only** — no student/course/enrollment FK |
| **CRM read models** | `get_consultant_crm_overview()`, `list_consultant_work_queue()` | Personal metrics; declarations block uses approved/pending sums |
| **RBAC** | `has_permission()`, canonical consultant template (M6-T02) | `lead.*`, `consultant_revenue.declare` — no `student.read`, no `payment.record` |

### B.3 Semantic layers already locked (M5)

From [M5 semantic boundaries](../m5/05-semantic-boundaries.md) and `src/lib/reporting/consultant-revenue-semantics.ts`:

1. **Declared** — consultant submission (`pending` / resubmitted after `returned`).
2. **Approved declaration** — accountant validated; **not** ledger cash or recognized revenue.
3. **Cash collected** — posted `payment`.
4. **Recognized revenue** — posted `revenue_recognition_event`.

`sum_approved_consultant_declarations()` sums **approved declaration amounts**, explicitly documented as not cash/revenue.

### B.4 Frontend stack (grid-relevant)

- Next.js 16, React 19, Tailwind 4, TypeScript strict.
- **No** data-grid library (`@tanstack/react-table`, AG Grid, etc.) in `package.json`.
- Lists use **static HTML `<table>`** (`LeadListTable`, `StudentListTable`) with server-side query + URL pagination pattern.

---

## C. Requirement mapping — gap analysis

Legend: **S** = already supported · **U** = supported, UI missing · **E** = requires extension · **N** = new schema/domain · **X** = conflicts · **D** = product decision

| # | Requirement | Classification | Notes |
|---|-------------|----------------|-------|
| 1 | Single Excel-like “my students” grid | **U + E** | Leads + converted students need a **unified read model**; no RPC today |
| 2 | Monthly consultant sales header | **E** | Derive from **posted payment/allocation** with consultant attribution (§H); not declaration approvals |
| 3 | Inline cell edit + keyboard nav | **N (UI)** | Not feasible on current static tables at scale |
| 4 | Column filter/sort/resize/hide/pin | **N (UI)** | Same |
| 5 | Row hide (view only) | **N** | No preference store |
| 6 | Per-user grid preferences | **N** | No table |
| 7 | Virtualization 1k–10k rows | **E** | Server cursor + client virtual window |
| 8 | Personal custom columns | **N** | No extension mechanism |
| 9 | STT stable under sort/filter | **N** | No business sequence column |
| 10 | Split họ / tên + UPPERCASE display | **S + U** | Storage: `family_name` + `given_name`; uppercase = **presentation** |
| 11 | Student code `CCYYNNNN` | **X + E** | Free-text `student_code` + partial unique index conflicts with provisional `0000` duplicates |
| 12 | Status Tiềm năng → … | **E + D** | Must derive from lead + student + enrollment + finance; not one column |
| 13 | Max 2 guardians (grid shows primary) | **S + U** | No max-2 DB constraint; unlimited links allowed |
| 14 | Chi tiết → existing profile | **U + E** | No `/students/[id]` hub; consultants lack `student.read` |
| 15 | Tuition cell states (Đóng phí, Cọc, …) | **E + U** | Finance RPCs exist; consultant-scoped summary RPC missing |
| 16 | Payment declaration panel (student, course, amounts) | **X + N** | Current `declare_consultant_revenue(date, amount, text)` insufficient |
| 17 | Draft / Gửi xác nhận workflow | **E** | Declaration status enum has no `draft`; insert = `pending` |
| 18 | Accounting confirm → code + enrollment + sales | **E** | Approve RPC does not assign code, create enrollment, or post payment |
| 19 | Consultant cannot edit status column | **S** | If status is derived in read model |
| 20 | RBAC without finance escalation | **S** | Preserve; add **scoped** read/update permissions, not `payment.record` for consultants |

---

## D. Source-of-truth map (display fields)

| Display field | Authoritative source (target) | Today |
|---------------|------------------------------|--------|
| **STT** | *Proposed:* persisted `consultant_workspace_sequence` per `(org, consultant_user_id, subject)` | None — use list index only in UIs |
| **Họ và tên đệm / Tên** | Pre-conversion: `lead_candidate.family_name` / `given_name` (primary). Post: `student.*` | Same split; lead vs student stores |
| **Mã học viên** | *Proposed:* `student.student_code` when assigned; else **computed** provisional display (not stored) | Nullable free text; manual |
| **Trạng thái (4-value UX)** | Derived function from lead/student/enrollment/charge/payment/declaration (see design contract) | Separate lead status vs `student.status` vs enrollment |
| **Phụ huynh** | Pre: primary `lead_contact`. Post: `student_guardian` + `guardian` where `is_primary_contact` | Supported |
| **Số điện thoại** | `guardian.phone` / `lead_contact.phone` (primary) | Supported |
| **Khóa học (panel)** | `course` via enrollment or lead candidate `target_course_id` | Supported in domain |
| **Học phí / obligation** | Active `enrollment_financial_terms.net_tuition_amount` + charges | RPC `get_enrollment_financial_summary` |
| **Confirmed paid** | Sum posted `payment_allocation` against enrollment charges (not raw declarations) | M2 canonical |
| **Còn thiếu** | Sum `charge_balance.outstanding_balance` for enrollment charges (or summary RPC) | Derived |
| **Payment display label** | Derived from charge status + schedule mode (deposit vs installment) | Partially in M2 |
| **Consultant attribution** | `lead.assigned_user_id`; cohort: `crm_lead_cohort_consultant_user_id()`; conversion snapshot on `lead_conversion` | Supported |
| **Doanh số tháng** | Sum **posted** `payment` / `payment_allocation` amounts in period with **reliable consultant attribution** (see §H); exclude pending declarations | Today: `sum_approved_consultant_declarations` — **wrong KPI for header** (declaration ≠ sales) |

---

## E. State machine mapping (visible lifecycle)

```text
Tiềm năng (provisional display e.g. 02170000)
  → Consultant payment declaration (draft OR submit)
  → Submitted / awaiting Accounting
  → Accounting confirms actual payment (M2 canonical)
  → Registration authoritative
  → Official Student Code allocated (e.g. 02170037)
  → UX Ghi danh
  → Đang học
  → Tốt nghiệp
```

| Visible status | Intended meaning | Canonical signals (deterministic) |
|----------------|------------------|-----------------------------------|
| **Tiềm năng** | Not yet registered under CW2 rules | No **official** `student.student_code`; provisional `CCYY0000` display only |
| **Ghi danh** | Registration authoritative after Accounting payment confirmation | Official immutable `student_code` assigned **and** registration composition complete **and** not yet **Đang học** |
| **Đang học** | Active learner | `student.status = active` **and** exists `enrollment.status = active` (default tie-break) |
| **Tốt nghiệp** | Completed program | `student.status = graduated` (prefer over enrollment-only signals) |

**Lead pipeline statuses** (`new`, `contacted`, …) remain CRM-internal; they must **not** map 1:1 to the four UX statuses.

**Payment declaration states** (orthogonal): `draft` → `pending` → `returned` | `approved` | `rejected` on extended declaration entity.

**Accounting confirmation side effects (single composed, idempotent RPC/workflow — no duplicate ledgers):**

1. Validate declaration (student, course, obligation, amount, context).
2. **`record_payment()` + allocations** once (Accounting-confirmed cash) — idempotent keys prevent double payment.
3. Authoritative **registration** (may compose with or extend `convert_lead()` in future tasks — **do not change `convert_lead()` in T01**).
4. **Official student code** assignment once — allocator idempotent per declaration / payment event.
5. Financial terms / charges per existing M2 rules where applicable.
6. **Consultant monthly sales** read model counts **this confirmed payment/allocation** (attributed), not declaration approval alone.

**Idempotency requirements (locked):** retries, double-clicks, concurrent requests, and network retries must not double-record payment, double-register, assign two codes, assign one code to two students, or double-count consultant sales.

---

## F. Student code — audit findings

### F.1 Current schema

- Column: `student.student_code` nullable text.
- Index: `idx_student_code_normalized_unique` on `(organization_id, lower(btrim(student_code)))` where non-empty ([M1-T03 migration](../supabase/migrations/20260914140800_m1_t03_student_code_unique.sql)).
- Manual assignment via `src/app/actions/students.ts` with conflict error.

### F.2 Conflicts with V2 rules

| Rule | Conflict |
|------|----------|
| Multiple Tiềm năng share `CCYY0000` | **Violates** partial unique index if stored on `student_code` |
| Provisional code not DB identity | Aligns with UUID PK — OK |
| Immutable after official assignment | Requires RPC guard; today consultants can edit via `student.update` (not granted) but Academic Ops can |
| `CC` consultant digit | **No** `app_user.consultant_code` (or similar) in schema — Center Manager = `01` rule needs staff numbering table |
| Concurrency on `NNNN` | **No** allocator — race if two approvals assign codes simultaneously |

### F.3 Sequence exhaustion (`9999`)

Official sequence per `(organization_id, consultant_code, birth_year)` runs **`0001` … `9999`** only.

When the namespace is exhausted: **FAIL CLOSED** — do not allocate another official code, do not reuse a visible `CCYYNNNN`, do not extend the format. Return a deterministic administrative error for operator resolution.

**Allocator must:** `SELECT … FOR UPDATE` on counter row; assign on Accounting payment-confirmation composition; idempotent per declaration/payment event; enforce hard stop at 9999.

---

## G. Payment / tuition workflow audit

### G.1 What exists

| Capability | Location |
|------------|----------|
| Financial terms draft/active | M2-T04 RPCs + `src/app/actions/enrollment-finance.ts` |
| Deposit + remainder schedule | `set_enrollment_payment_schedule_deposit_remainder` |
| Charge generation | `generate_enrollment_charges` on activation |
| Payment recording | `record_payment()` + `src/app/actions/payments.ts` (requires `payment.record`) |
| Declaration lifecycle | `declare_consultant_revenue` / `review_consultant_revenue_declaration` |
| Accountant list | `list_finance_consultant_declarations` (read model) |

### G.2 Gaps vs V2 panel

- Declarations **not linked** to student, course, enrollment, charge, or draft state.
- No consultant UI to declare (permission exists; **no form** in app).
- No accountant **action UI** on `/finance/consultant-revenue` (read-only table).
- **Remaining amount** must use **posted allocations**, not sum of pending declarations (M2 rule).
- **Cọc phí vs Một phần:** M2 distinguishes **deposit schedule** vs generic `charge.status = partially_paid`. Proposal: **Cọc phí** = active terms used deposit schedule **and** outstanding &gt; 0 **and** sum(allocations) &gt; 0; **Một phần** = partially_paid without deposit schedule **or** partial on non-deposit schedule.

### G.3 Double-entry / revenue

Do **not** add a parallel sales ledger. **Consultant sales KPI consumes authoritative M2 posted payment/allocation data with consultant attribution.** Declarations remain operational intake only. **Consultant sales ≠** `consultant_revenue_declaration` approval **≠** `revenue_recognition_event`.

---

## H. Monthly “Doanh số tháng” — finance semantics (locked)

**Rejected:** Using sum of approved `consultant_revenue_declaration` as consultant monthly sales.

**Canonical semantics:**

| Concept | Meaning | Evidence |
|---------|---------|----------|
| **Consultant declaration** | Consultant operational claim / intake | Extended declaration row (`draft` → submitted → reviewed) |
| **Consultant sales** | Money counted toward consultant monthly performance | **Posted M2 payment/cash** (and/or allocations) **attributable** to that consultant in the period |
| **Accounting revenue** | Recognized revenue | Posted `revenue_recognition_event` per existing M2 service-obligation rules |

Rules:

1. **Consultant declaration ≠ Consultant sales.**
2. Self-declared or accountant-**approved** declarations **do not** increment **Doanh số tháng** until authoritative **confirmed payment** exists and is attributed.
3. **Consultant sales ≠ accounting revenue recognition** — a confirmed payment may count immediately for consultant sales while recognition follows M2 timing.
4. **No parallel sales or revenue ledger** — derive sales from existing `payment` / `payment_allocation` (+ attribution join), same as center cash semantics.

Implementation note: today lacks a first-class **consultant attribution on payment**; CW2-T02+ must add attribution storage or deterministic join (e.g. declaration → `approved_payment_id` → payment, enrollment attribution snapshot) without duplicating amounts.

Use existing `resolve_reporting_period()` + month navigation pattern from `ReportingPeriodFilterForm` (`/crm/my-work`).

---

## I. Custom personal fields — alternatives

| Approach | Pros | Cons |
|----------|------|------|
| **A. EAV** (`consultant_custom_field_def` + `consultant_custom_field_value`) | RLS per consultant; typed defs; no collision with canonical columns | More migrations; UI metadata |
| **B. JSONB on lead** (`lead.notes_summary` or new column) | Fast | Not per-consultant; collides with shared lead record |
| **C. JSONB on app_user preferences** | Easy prefs | Wrong scope for per-student values |
| **D. Reuse `lead_activity` payload** | Audit trail | Wrong semantics; pollutes CRM timeline |

**Recommendation:** **A** for values tied to grid subjects; store prefs (column order, hidden rows) in **`consultant_grid_preference`** JSONB scoped to user.

---

## J. RBAC audit

Consultant template (M6-T02): `lead.read/create/update/assign/convert`, `consultant_revenue.declare`, `organization.read`, `identity.read`.

**Missing for V2 (minimum extensions, not broad finance):**

| Permission | Purpose |
|------------|---------|
| `consultant_workspace.read` (or scoped `student.read_attributed`) | Fetch unified grid + detail drawer |
| `consultant_workspace.update` | Inline edit allowed fields on owned prospects/students |
| `consultant_custom_field.manage` | Define personal columns |

Accountants retain `consultant_revenue.review`, `payment.record`, `charge.create`. Consultants must **not** receive `payment.record` or `revenue.recognize` via grid shortcuts.

RLS pattern: extend **SECURITY INVOKER RPCs** with `_assert_consultant_crm_personal_access()` + ownership checks (same as work queue).

---

## K. Grid technology audit

| Option | Fit | Verdict |
|--------|-----|---------|
| Extend current `<table>` | Low bundle | Insufficient for Excel keyboard model, virtualization, controlled edit at 1k+ rows |
| **TanStack Table + Virtual** | Headless; React 19 compatible; MIT | **Recommended** — column resize/filter/visibility/pinning via plugins; custom editors |
| Mature grid (AG Grid, Glide Data Grid) | Feature-rich | Heavier bundle/license review; harder Tailwind integration |

**Do not install in T01.** Add dependency in implementation task with bundle budget note.

---

## L. Performance architecture

| Scale | Strategy |
|-------|----------|
| ~100 rows | Single RPC page; client-side column filter optional |
| ~1,000 rows | Server-side filter/sort; keyset pagination; virtualized viewport (~40–60 rows DOM) |
| ~10,000 rows | Mandatory server cursor (`created_at`, `id` tie-break); debounced filter; no full org load |

Sort/filter must **not** recompute STT (persisted sequence). Newest-first default aligns with `created_at DESC` but STT remains stable field.

---

## M. Concurrency and integrity risks

| Risk | Severity | Mitigation direction |
|------|----------|---------------------|
| Duplicate official student code | High | DB counter + `FOR UPDATE`; idempotent composition RPC; fail closed at 9999 |
| Two accountants confirm same declaration | High | `FOR UPDATE`; single payment + single code path |
| Double-count consultant sales | High | Attribute payments once; idempotent sales aggregation |
| Consultant double-submit declaration | Medium | Idempotency key on submit RPC |
| Double registration / double `convert_lead` | High | Idempotent registration keyed to declaration/payment |
| Stale inline grid edit | Medium | Optimistic concurrency via `updated_at` on underlying row |
| Multiple tabs | Medium | Same as stale edit; server wins |
| Provisional code stored in DB | High | **Never store** `0000` duplicates; display-only |
| Cross-org isolation | High | Existing RLS; new tables must FORCE RLS |
| Role change mid-session | Low | Permission re-check on mutations |

---

## N. Semantic conflicts summary

1. **Unified “student” row spans Lead + Student** — must not merge domains in storage; use read model projection.
2. **Provisional student codes vs unique index** — display-layer or sentinel storage policy required.
3. **Consultant sales vs declaration vs revenue** — three KPIs; header uses **confirmed payment (attributed)** only (§H locked).
4. **Current declaration RPC** — not a tuition/payment declaration; extending table preferred over parallel entity.
5. **Consultant lacks `student.read`** — detail navigation requires scoped permission or RPC-backed profile view.
6. **Four UX statuses vs many canonical statuses** — derived mapping must be documented and tested.
7. **Registration timing** — CW2 locks code on Accounting **payment** confirmation; existing early `convert_lead()` may remain until composition RPC aligns (future task).

---

## O. T01 audit verdict inputs

**Reusable strengths:** M3 lead CRM, M1 people model, M2 finance chain, M5 declaration review RPCs, M5 reporting period, consultant personal CRM RPCs, permission model.

**Largest implementation chunks:** unified read model, student code allocator, extended declaration workflow, grid UX, scoped RBAC.

**Gate:** **PASS (final)** — audit complete; product decisions locked (monthly sales, registration/code workflow, code exhaustion). CW2-T02 not started.
