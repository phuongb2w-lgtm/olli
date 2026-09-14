# M1 — Guardian & Relationship Contract

**Task:** M1-T01

---

## 1. Guardian Field Classification

| Field | Classification | V1 required on create? | Editable? | Notes |
|-------|----------------|------------------------|-----------|-------|
| `id` | System | Auto | No | |
| `organization_id` | System | Server-derived | No | |
| `given_name` | Required identity | **Yes** | Yes | Same name model as Student |
| `family_name` | Required identity | **Yes** | Yes | |
| `phone` | Optional contact | No | Yes | See §5 |
| `email` | Optional contact | No | Yes | Not Auth identity — §6 |
| `status` | Lifecycle | Default `active` | Lifecycle action | `active` / `inactive` |
| `created_at`, `updated_at` | Audit | Auto | No | |
| `created_by`, `updated_by` | Audit | Server-set | No | |

### Absent — V1 decisions

| Field | Decision |
|-------|----------|
| `address` | **NICE TO HAVE** |
| `notes` | **NICE TO HAVE** |
| `phone_normalized` | **NICE TO HAVE** (see phone policy) |

Smallest useful V1 dataset: **name + optional phone + optional email + status**.

---

## 2. Guardian Lifecycle

| Status | Meaning |
|--------|---------|
| `active` | Valid contact for linking and new charges |
| `inactive` | Retired contact; historical charges/payments retain FK |

Guardian inactive does **not** auto-end `student_guardian` links — staff should end links explicitly or UI warns on inactive guardian still linked.

No `archived` status; no hard delete in M1 V1.

---

## 3. StudentGuardian Relationship

### Supported scenarios

| Scenario | Supported? |
|----------|------------|
| Student A → mother | Yes (`relationship_type = 'mother'`) |
| Student A → father | Yes |
| Student B → same mother | Yes (reuse guardian_id) |
| Additional contact | Yes (`guardian` or `other`) |
| Sibling as contact | Use `other` — no `sibling` code V1 |

### Link metadata

| Field | Purpose | V1 |
|-------|---------|-----|
| `relationship_type` | Machine-coded relationship | Required (default `guardian`) |
| `is_primary_contact` | Main operational contact | See §4 |
| `is_billing_contact` | Finance-facing contact | Keep — `charge.guardian_id` already exists |
| `status` | Link lifecycle | `active` / `ended` |

Unlinking sets `status = 'ended'`. Does **not** delete `guardian` row. Guardian shared by siblings remains.

No legal custody modeling. No family-law semantics.

---

## 4. Relationship Type Strategy

### Existing schema (retain for V1)

CHECK constraint allows: `mother`, `father`, `guardian`, `other`.

| Code | Reporting | Bilingual UI |
|------|-----------|--------------|
| `mother` | Canonical | Mẹ / Mother |
| `father` | Canonical | Bố / Father |
| `guardian` | Canonical | Người giám hộ / Guardian |
| `other` | Canonical | Khác / Other |

### Not added in V1

`grandparent`, `sibling` — use `other` with optional free-text note (**NICE TO HAVE** column `relationship_note` on link, or guardian notes).

Requirements met:

- Machine code independent of locale ✓
- Bilingual presentation via i18n ✓
- Simple V1 ✓
- No free-text as canonical reporting value ✓

---

## 5. Primary Contact Invariant

### Need

**Yes** — staff must know whom to call first. Column `is_primary_contact` already exists.

### Rule

- A Student may have **at most one** active (`student_guardian.status = 'active'`) link with `is_primary_contact = true`.
- A Student **may have zero** guardians (adult learners).
- Multiple guardians allowed; only one primary among active links.

### Enforcement

| Layer | V1 |
|-------|-----|
| Application (Server Action) | **Required** — validate before insert/update link |
| Database partial unique index | **NICE TO HAVE** — `UNIQUE (organization_id, student_id) WHERE is_primary_contact AND status = 'active'` |

Setting a new primary must clear previous primary on same student in same transaction.

`is_billing_contact` independent — may coincide with primary but not required.

---

## 6. Duplicate-Person Prevention

### Principles

- Never UNIQUE on name alone
- Organization-scoped checks only
- Distinguish hard constraint vs staff warning

### Hard uniqueness (safe DB constraints)

| Target | Constraint | Priority |
|--------|------------|----------|
| student_code per org | `UNIQUE (organization_id, student_code) WHERE student_code IS NOT NULL` | REQUIRED before code reliance |
| student_guardian pair | Already `UNIQUE (organization_id, student_id, guardian_id)` | Exists |

### Duplicate warnings (application — human judgment)

| Signal | Match rule | Action |
|--------|------------|--------|
| Guardian phone | Normalized digits match within org | Warn "Similar guardian exists" + link option |
| Guardian email | Case-insensitive exact match within org | Warn + link option |
| Student code | Exact match within org | Block if unique index exists; else warn |
| Student name + DOB | Same family+given (case/diacritic fold) + same DOB | Warn only |
| Guardian name + phone | Name similarity + phone match | Strong warn |

Staff may proceed after acknowledging warning. Log decision in audit (future enhancement).

---

## 7. Phone Number Policy (V1)

Vietnam-first; international numbers not blocked.

| Aspect | V1 approach |
|--------|-------------|
| Storage | Single `phone text` column (display/original input preserved) |
| Normalization | **Application-layer** for search/compare: strip non-digits; if starts with `0`, allow; if `+84`, convert to `84` prefix form for comparison |
| Display | Show stored value; optional future formatting |
| Uniqueness | **Not** globally unique; not unique per org — duplicate warn only |
| Validation | Min length after digit strip (e.g. ≥ 9 digits); reject obvious garbage |

**NICE TO HAVE:** `phone_normalized text` column + index for search performance.

---

## 8. Email Policy

| Rule | Detail |
|------|--------|
| Purpose | Business contact only |
| Auth | **Not** linked to Supabase Auth in M1 |
| Validation | RFC5322-lite: contains `@`, reasonable length |
| Uniqueness | Warn on duplicate within org; no hard UNIQUE |
| Case | Store as entered; compare case-insensitive |

Student records lack email column V1; guardian email is the primary billing/contact email path for charges.

---

## 9. Guardian V1 Operations

| Operation | Behavior |
|-----------|----------|
| Add new Guardian | Insert `guardian` + optional `student_guardian` link |
| Link existing Guardian | Search by name/phone; insert link only |
| Edit Guardian contact | Update `guardian` row; affects all linked students |
| Change relationship metadata | Update `student_guardian` row |
| Unlink | `student_guardian.status → 'ended'`; clear primary/billing flags |
| Hard delete Guardian | **Not in M1 V1** |

If guardian has open charges and is inactivated, finance flows continue against historical FK.
