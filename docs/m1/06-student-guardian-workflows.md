# M1 — Student & Guardian Workflows

**Task:** M1-T01  
**Implementation targets:** M1-T03 (Student), M1-T04 (Guardian links)

---

## 1. Student Create Workflow

### Required fields (V1)

| Field | Required |
|-------|----------|
| given_name | Yes |
| family_name | Yes |
| student_code | No |
| date_of_birth | No |
| status | Default `active` (staff may set `prospect`) |

### Guardian on create

| Question | Answer |
|----------|--------|
| May student be created without guardian? | **Yes** — adult students |
| Attach guardian in same flow? | **Yes** — optional section |
| Reuse existing guardian? | **Yes** — search/select + create new inline |
| Minimum guardian fields if adding | given_name, family_name; phone recommended |

### Flow (single page, not wizard)

1. Staff opens "Add student"
2. Enters student identity fields
3. Optional: add guardian (new or search existing)
   - If new guardian: duplicate phone/email check → warning
   - If linking: set relationship_type, primary/billing flags
4. Submit → Server Action validates → INSERT student (+ guardian/link if provided)
5. On success: toast + navigate to student detail (or list with highlight)

### Duplicate warnings on create

- Student: name+DOB warning (non-blocking)
- Student code: block if unique constraint violated
- Guardian: phone/email match warning with "Use existing" action

### After success

- Refetch list cache / router refresh
- No success modal

---

## 2. Student Edit Workflow

### Normal profile update

Editable: given_name, family_name, student_code, date_of_birth.

Permission: `student.update`. RLS + server validation.

### Lifecycle change

Separate UI control (dropdown or dedicated action) for `status` transitions per [03-student-field-contract.md](./03-student-field-contract.md).

Confirm destructive-ish transitions (→ withdrawn, → inactive) with brief confirmation dialog.

### Not editable on Student form

- organization_id
- enrollment/class data
- financial balances
- academic metrics

---

## 3. Guardian Workflow Summary

| Action | Effect |
|--------|--------|
| Add new guardian + link | INSERT guardian; INSERT student_guardian |
| Link existing | INSERT student_guardian only |
| Edit guardian details | UPDATE guardian (org-wide effect) |
| Change relationship | UPDATE student_guardian metadata |
| Unlink | UPDATE student_guardian SET status='ended'; clear primary if set |
| Deactivate guardian | UPDATE guardian SET status='inactive' |

Hard deletion: not in M1 V1.

Permission: `guardian.create` / `guardian.update` as appropriate; reading links uses `guardian.read`.

---

## 4. Form Validation Contract

All business validation **server-side**. Client validation mirrors for UX only.

| Category | Rules |
|----------|-------|
| Required name | given_name, family_name non-empty after trim |
| Date | DOB not future; valid calendar date |
| Email | If supplied: shape check |
| Phone | If supplied: digit normalization + min length |
| Status | Must be allowed CHECK value for entity |
| Relationship type | Must be allowed CHECK value |
| Organization | Server-derived; reject mismatch |
| Primary contact | At most one active primary per student |
| student_code | Trim; empty → null; uniqueness if constraint exists |

All validation messages via i18n (`validation.*` namespace).

---

## 5. Server Action Architecture

Pattern (consistent with M0):

```text
Client form → Server Action → createServerClient(session) → Supabase insert/update
                           → validate input (zod or equivalent)
                           → resolve app_user / organization from getIdentityState()
                           → set created_by / updated_by
                           → return { ok, data } | { ok: false, code, messageKey }
```

Rules:

- Authenticated Supabase session only
- Subject to RLS — no service role for normal CRUD
- Never trust browser-supplied `organization_id` as authority (may omit from client payload entirely)
- Controlled error returns — no raw PostgREST messages to users

---

## 6. Error Model

Stable application error categories:

| Code | HTTP-ish | User-facing | Example |
|------|----------|-------------|---------|
| `validation` | 400 | Field-level i18n messages | Missing name |
| `permission_denied` | 403 | Generic permission message | RLS / missing permission |
| `duplicate_warning` | 409 | Warning with continue/cancel | Similar guardian exists |
| `conflict` | 409 | Blocking message | Duplicate student_code |
| `not_found` | 404 | Not found message | Stale ID |
| `unexpected` | 500 | Generic error | Logged server-side |

Map `messageKey` to `messages/{locale}.json`. Do not expose PostgreSQL codes, RLS details, or stack traces.

---

## 7. Audit Behavior

| Entity | created_by / updated_by |
|--------|-------------------------|
| student | Set in Server Action |
| guardian | Set in Server Action |
| student_guardian | **Not in schema** — use created_at + future note field or add columns (NICE TO HAVE) |

Use trusted `app_user.id` from identity resolution. Never from form body.

---

## 8. Accessibility (Implementation Checklist)

- Label every input; errors linked with `aria-describedby`
- Focus first invalid field on validation failure
- Status badges include text, not color alone
- Tables: responsive card fallback preserves reading order
- Action buttons: discernible names ("Save student", not just "Save")

---

## 9. Responsive Breakpoints (Implementation)

Align with [01-student-guardian-product-contract.md](./01-student-guardian-product-contract.md):

- Tailwind defaults: `md` (768px), `lg` (1024px)
- List: table at `lg`, cards below
- Forms: full width mobile; max-width container desktop
