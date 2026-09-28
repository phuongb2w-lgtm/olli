# CW2-T02.2 — Operations Analytics OA-5 / OA-6 classification

**Baseline:** `1b28c00aedb286cfe4ca52c86e3ea65ed62c8841`  
**Scope:** Classify verify failures in `test:operations-analytics` (OA-5, OA-6). **CW2-T03 not started.**

## Symptoms (reported full verify)

- OA-5 *reschedule effect on workload* — FAIL  
- OA-6 *substitution effect on workload* — FAIL  
- Other OA cases and CW2 SQL gates passed.

## Reproduction

| Scenario | Result |
|----------|--------|
| `node scripts/operations-analytics-smoke.mjs` alone (multiple runs) | **11/11 PASS** |
| After `session-operations-smoke.mjs` | **11/11 PASS** |
| After full `teaching-smoke.mjs` | **11/11 PASS** |
| Back-to-back OA smoke (same DB, no reset) | **11/11 PASS** |

Failures were **not reproduced deterministically** on the seeded local stack after the verify ordering that precedes OA in `npm run verify`.

## Semantic audit (product)

- **Materialized ≠ delivered.** Workload uses materialized `teaching_session` rows bucketed by **local operational date** derived from `scheduled_start_at` in the org timezone (`_list_operational_occurrences` / M4-T07).
- **`reschedule_teaching_session`** updates `scheduled_start_at` / `scheduled_end_at`; **`occurrence_date` stays** (timetable identity / projection dedup). After reschedule, workload must move from old local day to new local day — OA-5 expectation is correct.
- **`substitute_session_teacher`** moves assigned teacher on the materialized session; OA-6 expectation is correct.
- M5-T05 does not alter this bucketing; teacher-only scoping remains on `list_teacher_workload`.

## CW2 causality

Migrations reviewed:

- `20260930100000_cw2_t02_declaration_draft_enum.sql`
- `20260930101000_cw2_t02_domain_schema_foundations.sql`
- `20260930102000_cw2_t02_1_student_sequence_bootstrap.sql`

**No causal path** to `teaching_session`, session operation RPCs, teacher assignment, or M4 workload analytics. CW2 touches consultant codes, declarations, student sequence bootstrap, and related RLS — not operational occurrence math.

## Root cause

The smoke called `reschedule_teaching_session` and `substitute_session_teacher` **without checking RPC errors**. When those RPCs fail (e.g. transient conflict, partial state from an earlier step, or environment timing), workload assertions fail with **no diagnostic**, appearing as product regressions.

Product semantics match passing runs when RPCs succeed.

## Classification

| Test | Class | Rationale |
|------|-------|-----------|
| **OA-5** | **C — Test/harness regression** | Harness omitted RPC error surfacing and class-scoped workload filters; not CW2 product change. |
| **OA-6** | **C — Test/harness regression** | Same silent-RPC pattern; depends on OA-5 reschedule succeeding. |

Not **A** (CW2 product regression): no schema/RPC linkage.  
Not **B** (existing product defect): M4/M5 semantics verified; isolated smokes pass.  
Not **D**: failure was reported once in full verify without local deterministic repro; insufficient evidence to label environmental without RPC error detail from the failing run.

## Harness fix (T02.2)

- Assert `{ error }` on reschedule, substitute, and room change RPCs (aligned with `session-operations-smoke.mjs`).
- Scope OA-5/OA-6 workload queries with `p_class_id` for the fixture class.
- Emit counts in OA-5 detail when workload assertion fails.

## Acceptance

- Targeted OA smoke: **11/11 PASS** (repeated + after teaching/session-operations chain).
- Full `npm.cmd run verify`: **exit code 0** with CW2-T02 **16/16**, T02.1 **8/8**, OA **11/11**.
