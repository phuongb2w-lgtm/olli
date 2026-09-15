# M1-T04 Implementation — Guardian & StudentGuardian Management

**Task:** M1-T04  
**Baseline:** M1-T03 at `d37f4c5`  
**Branch:** `main`

---

## Migration

**File:** `supabase/migrations/20260914140900_m1_t04_guardian_relationship.sql`

### StudentGuardian audit columns

Added nullable `created_by` and `updated_by` with composite FKs to `app_user (organization_id, id)`. Historical rows remain nullable.

### Primary contact partial unique index

```sql
CREATE UNIQUE INDEX idx_student_guardian_primary_unique
  ON student_guardian (organization_id, student_id)
  WHERE status = 'active' AND is_primary_contact = true;
```

**Pre-migration check:** aborts if any student already has multiple active primary contacts. Seed DB: no conflicts.

---

## Guardian Master

| Field | Required | Notes |
|-------|----------|-------|
| `family_name`, `given_name` | Yes | Trimmed; Unicode preserved |
| `phone`, `email` | No | Optional contact fields |
| `status` | Default `active` | `active` / `inactive` |

Create/edit via Server Actions with `guardian.create` / `guardian.update`. Shared master record — edits affect all linked students.

---

## StudentGuardian

| Behavior | Implementation |
|----------|----------------|
| New link | Insert active row with audit actors |
| Active duplicate pair | Rejected (`already_linked`) |
| Ended pair | Reactivate same row with new metadata |
| Unlink | `status = 'ended'`; no hard delete |

Relationship types: `mother`, `father`, `guardian`, `other`.

---

## Primary Contact

- Zero or one active primary per student (DB enforced).
- Switch: clear other active primaries, then set target (multi-step; zero primary valid on partial failure).
- Postgres `23505` → localized `primaryConflict` error.
- UI requires confirmation when replacing existing primary.

---

## Billing Contact

- Independent from primary; no DB uniqueness in M1-T04.
- Multiple active billing contacts allowed.
- Only `status = 'active'` links count as operational.

---

## Permissions

| Action | Permission |
|--------|------------|
| View student guardian page | `student.read` + `guardian.read` |
| Create guardian / link | `guardian.create` |
| Edit guardian / relationship / primary / billing / unlink | `guardian.update` |

Server Actions enforce independently of UI.

---

## Duplicate Warnings

Email (case-insensitive) and phone (digit-normalized) duplicates produce warning-only UX with explicit continue. No DB uniqueness on email/phone. Name-only never blocks.

---

## Routes / UI

| Route | Purpose |
|-------|---------|
| `/students/[id]/guardians` | Relationship management for one student |

Sections: active links (with edit/unlink/primary/billing actions), ended links (minimal), link existing (search), add new guardian.

Student list shows **Guardians** link when `guardian.read`.

---

## Library / Actions

| Module | Role |
|--------|------|
| `src/lib/guardians/*` | Validation, search, duplicates, primary contact, link logic |
| `src/app/actions/guardians.ts` | Server Actions |

---

## Tests

| Suite | File | Count |
|-------|------|-------|
| Guardian smoke | `scripts/guardian-relationships-smoke.mjs` | 44 |
| E2E | `tests/e2e/guardian-relationships.spec.ts` | 4 |

---

## Deviations

None.
