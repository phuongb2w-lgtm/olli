# CW2-T02.1 — Student sequence bootstrap & acceptance

**Baseline implementation:** `0b738f3`  
**Migration:** `20260930102000_cw2_t02_1_student_sequence_bootstrap.sql`

## Audit summary (pre-CW2 Olli)

| Topic | Finding |
|-------|---------|
| `student.student_code` | Nullable free text; partial unique index per org (M1-T03). Manual entry via Student UI; **not** set by `convert_lead()`. |
| Legacy codes | Examples: `HV001`, empty — **not** CW2 official registrations. |
| CW2 official code | Persisted only as **`CCYYNNNN`** (8 digits); **`0000`** suffix never stored as official. |
| Student delete | No hard delete in normal flows; withdrawn/inactive rows may remain. **Counter never decreases** (no NNNN reuse). |
| `COUNT(student)` | **Rejected** as bootstrap input — does not represent consumed center sequence. |

## Bootstrap policy

### A — New organization (no CW2-shaped codes)

- `last_allocated_sequence = 0`
- T03 first official registration allocates **`0001`**.

### B — Existing org with CW2-shaped `student_code`

- Infer **`NNNN`** only when code matches `^[0-9]{8}$` and digits 5–8 are **`0001`–`9999`**.
- `last_allocated_sequence = MAX(inferred NNNN)` (never lower existing counter).
- **Never rewrite** legacy codes.

### C — Existing org with students but no trustworthy sequence

- Legacy/manual codes **do not** advance the counter.
- **No invented chronology** from student count or portfolio STT.
- First **new** official CW2 allocation may still be **`0001`** while legacy labels coexist (separate namespaces).

### D — Collision with future allocator

- Full-code uniqueness remains on `student`.
- Floor prevents re-issuing **`NNNN`** already present on a shaped stored code.

## Independence

- **Consultant portfolio STT** (`consultant_portfolio_entry.workspace_sequence`) is unrelated to **`organization_student_sequence`**.
- Triggers on `student.student_code` only refresh the org floor; they do not touch portfolio tables.

## Tests

- `supabase/tests/cw2_t02_1_student_sequence_bootstrap_tests.sql` — **8/8** scenarios (legacy, shaped, `0000`, isolation, STT, consultant `01`).

## Verification evidence (local)

| Gate | Result |
|------|--------|
| `npm run db:verify` | **SUCCESS** — includes **CW2-T02 16/16** and **CW2-T02.1 8/8** |
| `supabase db lint` | Warnings only (pre-existing M2/M4/M6 + resolved CW2 loop shadow in migration `20260930103000`) |
| Full `npm run verify` | User run: **failed** at `test:operations-analytics` **OA-5/OA-6** (9/11); **not CW2-related** — isolated re-run of `operations-analytics-smoke.mjs` **11/11 PASS** (likely long-pipeline flake / Supabase service restarts) |

Re-run `npm run verify` once if OA smokes fail at the tail; CW2 SQL regressions were green in the same run through M8 + recovery **6/6**.

## T03 boundary

Student Code **allocator RPC** is **not** implemented in T02.1.
