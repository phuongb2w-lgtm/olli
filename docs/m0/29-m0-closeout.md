# M0 — Foundation Closeout

## Status

**M0 — CLOSED / ACCEPTED**

All foundation gates passed at M0-T06 closeout.

---

## Final Commit Chain

| Milestone | Commit | Message |
|-----------|--------|---------|
| M0-T01 | `294e6d3` | docs(m0): establish product foundation |
| M0-T02 | `b1ff5c4` | docs(m0): canonical domain model and relational foundation |
| M0-T03 | `ca1e1c6` | feat(m0): establish PostgreSQL data foundation |
| M0-T04 | `83168e6` | feat(m0): establish auth and RLS foundation |
| M0-T05 | `8e09750` | feat(m0): bootstrap secure bilingual web application |
| M0-T06 | _(this commit)_ | chore(m0): close product and data foundation |

**Branch:** `main`

---

## Final Architecture

See [30-architecture-baseline.md](./30-architecture-baseline.md).

Summary: Next.js 16 + TypeScript + Supabase PostgreSQL. Permission-code RLS authorization. Bilingual vi/en. Charge-based finance. Management evidence only (not LMS).

---

## Schema Object Count

| Object type | Count |
|-------------|------:|
| Tables | 31 |
| Views | 1 (`charge_balance`) |
| Custom application functions | 16 |

See [32-security-surface-inventory.md](./32-security-surface-inventory.md).

---

## Verification Results

| Suite | Result |
|-------|--------|
| M0-T03 domain integrity | **25/25 PASS** |
| M0-T04 RLS security | **30/30 PASS** |
| charge_balance | **5/5 PASS** |
| M0-T05 Data API security | **6/6 PASS** |
| M0-T05 application smoke | **8/8 PASS** |
| M0-T06 locale persistence | **6/6 PASS** |
| **Total scenarios** | **80/80 PASS** |

### Build Quality

| Gate | Result |
|------|--------|
| db lint | PASS |
| lint | PASS |
| typecheck | PASS |
| production build | PASS |
| fresh Supabase reset | PASS |
| i18n key parity | PASS (35 keys) |
| env/secrets audit | PASS |
| generated types freshness | PASS |

**Unified command:** `npm run verify`

---

## M0-T06 Additions

### Locale persistence

- RPC: `set_own_preferred_locale(p_locale text)` — SECURITY DEFINER, fixed `search_path`, no arbitrary user ID
- Server Action: `setLocale()` — cookie + RPC when authenticated
- Resolution: `app_user.preferred_locale → organization.default_locale → cookie → vi`

### Documentation

- Architecture ADR, status registry, security inventory, open decisions
- Permission registry finalized in [19-permission-model.md](./19-permission-model.md)
- Delete policy: no hard DELETE for normal users; status/archive/reversal patterns

### Automation

- `npm run verify` — unified foundation gate
- `npm run test:i18n` — structural key parity
- `npm run test:env` — secrets audit
- `npm run test:types:stale` — generated types check
- `npm run db:inventory` — security surface regeneration

---

## Known Deferred Decisions

See [33-open-decisions.md](./33-open-decisions.md).

- Cost B business group names/codes — OPEN BUSINESS DECISION
- TuitionPlan exclusivity/scope — OPEN BUSINESS RULE
- FinancialPeriod — DEFERRED
- OrganizationSettings expansion — DEFERRED
- Student/Guardian portal — OUT OF M0
- Teacher-specific visibility — NOT YET LOCKED

---

## M0 / M1 Boundary

**M0 includes:** product contract, domain model, schema, auth/RLS, web bootstrap, i18n foundation, CI, verification baseline.

**M1 begins with:** Student & Guardian Operations (list, create/edit, lifecycle, guardian relationships, search, permissions, bilingual UX). No M1 features were implemented during M0-T06.

---

## Fresh Clone Workflow

```powershell
git clone <repository-url> olli
cd olli
npm ci
npx supabase start
copy .env.example .env.local
# Set NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY from: npx supabase status
npm run verify
npm run dev
```

Local test fixtures (`org-a-admin@olli.local` / `testpass123`) are **development only** — never production credentials.
