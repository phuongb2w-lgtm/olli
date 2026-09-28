# CW2-T03 — Official Student Code Allocator

**Migration:** `20260930104000_cw2_t03_official_student_code_allocator.sql`  
**Tests:** `supabase/tests/cw2_t03_official_student_code_allocator_tests.sql` (25 scenarios)

## Contract

**RPC:** `allocate_official_student_code(p_student_id uuid, p_consultant_app_user_id uuid)`  
**Returns:** `official_student_code_allocation_result` (student id, org, official code, CC/YY/NNNN breakdown, `idempotent_replay`).

**Permission:** `payment.record` + active app user in the student’s organization. Intended for future Accounting confirmation composition (CW2-T04+), not Consultant self-service.

**Trusted inputs (only):**

| Input | Role |
|-------|------|
| `p_student_id` | Target authoritative `student` row (must belong to caller org) |
| `p_consultant_app_user_id` | Consultant attribution; must be active `app_user` in same org with valid `consultant_operational_code` |

**Not accepted from clients:** organization id, CC, YY, NNNN, or final code.

### CC (consultant snapshot)

From `app_user.consultant_operational_code` for `p_consultant_app_user_id` (T02 foundation). Primary owner uses `01`. Immutable in the allocated code after issuance.

### YY (birth year snapshot)

From `student.date_of_birth` at allocation time: last two digits of calendar year. Missing DOB → `student_dob_required` (fail closed). No `00`, no “current year” fallback.

### NNNN (center sequence)

From `organization_student_sequence.last_allocated_sequence + 1` under `FOR UPDATE` row lock in the same transaction as persisting `student.student_code`. Scope: organization only. Independent of Consultant Portfolio STT.

## Transactional allocation

1. Lock `student` row (`FOR UPDATE`).  
2. Idempotent return if official code already present.  
3. Reject if non-empty legacy/manual `student_code`.  
4. Validate DOB + consultant.  
5. Lock `organization_student_sequence` (`FOR UPDATE`).  
6. Advance counter via `_cw2_advance_organization_student_sequence` (`FOR UPDATE`, SECURITY DEFINER for RLS).  
7. Set session `cw2.official_student_code_write = 1`, update `student.student_code`.  
8. Commit atomically.

Counter never advances without a successful code persist; persist never succeeds without counter advance in the same transaction.

## Idempotency

If the student already has an official CW2 code, repeat calls return the same code with `idempotent_replay = true` and **do not** consume another NNNN.

## Concurrency

Row locks + unique index `idx_student_org_cw2_nnnn_unique` on `(organization_id, NNNN)` for official codes. Concurrent registrations for different students receive distinct NNNN values; ordering between transactions is not fixed.

## Exhaustion

At `last_allocated_sequence = 9999`, further allocation fails closed. No rollover, reuse, `0000`, or format expansion in T03.

## Bootstrap floor (T02.1)

Allocator respects `last_allocated_sequence` floor from existing CW2-shaped codes. After floor `37`, next issue is `0038`. Does not use `COUNT(student)` or portfolio STT.

## Legacy codes

Students with non-official occupied codes (e.g. `HV001`) → `student_code_already_set`. No silent overwrite. Legacy rows remain editable as non-CW2 codes.

## Manual CW2-shaped entry

Trigger `student_protect_official_code` blocks authenticated inserts/updates of 8-digit official-shaped codes unless session flag `cw2.official_student_code_write` is set (allocator) or role is postgres/service (bootstrap/tests).

## Official code immutability

Once official, `student_code` cannot be changed or cleared via normal update paths (`official_student_code_immutable`).

## NNNN uniqueness

Partial unique index ensures one row per `(organization_id, NNNN)` for official codes, so `02170037` and `05180037` cannot coexist in the same org.

## STT independence

Portfolio `workspace_sequence` / `consultant_portfolio_sequence` are not read or updated by the allocator (regression tests 17–18).

## Deferred (T04+)

- Full declaration → payment → registration composition  
- Consultant grid / UI  
- Administrative code correction workflow  

**CW2-T04 has not been started.**
