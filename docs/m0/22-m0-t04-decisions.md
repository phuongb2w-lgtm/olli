# M0-T04 — Decision Log

**Date:** 2026-09-14

Identity, permissions, and RLS foundation decisions.

---

## 1. Migration Timestamp Correction

**Issue:** Foundation migration used `20250914140000` (2025) but milestone date is 2026-09-14.  
**Action:** Renamed to `20260914140000_m0_foundation.sql`.  
**Remote check:** No linked Supabase remote migration history at time of change.

---

## 2. Reference Data vs Dev Seed

| Data | Location | Production |
|------|----------|------------|
| 34 Permission codes | `20260914140100_reference_data.sql` | Safe after `db push` |
| 3 ObservationIndicator codes | same migration | Safe |
| Org A/B, auth users, roles, sample domain | `supabase/seed.sql` | **Never deploy** |

Auto-seed disabled in `supabase/config.toml`; dev seed applied manually after stack is up.

---

## 3. Local Supabase vs Raw PostgreSQL

| Layer | Script | Proves |
|-------|--------|--------|
| Generic PostgreSQL | `scripts/db-verify.ps1` | Schema/constraints (foundation + reference migrations) |
| Local Supabase | `scripts/supabase-verify.ps1` | Auth, JWT context, RLS, full migration chain |

Olli uses custom ports **54421–54424** to avoid conflict with other local Supabase projects.

---

## 4. Auth Mapping: ON DELETE SET NULL

Deleting `auth.users` nulls `app_user.auth_user_id` but preserves `app_user` and all historical FKs. Access ends; audit/finance/academic history remains.

---

## 5. No Role-Name Security

RLS uses `has_permission(code)` exclusively. Fixture role codes (`admin`, `staff`) are dev labels only.

---

## 6. No DELETE Policies in M0

Authenticated clients receive SELECT/INSERT/UPDATE grants; DELETE is not granted. Historical truth relies on status fields and constraints.

---

## 7. Permission Catalog Mutability

Only SELECT policy on `permission`. No client INSERT/UPDATE/DELETE — canonical codes change via migrations only.

---

## 8. Charge Amount Immutability Under RLS

Added `20260914140500_charge_amount_immutability.sql` trigger because admin users with `charge.create` could otherwise UPDATE `amount` through RLS-permitted UPDATE policy.

---

## 9. Generated Types

Path: `types/database.generated.ts`  
Regenerate: `npm run db:types` (requires local Supabase running).  
File is CLI-generated — do not hand-edit.

---

## 10. Explicitly Deferred (M0-T05+)

- Frontend framework / application UI
- Student or guardian Auth portals
- SaaS organization self-signup
- Teacher-scoped “own classes only” rules (unless product spec locks this)
- Production Supabase project linking
- `report.read` application endpoints

---

## Rebaseline Note

M0-T02/M0-T03 incorporated finance and learning-evidence foundation. **M0-T04** is the Identity / Permission / RLS security layer on top of that schema — not a duplicate of T03 work.
