# M8 — Auth & Domain Contract

**Production app origin:** `https://olli.riuda.click`

Operator steps: [13 — Auth & SMTP procedure](./13-auth-smtp-operator-procedure.md)

## DNS & HTTPS

| Record | Target | Notes |
|--------|--------|-------|
| `olli.riuda.click` | Vercel (CNAME or A/AAAA per provider) | TLS at host; canonical browser origin |
| Supabase API | Default `https://<ref>.supabase.co` | No custom Auth domain required for MVP |

All production cookies and redirects assume **HTTPS** and a **single canonical host** (no mixed `www`/apex unless redirect rules are added).

## Supabase Auth dashboard settings (production project)

| Setting | Value |
|---------|--------|
| **Site URL** | `https://olli.riuda.click` |
| **Redirect URLs** | Must allow `https://olli.riuda.click/auth/callback**` and app paths used by Auth emails; confirm glob syntax in Supabase UI |
| **Enable signup** | **Off** — users created via Auth Admin only |
| **JWT expiry** | Default or align with local `jwt_expiry = 3600` after session UX review |
| **Email** | Production SMTP configured (see procedure §5) |

Local `supabase/config.toml` uses `http://127.0.0.1:3000` for Site URL — **must not** be copied to the production project.

## Application auth flows

| Flow | Status | Production implication |
|------|--------|------------------------|
| Email + password sign-in | Implemented | Owner/staff after password setup |
| Sign-out | Implemented | OK |
| Registration | Disabled | OK |
| Forgot password | **M8-T04** — `/forgot-password` | Neutral response; Supabase reset email |
| Password / invite setup | **M8-T04** — `/update-password` after `/auth/callback` | Owner + staff first credential |
| Staff provisioning | `inviteUserByEmail` + `redirectTo` callback | Requires SMTP + redirect allowlist |
| Center provisioning | **`inviteUserByEmail`** (default) | Owner setup email; no operator password |

### Redirect contract

- Auth email links target `{appOrigin}/auth/callback?next=/update-password` (or safe internal `next`).
- `resolveSafeRedirectPath` rejects external and protocol-relative targets.
- Production `appOrigin` from `NEXT_PUBLIC_OLLI_CANONICAL_APP_ORIGIN` (`https://olli.riuda.click`).
- Preview hostnames must not become production **Site URL**.

## Session & cookies

- `@supabase/ssr` cookie session via `src/lib/supabase/server.ts` and `proxy.ts`.
- Locale cookie `LOCALE_COOKIE` — `sameSite: lax`, `path: /` (host should set `Secure` on HTTPS).

## CORS / origins

- Browser talks to Supabase project URL with publishable key.
- Next.js app origin must match Auth redirect allowlist.

## RLS & service role (unchanged semantics)

| Role | Use |
|------|-----|
| `authenticated` | Normal staff/Owner JWT — all product RPCs and RLS |
| `service_role` | Operator scripts, provisioning orchestration, subscription lifecycle RPCs |
| Primary Owner | Commercial reads + onboarding; cannot EXECUTE operator subscription mutations (M7) |

## M7 commercial gating (production)

- `has_permission()` / `is_active_app_user()` require **active** subscription for normal use.
- Provisioning subscription → Owner onboarding → operator **activate** before full staff use.

## Gap summary (post T04 repository)

| ID | Status | Notes |
|----|--------|-------|
| A-01 | **Addressed (repo)** | Owner invite + password setup path |
| A-02 | **Addressed (repo)** | Forgot password + update password |
| A-03 | **Live pending** | SMTP in Supabase Dashboard |
| A-04 | **Checklist** | Site URL ≠ preview; see procedure |
