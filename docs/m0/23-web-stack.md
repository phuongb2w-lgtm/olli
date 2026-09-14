# M0-T05 — Web Stack

**Date:** 2026-09-14

## Decision

Single-application repository (no monorepo). One Next.js app shares the existing `supabase/` foundation.

| Layer | Choice |
|-------|--------|
| Framework | Next.js **16.3.4** (Active LTS, patched) |
| React | **19.x** (peer required by Next 16.3) |
| Language | TypeScript **5.9** strict |
| Styling | Tailwind CSS **4.x** |
| Package manager | npm |
| Node (dev/CI) | **22 LTS** (`engines >= 20.9`) |
| Auth client | `@supabase/supabase-js` + `@supabase/ssr` |
| i18n | `next-intl` **4.x** |

## Why no monorepo

Olli has one management application and one PostgreSQL foundation. Turborepo/Nx would add coordination cost without a second deployable unit.

## Scripts

| Script | Purpose |
|--------|---------|
| `dev` / `build` / `start` | Next.js application |
| `lint` / `typecheck` | Application quality gates |
| `db:verify` | Full Supabase verification (alias) |
| `db:verify:postgres` | Generic Docker PostgreSQL (25 integrity) |
| `db:verify:supabase` | Local Supabase (25 + 30 + 5 + types) |
| `db:types` | Regenerate `types/database.generated.ts` |
| `test:api` | HTTP/API security smoke (6) |
| `test:app` | Playwright application smoke (8) |
