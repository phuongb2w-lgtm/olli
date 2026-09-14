# M0-T03 — Data Integrity Tests

**Date:** 2026-09-14  
**Test file:** `supabase/tests/m0_integrity_tests.sql`  
**Runner:** `scripts/db-verify.ps1`

---

## Execution Flow

```text
empty PostgreSQL 15 (Docker)
  → supabase/migrations/20260914140000_m0_foundation.sql
  → supabase/seed.sql
  → supabase/tests/m0_integrity_tests.sql
```

Requirements: Docker Desktop running.

```powershell
powershell -ExecutionPolicy Bypass -File scripts/db-verify.ps1
```

---

## Test Results (25/25 PASS)

| # | Scenario | Expected | Result |
|---|----------|----------|--------|
| 1 | One guardian → two students | Two `student_guardian` rows | **PASS** |
| 2 | One student → two guardians | Two relationship rows | **PASS** |
| 3 | Transfer Class A → B | Two enrollment rows, closed + active | **PASS** |
| 4 | Rejoin same class later | Two non-overlapping enrollments | **PASS** |
| 5 | Overlapping enrollment same class | Exclusion violation | **PASS** |
| 6 | Teacher A then B — old sessions preserved | Session teacher_id unchanged | **PASS** |
| 7 | Change teacher on completed session | Trigger rejection | **PASS** |
| 8 | Duplicate attendance same session/enrollment | Unique violation | **PASS** |
| 9 | Attendance enrollment from wrong class | Trigger rejection | **PASS** |
| 10 | Multiple observations over time | Separate rows preserved | **PASS** |
| 11 | Duplicate indicator on observation | Unique violation | **PASS** |
| 12 | Modify finalized assessment score | Trigger rejection | **PASS** |
| 13 | Partial payment | Balance = 100,000 of 200,000 | **PASS** |
| 14 | One payment → multiple charges | Both balances zero | **PASS** |
| 15 | Multiple payments → one charge | Balance zero | **PASS** |
| 16 | Discount (negative delta) | Reduces outstanding | **PASS** |
| 17 | Correction (positive delta) | Increases outstanding | **PASS** |
| 18 | Zero allocation amount | CHECK violation | **PASS** |
| 19 | New org has 2 cost groups | count = 2 | **PASS** |
| 20 | Duplicate group_slot | Unique violation | **PASS** |
| 21 | Slots are 1 and 2 | Both present | **PASS** |
| 22 | Reparent used expense category | Trigger rejection | **PASS** |
| 23 | Expense group ≠ category group | Trigger rejection | **PASS** |
| 24 | Cross-org enrollment | FK/composite rejection | **PASS** |
| 25 | Cross-org charge (guardian) | FK/composite rejection | **PASS** |

---

## Test Transaction Behavior

Tests run inside `BEGIN … ROLLBACK` so verification data is not persisted. Seed and migration state remain; test inserts are rolled back.

---

## Failure Diagnostics

If tests fail, the script exits non-zero with PostgreSQL error detail. Common causes:

| Issue | Fix |
|-------|-----|
| Docker not running | Start Docker Desktop |
| Port 54329 in use | Change `$PgPort` in `scripts/db-verify.ps1` |
| Migration syntax error | Fix migration SQL; re-run from empty container |
