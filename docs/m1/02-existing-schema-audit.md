# M1 — Existing Schema Audit

**Task:** M1-T01  
**Sources inspected:**

- `supabase/migrations/20260914140000_m0_foundation.sql`
- `supabase/migrations/20260914140100_reference_data.sql`
- `supabase/migrations/20260914140400_rls_policies.sql`
- `types/database.generated.ts`
- M0 docs: [07](../m0/07-canonical-domain-model.md), [13](../m0/13-physical-data-model.md), [15](../m0/15-database-indexes.md), [31](../m0/31-status-code-registry.md)

---

## 1. `student` — Physical Definition

```sql
CREATE TABLE student (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organization (id) ON DELETE RESTRICT,
  student_code    text,
  given_name      text NOT NULL,
  family_name     text NOT NULL,
  date_of_birth   date,
  status          text NOT NULL DEFAULT 'active',
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  created_by      uuid,
  updated_by      uuid,
  UNIQUE (organization_id, id),
  CONSTRAINT student_status_check CHECK (status IN ('prospect', 'active', 'inactive', 'graduated', 'withdrawn'))
);
```

| Aspect | Detail |
|--------|--------|
| PK | `id` (uuid) |
| Tenant key | `organization_id` |
| Composite FK target | `UNIQUE (organization_id, id)` — used by enrollment, charge, etc. |
| Indexes | `idx_student_organization`, `idx_student_active` (partial: `status = 'active'`) |
| Audit | `created_at`, `updated_at` (trigger), `created_by`, `updated_by` (FK → app_user) |
| DELETE | No RLS DELETE policy; hard delete not exposed |
| Absent columns | email, phone, address, notes, gender, display_name |

---

## 2. `guardian` — Physical Definition

```sql
CREATE TABLE guardian (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organization (id) ON DELETE RESTRICT,
  given_name      text NOT NULL,
  family_name     text NOT NULL,
  email           text,
  phone           text,
  status          text NOT NULL DEFAULT 'active',
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  created_by      uuid,
  updated_by      uuid,
  UNIQUE (organization_id, id),
  CONSTRAINT guardian_status_check CHECK (status IN ('active', 'inactive'))
);
```

| Aspect | Detail |
|--------|--------|
| Indexes | `idx_guardian_organization`, `idx_guardian_active` (partial: `status = 'active'`) |
| Audit | Same pattern as student |
| Absent columns | address, notes, phone_normalized |

---

## 3. `student_guardian` — Physical Definition

```sql
CREATE TABLE student_guardian (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id    uuid NOT NULL,
  student_id         uuid NOT NULL,
  guardian_id        uuid NOT NULL,
  relationship_type  text NOT NULL DEFAULT 'guardian',
  is_primary_contact boolean NOT NULL DEFAULT false,
  is_billing_contact boolean NOT NULL DEFAULT false,
  status             text NOT NULL DEFAULT 'active',
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, id),
  UNIQUE (organization_id, student_id, guardian_id),
  CONSTRAINT student_guardian_status_check CHECK (status IN ('active', 'ended')),
  CONSTRAINT student_guardian_relationship_check CHECK (
    relationship_type IN ('mother', 'father', 'guardian', 'other')
  ),
  FOREIGN KEY (organization_id, student_id) REFERENCES student (organization_id, id),
  FOREIGN KEY (organization_id, guardian_id) REFERENCES guardian (organization_id, id)
);
```

| Aspect | Detail |
|--------|--------|
| Indexes | By student; by guardian |
| Audit | **No** `created_by` / `updated_by` |
| Uniqueness | One link row per student+guardian pair per org |
| No DB constraint | At most one `is_primary_contact = true` per student |

---

## 4. Related Tables (Context Only)

| Table | Relevance to M1 |
|-------|-----------------|
| `organization` | Tenant root; `default_locale`, `timezone` |
| `app_user` | Audit actor; permission resolution |
| `enrollment` | Class membership — **not** Student lifecycle |
| `charge` | Requires `guardian_id`; billing contact relevance |

Seed fixtures (`supabase/seed.sql`): minimal student/guardian rows without `student_guardian` links; charges join guardian by org only.

---

## 5. CHECK Constraints Summary

| Table | Constrained column | Allowed values |
|-------|-------------------|----------------|
| student | status | `prospect`, `active`, `inactive`, `graduated`, `withdrawn` |
| guardian | status | `active`, `inactive` |
| student_guardian | status | `active`, `ended` |
| student_guardian | relationship_type | `mother`, `father`, `guardian`, `other` |

---

## 6. RLS Policies

All three tables: **ENABLE + FORCE** RLS. No DELETE policies.

| Table | SELECT | INSERT | UPDATE |
|-------|--------|--------|--------|
| student | `student.read` + org | `student.create` + org | `student.update` + org |
| guardian | `guardian.read` + org | `guardian.create` + org | `guardian.update` + org |
| student_guardian | `guardian.read` + org | `guardian.create` + org | `guardian.update` + org |

Update policies use `WITH CHECK (organization_id = current_organization_id())` — org cannot be moved on update.

Reference: [M0 RLS policy matrix](../m0/20-rls-policy-matrix.md).

---

## 7. Permissions (Relevant Subset)

From `20260914140100_reference_data.sql`:

- `student.create`, `student.read`, `student.update`
- `guardian.create`, `guardian.read`, `guardian.update`

No `student.delete`, `guardian.delete`, or granular link permissions.

---

## 8. Generated TypeScript Types

File: `types/database.generated.ts`

| Table | Matches migration? |
|-------|-------------------|
| student | Yes — all columns present; status typed as `string` (not enum union) |
| guardian | Yes |
| student_guardian | Yes |

Application layer should define narrow status/relationship unions in `src/types/` when implementing M1 (pattern from existing M0 code).

---

## 9. Drift Analysis

### 9.1 Logical M0 vs Physical Migration

| Topic | M0 logical | Physical | Drift? |
|-------|------------|----------|--------|
| Student key attributes | given_name, family_name, DOB, student_code | Matches | None |
| No current_class on Student | Documented | No column | None |
| Guardian key attributes | given_name, family_name, phone, email | Matches | None |
| StudentGuardian flags | is_primary_contact, is_billing_contact | Matches | None |
| Relationship types | mother, father, guardian, other | Matches CHECK | None |
| Archive strategy | Soft status | status CHECK, no DELETE | None |

### 9.2 Physical vs M1 Product Requirements

| Requirement | Physical state | Gap |
|-------------|----------------|-----|
| student_code unique where non-null | **No unique index** | **Gap — REQUIRED fix before relying on codes** |
| student_code org-scoped | Implicit via org_id | OK |
| Primary contact at most one | No partial unique index | App-enforced V1; optional DB later |
| Guardian reuse across students | Supported via student_guardian | OK |
| Student search by name/code/guardian | No search indexes beyond org listing | App query pattern sufficient V1 |
| student_guardian audit columns | Missing created_by/updated_by | Implementation gap for audit |
| Relationship note for `other` | No column | Optional note via guardian or future field |

### 9.3 M0 Status Registry vs M1 Semantics

| Item | M0 registry wording | M1 correction |
|------|---------------------|---------------|
| student `active` | "Currently enrolled participant" | **Product drift** — registry conflates enrollment. M1 defines `active` as operational master lifecycle (see [01](./01-student-guardian-product-contract.md)). DB codes unchanged. |

Recommend updating M0 registry description in a future docs-only pass; not blocking M1.

### 9.4 Generated Types vs Migration

No column-level drift detected at `d356e1d`.

---

## 10. Machine Status Inventory (M1-Relevant)

| Entity | Codes | Mutable via UPDATE? |
|--------|-------|---------------------|
| student | prospect, active, inactive, graduated, withdrawn | Yes |
| guardian | active, inactive | Yes |
| student_guardian | active, ended | Yes |
| student_guardian.relationship_type | mother, father, guardian, other | Yes (on link row) |

No `archived` status on student or guardian (unlike `course` which has `archived`). Student terminal states: `graduated`, `withdrawn`, or long-term `inactive`.
