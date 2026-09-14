# M1 — Student List & Search Contract

**Task:** M1-T01  
**Implementation target:** M1-T02

---

## 1. Student List — V1 Columns

Minimum useful columns for administrative staff:

| Column | Source | V1 show? | Notes |
|--------|--------|----------|-------|
| Student name | `student.given_name`, `student.family_name` | **Yes** | Primary column; formatted display |
| Student code | `student.student_code` | **Yes** | Show em dash when null |
| Primary guardian / contact | Join `student_guardian` → `guardian` where `is_primary_contact AND status='active'`; fallback first active link | **Yes** | Name + phone if available |
| Status | `student.status` | **Yes** | Badge with i18n label |
| Current class | Derived from active `enrollment` | **No** | Omit until Enrollment integration intentionally added |
| Date of birth | `student.date_of_birth` | **No** | Detail view only V1 |
| Created date | `student.created_at` | **No** | Optional secondary sort only |

Mobile/card layout: name, status, code (if any), primary contact phone.

---

## 2. Search — V1 Behavior

### Searchable fields

| Field | Match type | Priority |
|-------|------------|----------|
| Student name (given + family) | Partial, case-insensitive | High |
| Student code | Partial prefix or exact | High |
| Guardian name | Partial via join | Medium |
| Guardian phone | Digit-normalized contains | Medium |

### Query rules

| Rule | V1 decision |
|------|-------------|
| Organization isolation | **Mandatory** — `organization_id = current_organization_id()`; RLS enforces |
| Case handling | `ILIKE` or lower() comparison |
| Vietnamese diacritics | **Best-effort V1:** search both raw input and unaccented fold in application if `unaccent` extension not added; document limitation in UI help text |
| Partial matching | Yes — `%term%` for names; prefix preferred for codes |
| Minimum term length | 2 characters (avoid full table scan on single char) |
| Empty search | Return paginated default list |

### Index implications V1

Existing indexes sufficient for org-scoped paginated listing. Search across name may seq-scan at small center scale.

**NICE TO HAVE later:**

- `pg_trgm` GIN index on `(family_name || ' ' || given_name)`
- Partial index on `(organization_id, student_code)` where not null
- `unaccent` extension for diacritic-insensitive search

No full-text search infrastructure until justified by scale.

### Guardian search (reuse flow)

Same rules when linking existing guardian in create/edit flow; scoped to org, searchable by name/phone/email.

---

## 3. Filtering — V1

| Filter | V1? | Values |
|--------|-----|--------|
| Lifecycle status | **Yes** | All + prospect, active, inactive, graduated, withdrawn |
| Search term | **Yes** | Combined with status filter (AND) |
| Class | **No** | Enrollment domain |
| Has guardian | **No** | Defer |
| Date range | **No** | Defer |

Default filter: status = `active` **or** show all with active sorted first — product choice at M1-T02; recommend **All statuses** default with status badge visible to avoid hiding prospects/inactive.

---

## 4. Sorting — V1

### Default primary sort

**Family name ascending, given name ascending** — matches Vietnamese directory practice and stable UX.

### Secondary stable sort

**`student.id` ascending** — tie-breaker for pagination consistency.

### User-selectable sorts (optional M1-T02)

| Option | Order |
|--------|-------|
| Name (default) | family_name ASC, given_name ASC, id ASC |
| Newest created | created_at DESC, id ASC |
| Student code | student_code ASC NULLS LAST, family_name ASC, id ASC |

Avoid sorting by derived enrollment data in M1-T02.

---

## 5. Pagination — V1

| Aspect | Decision |
|--------|----------|
| Approach | Offset/limit server-side |
| Default page size | **25** |
| Allowed page sizes | 25, 50, 100 |
| UI | Previous/Next + page indicator; show total count if cheap (`count: exact` head request) |
| Infinite scroll | **No** V1 |
| Max unbounded fetch | **Never** — all list queries must paginate |

Server query strategy: Supabase client from Server Component or Server Action with `.range(from, to)` and explicit `.order()`.

---

## 6. Empty & Error States

| State | UI |
|-------|-----|
| No students in org | Empty state with "Add student" CTA (when permitted) |
| No search results | `common.noResults` |
| Permission denied | Do not leak existence; show permission message |
| Server error | Generic localized error; log detail server-side |
