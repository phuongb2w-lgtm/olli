# M1-T02 — Implementation Notes

**Task:** Student read model + list/search  
**Route:** `/students`

---

## Read Model

Module: `src/lib/students/`

| File | Role |
|------|------|
| `query-student-list.ts` | Server-side list query |
| `parse-list-params.ts` | URL param validation |
| `format-person-name.ts` | `family_name + " " + given_name` |
| `build-list-url.ts` | Pagination/filter link builder |
| `types.ts` | `StudentListItem` and param types |

### Vietnamese / diacritic search (V1)

PostgREST `ilike` filters do not reliably match Unicode characters in filter values. V1 uses:

- Full-term patterns for ASCII-only queries (names, codes)
- Leading ASCII-prefix patterns per token (e.g. `Ph` matches `Phương`, `Phạm`)
- Digit-normalized phone search on guardians

Full diacritic-insensitive search remains NICE TO HAVE (`unaccent` extension).

### Query architecture

1. Parse and validate URL params (`q`, `status`, `page`, `pageSize`).
2. If `q` length ≥ 2, resolve matching student IDs **before pagination**:
   - Student `given_name`, `family_name`, `student_code` via `ILIKE`
   - If `guardian.read`: union student IDs from active `student_guardian` links whose guardian matches name/phone
3. Count filtered students (`head: true`).
4. Fetch one page with stable sort: `family_name`, `given_name`, `id` ASC.
5. If `guardian.read`, batch-fetch primary contacts in a second query (no row duplication on student).

### One student = one row

Student list queries the `student` table only. Guardian matching uses ID union, not a join that would duplicate rows.

### Primary contact resolution

Active link: `student_guardian.status = 'active'` AND `is_primary_contact = true`.

If multiple primaries exist (legacy data), display the link with earliest `created_at` (deterministic). No mutation in M1-T02.

Without `guardian.read`: primary contact query is skipped; UI omits the column and never serializes guardian fields.

---

## Guardian Permission Boundary

| Permission | Primary contact column | Guardian search |
|------------|------------------------|-----------------|
| `student.read` only | Hidden | Disabled |
| `student.read` + `guardian.read` | Shown | Enabled |

Enforced in `queryStudentList({ hasGuardianRead })` and UI `showPrimaryContact={hasGuardianRead}`.

---

## URL Parameters

| Param | Values | Default |
|-------|--------|---------|
| `q` | string | empty (ignored if &lt; 2 chars) |
| `status` | `all`, `prospect`, `active`, `inactive`, `graduated`, `withdrawn` | `all` |
| `page` | positive integer | `1` (clamped to valid range) |
| `pageSize` | `25`, `50`, `100` | `25` |

Invalid `status` → `all`. Invalid `pageSize` → `25`.

---

## Tests Added

| Suite | File | Count |
|-------|------|-------|
| Student list smoke | `scripts/student-list-smoke.mjs` | 20 |
| Playwright UI | `tests/e2e/student-list.spec.ts` | 10 |

Run: `npm run test:students`, `npm run test:app`

---

## Seed Fixtures (Org A)

- `Trần Văn Phương` (`HV001`) with two guardian links (primary: Phạm Lan)
- `Nguyễn Minh Anh` (`HV002`, prospect)
- `org-a-reader@olli.local` — `student.read` without `guardian.read`
- `org-a-no-student@olli.local` — no `student.read`
