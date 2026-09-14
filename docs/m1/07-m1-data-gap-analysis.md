# M1 — Data Gap Analysis & Task Breakdown

**Task:** M1-T01

---

## 1. Data-Gap Matrix

| Requirement | Existing schema supports? | Change needed? | Priority | Reason |
|-------------|---------------------------|----------------|----------|--------|
| Student org isolation | Yes | No | — | organization_id + RLS |
| Guardian org isolation | Yes | No | — | Same |
| Student given/family name | Yes | No | — | Fits VN name model |
| Student optional DOB | Yes | No | — | `date` column exists |
| Student lifecycle statuses | Yes | No | — | 5-value CHECK |
| Guardian phone/email | Yes | No | — | |
| Guardian reuse (siblings) | Yes | No | — | student_guardian M:N |
| Relationship types (4 codes) | Yes | No | — | CHECK constraint |
| Primary contact flag | Yes | No | — | is_primary_contact |
| Billing contact flag | Yes | No | — | is_billing_contact; charge FK |
| student_code optional | Yes | No | — | Nullable text |
| student_code unique per org | **No** | **Yes** | **REQUIRED** | Partial unique index before code reliance |
| student.read/create/update permissions | Yes | No | — | 3 codes exist |
| guardian.read/create/update permissions | Yes | No | — | 3 codes exist |
| student_guardian via guardian perms | Yes | No | — | RLS uses guardian.* |
| No DELETE (soft lifecycle) | Yes | No | — | M0 pattern |
| Audit on student/guardian | Partial | Implement in app | **REQUIRED** (app) | Columns exist; not auto-set |
| Audit on student_guardian | **No** | Optional columns | NICE TO HAVE | created_by missing |
| Student notes | No | Add column | NICE TO HAVE | Staff context |
| Student email/phone | No | Add columns | NICE TO HAVE | Adult student contact |
| Guardian address/notes | No | Add columns | NICE TO HAVE | |
| phone_normalized (guardian) | No | Add column | NICE TO HAVE | Search performance |
| relationship_note for `other` | No | Add column | NICE TO HAVE | Clarify other contacts |
| Primary contact DB invariant | Partial | Partial unique index | NICE TO HAVE | App enforce V1 |
| Search index (name trigram) | No | Add index/extension | NICE TO HAVE | Scale optimization |
| Diacritic-insensitive search | No | unaccent extension | NICE TO HAVE | VN search UX |
| display_name on student | No | Add column | REJECTED V1 | Use formatted names |
| gender on student | No | — | REJECTED V1 | No demonstrated need |
| current_class on student | No | — | REJECTED | Derive from enrollment |
| grandparent/sibling rel codes | No | — | REJECTED V1 | Use `other` |
| Guardian Auth portal link | No | — | REJECTED | Out of scope |
| student.delete permission | No | — | REJECTED V1 | Soft lifecycle only |

---

## 2. Required Schema Changes (Pre-Implementation Review)

### REQUIRED before M1 production use of student codes

```sql
CREATE UNIQUE INDEX idx_student_code_unique
  ON student (organization_id, student_code)
  WHERE student_code IS NOT NULL;
```

Review in dedicated migration after product sign-off. Not created in M1-T01.

### REQUIRED (application — no migration)

- Server Action audit population for student/guardian
- Primary contact invariant validation
- Duplicate warning logic

### NICE TO HAVE (later migrations)

- `student.notes text`
- `student.email`, `student.phone` (adult learners)
- `guardian.notes`, `guardian.address`
- `guardian.phone_normalized text`
- `student_guardian.relationship_note text`
- `student_guardian.created_by`, `updated_by`
- Partial unique index on primary contact
- `pg_trgm` / `unaccent` for search

### REJECTED

- full_name replacing given/family
- middle_name column
- gender
- current_class_id on student
- Hard DELETE endpoints
- New permissions (existing six suffice)
- Guardian ↔ auth.users link

---

## 3. M0 Registry Doc Update (Non-Blocking)

Update student `active` description in [31-status-code-registry.md](../m0/31-status-code-registry.md) from "Currently enrolled participant" to master-record semantics aligned with [01-student-guardian-product-contract.md](./01-student-guardian-product-contract.md). Docs-only; separate from M1 implementation.

---

## 4. Recommended M1 Task Breakdown

### M1-T02 — Student read model + list/search

**Scope:**

- `/students` route (replace M0 proof UI)
- Paginated list per [05-student-list-search-contract.md](./05-student-list-search-contract.md)
- Search by name, code, guardian name/phone
- Status filter
- i18n labels from [01](./01-student-guardian-product-contract.md)
- Permission gate: `student.read`
- Server-side Supabase queries with session client
- Responsive table/cards

**Dependencies:** None beyond M1-T01 sign-off. Optional: student_code unique migration if search-by-code must be strict.

**Out of scope:** Create/edit forms, guardian management UI.

---

### M1-T03 — Student create/edit

**Scope:**

- Create student form + Server Action
- Edit student profile + lifecycle controls
- Validation + error model per [06](./06-student-guardian-workflows.md)
- Audit fields populated
- Duplicate warnings (name+DOB, code)
- Apply student_code unique migration if approved

**Dependencies:** M1-T02 (navigation shell).

**Out of scope:** Guardian linking (may stub optional section for M1-T04).

---

### M1-T04 — Guardian relationships

**Scope:**

- Guardian create/link/unlink on student detail
- Guardian search/reuse
- Relationship type + primary/billing flags
- Edit guardian contact
- Primary contact invariant
- Duplicate phone/email warnings

**Dependencies:** M1-T03 (student detail exists).

---

### M1-T05 — Lifecycle + validation + module integration

**Scope:**

- Lifecycle transition UX polish + confirmations
- Vietnamese diacritic search improvement (if unaccent approved)
- Cross-module smoke: student appears in existing charge/enrollment contexts read-only
- Shared form components + validation/i18n extraction
- Optional NICE TO HAVE columns if approved

**Dependencies:** M1-T03, M1-T04.

---

### M1-T06 — QA / regression / M1 closeout

**Scope:**

- E2E tests for student/guardian flows
- API security smoke extensions
- Permission matrix verification
- M0 regression 80/80 maintained
- M1 closeout doc

**Dependencies:** M1-T02 through M1-T05.

---

## 5. Dependency Graph

```text
M1-T01 (this task)
    ↓
M1-T02 (read/list/search)
    ↓
M1-T03 (student write)
    ↓
M1-T04 (guardian links)
    ↓
M1-T05 (lifecycle + integration)
    ↓
M1-T06 (QA closeout)
```

Parallelization: M1-T02 can start immediately after T01 review. Migration for student_code unique can land between T01 review and T03.

---

## 6. Stop Gate

**Do not proceed to M1-T02** until product/data review approves:

1. Name model (given + family, formatted display)
2. Student code optional V1 + required unique index before T03
3. Student lifecycle semantics (decoupled from enrollment)
4. Primary contact application invariant
5. Data-gap matrix REQUIRED vs NICE TO HAVE vs REJECTED
