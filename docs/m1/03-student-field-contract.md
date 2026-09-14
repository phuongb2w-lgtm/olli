# M1 — Student Field Contract

**Task:** M1-T01  
**Schema reference:** [02-existing-schema-audit.md](./02-existing-schema-audit.md)

---

## 1. Field Classification

| Field | Classification | V1 required on create? | Editable (normal)? | Notes |
|-------|----------------|------------------------|--------------------|-------|
| `id` | System identity | Auto | No | UUID PK |
| `organization_id` | System / tenant | Server-derived | No | Never from client |
| `given_name` | Required canonical identity | **Yes** | Yes | See name model §2 |
| `family_name` | Required canonical identity | **Yes** | Yes | See name model §2 |
| `student_code` | Optional operational data | No | Yes | Human-readable; see §3 |
| `date_of_birth` | Optional operational data | No | Yes | `date` type; see §6 |
| `status` | Lifecycle state | Default `active` | Lifecycle action only | See §4 |
| `created_at` | Audit | Auto | No | |
| `updated_at` | Audit | Auto | No | Trigger-maintained |
| `created_by` | Audit | Server-set | No | See §7 |
| `updated_by` | Audit | Server-set | No | See §7 |

### Absent fields — classification

| Proposed field | Classification | V1 decision |
|----------------|----------------|-------------|
| `display_name` / preferred name | Optional operational | **NICE TO HAVE** — use formatted given+family until needed |
| `email` | Optional contact | **NICE TO HAVE** — adult students; guardian carries contact V1 |
| `phone` | Optional contact | **NICE TO HAVE** — same |
| `address` | Optional operational | **NICE TO HAVE** — not required for language-center V1 |
| `gender` | Optional operational | **REJECTED V1** — no demonstrated operational need |
| `notes` | Optional operational | **NICE TO HAVE** — staff context useful but not blocking |
| `current_class_id` | Derived / inappropriate | **REJECTED** — derive from enrollment |
| Attendance %, balance, scores | Derived | **REJECTED** — wrong domain |

---

## 2. Name Model Decision

### Context

Physical schema stores **`given_name`** + **`family_name`** (both NOT NULL). M0 chose this over a single `full_name` column.

### Vietnam-first evaluation

Vietnamese personal names map naturally to this structure:

- **`family_name`** → họ (e.g. Nguyễn, Trần)
- **`given_name`** → tên đệm + tên (e.g. Văn An, Thu Hà)

Staff typically collect and speak full names; Western first/last ordering does not apply. English UI displays the same data with locale-appropriate formatting.

### Decision (locked for M1)

| Choice | Decision |
|--------|----------|
| Replace with single `full_name` column | **No** — unnecessary migration; current columns fit Vietnamese practice |
| Add middle_name column | **No** — fold into `given_name` |
| Add optional display/preferred name | **Defer** — NICE TO HAVE |
| UI presentation | Single **display name** derived in application: `formatPersonName(given_name, family_name, locale)` |
| Form labels (vi) | "Họ" → family_name; "Tên" → given_name |
| Form labels (en) | "Family name" / "Given name" OR grouped as "Full name" with two inputs |

Do not force Western name order in storage or sort. Default sort uses family_name, then given_name (Vietnamese directory convention).

---

## 3. Student Code

### Current mechanism

- Column: `student_code text` (nullable)
- **No** UNIQUE constraint in migration
- Not used in FK relationships

### Requirements (if retained)

| Requirement | Current support |
|-------------|-----------------|
| Human-readable | Yes (free text) |
| Not PK | Yes |
| Organization-scoped | Yes (row scoped by org) |
| Unique where non-null | **No — gap** |
| Not used for relationships | Yes |
| Survives class changes | Yes (independent of enrollment) |

### V1 behavior recommendation

**Option C: Optional initially** — safest for M1 launch.

| Aspect | Rule |
|--------|------|
| Create | student_code optional |
| Format | **Do not invent** a numbering format in M1-T01; centers may use existing paper codes |
| Uniqueness | Before production-heavy use, add partial unique index (see gap analysis) |
| Duplicate check | If provided on create/edit, warn on org-scoped duplicate; block if unique index exists |
| Search | Exact and prefix match when code provided |

Manual assignment (A) vs auto-generation (B) deferred to center onboarding policy; optional field supports both without committing to format.

---

## 4. Student Lifecycle

### Semantics (master record — not enrollment)

| Status | Meaning | Typical triggers |
|--------|---------|------------------|
| `prospect` | Known interest; minimal master record | Inquiry, trial registration |
| `active` | Center actively maintains this person as a student | Default on create; reactivation |
| `inactive` | Temporarily not attending; history preserved | Long pause, seasonal break |
| `graduated` | Completed program pathway at center | Program completion |
| `withdrawn` | Left center before graduation | Explicit departure |

**Not represented here:** per-class enrollment state (`enrollment.status`), session attendance, payment standing.

### Allowed transitions

```text
prospect → active | withdrawn
active → inactive | graduated | withdrawn
inactive → active | withdrawn
graduated → (terminal; reactivation requires admin override → active with audit note)
withdrawn → active (re-enrollment case; rare; auditable)
```

No transition deletes or orphans: enrollment, attendance, assessment_result, teacher_observation, charge, payment_allocation history.

### UI vs enrollment

| Event | Student status change? |
|-------|------------------------|
| Student leaves one class | **No** automatic change |
| Last active enrollment ends, student may return | Prefer `inactive` only if staff confirms |
| New enrollment created | Does **not** auto-set student to `active` if currently `inactive` — staff decides |

### Archive terminology

Use lifecycle statuses above. No `archived` machine code on student. UI "Deactivate" maps to `inactive` unless staff selects withdrawn/graduated.

---

## 5. Edit Categories

| Category | Fields | Permission |
|----------|--------|------------|
| Normal profile update | given_name, family_name, date_of_birth, student_code | `student.update` |
| Lifecycle change | status | `student.update` + confirmation UI |
| Historical correction | DOB, name typo on old records | `student.update` + audit trail via updated_by |

Profile editing must **not** mutate enrollment, charges, or derived academic/financial data. No current-class editor on Student profile.

---

## 6. Date of Birth

| Rule | Value |
|------|-------|
| Storage | PostgreSQL `date` (already in schema) |
| Timezone | None — calendar date only |
| Required? | Optional V1 |
| Validation | Must not be in the future |
| Min/max age | No arbitrary limits — adult students allowed |
| Display | `formatDate(dob, locale)` — existing helper pattern |

---

## 7. Audit Behavior

Schema provides `created_by`, `updated_by` on `student`. **No trigger auto-populates** — Server Actions must set:

- `created_by` = current `app_user.id` on INSERT
- `updated_by` = current `app_user.id` on UPDATE

Never accept audit user IDs from the browser. Derive from authenticated session + `get-identity-state` pattern (M0).

If audit columns left null, document as incomplete audit — implementation requirement for M1-T03+.
