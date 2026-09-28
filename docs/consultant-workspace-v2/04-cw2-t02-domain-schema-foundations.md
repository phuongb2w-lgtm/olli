# CW2-T02 — Domain / Schema Foundations

**Baseline:** `0e1a4d870d8722414277b638d9f66ffb5d5b05f8`  
**Migrations:** `20260930100000_cw2_t02_declaration_draft_enum.sql`, `20260930101000_cw2_t02_domain_schema_foundations.sql`  
**Tests:** `supabase/tests/cw2_t02_domain_foundation_tests.sql` (16 scenarios)

## Delivered

| Area | Artifact | Source of truth |
|------|----------|-----------------|
| Consultant code | `app_user.consultant_operational_code` | Trusted assign + primary owner `01` backfill |
| Center sequence | `organization_student_sequence.last_allocated_sequence` | Org-wide `NNNN` counter (allocator T03) |
| Portfolio STT | `consultant_portfolio_entry`, `consultant_portfolio_sequence` | Per-consultant stable `workspace_sequence` |
| Declaration extension | Columns on `consultant_revenue_declaration` + enum `draft` | Existing M5 table (not parallel ledger) |
| Sales attribution | `payment_consultant_attribution` | Posted `payment` + snapshot (not declaration totals) |
| Custom fields | `consultant_custom_field_definition` / `_value` | Consultant-owned EAV |
| View prefs | `consultant_workspace_preference`, `consultant_grid_hidden_row` | Non-authoritative UI state |
| Permissions | `consultant_workspace.read/update`, `consultant_custom_field.manage` | Canonical consultant role template |

## Backfill

- All organizations receive `organization_student_sequence`.
- **T02.1:** `last_allocated_sequence` defaults to **`0`** or **`MAX(NNNN)`** from existing **CW2-shaped** `student_code` values only (see [T02.1 bootstrap](./05-cw2-t02-1-student-sequence-bootstrap.md)). Legacy codes (e.g. `HV001`) do **not** advance the counter.
- Primary owner receives code `01` when null (`initialize_organization_cw2_foundation`, including after `set_primary_owner_for_organization`).
- Active canonical **consultant** role members receive next available `02`–`99` by `created_at` (existing codes preserved).
- No historical `student.student_code` values fabricated.

## Deferred to CW2-T03+

- Official `CCYYNNNN` allocation RPC and immutability trigger on `student.student_code`.
- Accounting confirmation composition and `payment_consultant_attribution` inserts.
- Portfolio entry creation RPCs and grid read model.
- `student_code` format validation at DB layer (optional CHECK in T03).

## Semantic debt

- M5 legacy `declare_consultant_revenue()` still creates `pending` rows without student/course context.
- `assign_consultant_operational_code()` does not auto-run on staff provisioning yet (T09 integration).
- Consultant sales KPI RPC not implemented (T05).

## Student sequence semantics (locked T01.1)

- `last_allocated_sequence` = highest **center-wide** `NNNN` already issued.
- T03 will allocate `next = last + 1` under `FOR UPDATE`, fail closed when `next > 9999`.
