# M1-T03 Implementation — Student Create/Edit & Schema Hardening

**Task:** M1-T03  
**Baseline:** M1-T02 at `74b8648`  
**Branch:** `main`

---

## Migration

**File:** `supabase/migrations/20260914140800_m1_t03_student_code_unique.sql`

Pre-migration guard: raises if any `(organization_id, lower(btrim(student_code)))` group has more than one row.

Index:

```sql
CREATE UNIQUE INDEX idx_student_code_normalized_unique
  ON student (organization_id, lower(btrim(student_code)))
  WHERE student_code IS NOT NULL
    AND btrim(student_code) <> '';
```

**Pre-migration conflict result (seed DB):** none — seed uses distinct codes (`HV001`, `HV002`) and NULL codes without normalized collisions.

---

## Student Code Normalization

**Application write (`normalizeStudentCode`):**

1. Trim leading/trailing whitespace.
2. Empty after trim → store `NULL`.
3. Preserve meaningful display casing in the stored value.

**Uniqueness comparison (`normalizedStudentCodeKey`):**

- `lower(trim(code))` — case-insensitive, whitespace-normalized.
- Scoped per `organization_id` via the partial unique index.
- Multiple `NULL`/blank codes allowed within an organization.

---

## Routes / UI

| Route | Purpose | Permission |
|-------|---------|------------|
| `/students/new` | Create form | `student.create` |
| `/students/[id]/edit` | Edit form (profile + lifecycle) | `student.update` |
| `/students` | List (unchanged read model) + Create button + Edit links | read/create/update as applicable |

- Single-page forms with profile and lifecycle sections separated.
- Success redirect: `/students?success=created|updated` with localized banner.
- Responsive layout; accessible labels; double-submit guarded via pending state.

---

## Permissions

| Action | Permission | UI | Server |
|--------|------------|-----|--------|
| Create | `student.create` | Button hidden without permission | Action + RLS reject |
| Edit / lifecycle | `student.update` | Edit link hidden | Action + RLS reject |
| List | `student.read` | Unchanged from M1-T02 | Unchanged |

Read-only users (`org-a-reader`) retain clean list experience without create/edit controls.

---

## Server Actions

**File:** `src/app/actions/students.ts`

- `createStudent` — validates input, pre-checks student-code conflict, name+DOB warning gate, inserts with trusted org/audit fields.
- `updateStudent` — loads student under RLS, lifecycle confirmation gate when status changes, pre-checks code conflict excluding self, updates with trusted `updated_by`.

**Security:**

- Session Supabase client only (no service role).
- `organization_id`, `created_by`, `updated_by` from `getCurrentAppUser()`.
- Never accepts actor/org IDs from form data.
- Postgres `23505` translated to localized student-code conflict error.

---

## Audit Attribution

| Operation | Fields set |
|-----------|------------|
| Create | `created_by`, `updated_by` = authenticated `app_user.id` |
| Update | `updated_by` = authenticated `app_user.id` |

Existing schema columns reused; no new audit columns added.

---

## Duplicate Handling

### A. Student code — hard conflict

- Application pre-check via `hasStudentCodeConflict`.
- Database partial unique index is final authority.
- Concurrent inserts handled via `23505` → friendly conflict error.
- Update excludes current student ID from pre-check.

### B. Name + DOB — warning only

- Heuristic: trimmed `family_name`, `given_name`, exact `date_of_birth` in org.
- RLS-scoped query — no PII leak for rows user cannot read.
- Requires `confirmDuplicate=true` checkbox to proceed.
- Name-only match never blocks; no DOB → no warning.

---

## Lifecycle Confirmation

- Allowed statuses: `prospect`, `active`, `inactive`, `graduated`, `withdrawn`.
- When submitted status ≠ `originalStatus`, action returns `statusChangeRequired` until `confirmStatusChange=true`.
- Profile edits with unchanged status proceed without lifecycle confirmation.
- Status change does not mutate enrollment, class, attendance, or finance data.

---

## Library Modules

| Module | Role |
|--------|------|
| `constants.ts` | Status enum, defaults, code max length |
| `normalize-student-code.ts` | Write normalization + uniqueness key |
| `validate-student-input.ts` | Server-side field validation |
| `check-student-duplicates.ts` | Code conflict + name/DOB heuristic |

---

## i18n

New keys under `students.*` in `messages/en.json` and `messages/vi.json`:

- Form labels, save/cancel, success messages
- Validation errors, student-code conflict, duplicate warning, lifecycle confirmation
- Permission denied, save error

---

## Tests Added

| Suite | File | Count |
|-------|------|-------|
| Mutation smoke | `scripts/student-mutations-smoke.mjs` | 30 |
| E2E create/edit | `tests/e2e/student-mutations.spec.ts` | 6 |

`npm run test:students` runs M1-T02 list smoke (20) + M1-T03 mutation smoke (30).

---

## Deviations

None.
