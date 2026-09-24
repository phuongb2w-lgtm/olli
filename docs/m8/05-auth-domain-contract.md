# M8 — Auth & Domain Contract

**Production app origin:** `https://olli.riuda.click`

## DNS & HTTPS

| Record | Target | Notes |
|--------|--------|-------|
| `olli.riuda.click` | App host (CNAME or A/AAAA per provider) | TLS terminated at host (auto cert) |
| Supabase | Default `*.supabase.co` | No custom domain required for MVP |

All production cookies and redirects assume **HTTPS** and a **single canonical host** (no mixed `www`/apex unless redirect rules added in M8-T04).

## Supabase Auth dashboard settings (production project)

| Setting | Value |
|---------|--------|
| **Site URL** | `https://olli.riuda.click` |
| **Redirect URLs** | `https://olli.riuda.click/**` (confirm exact glob syntax in Supabase UI); include login callback paths |
| **Enable signup** | **Off** (matches local `enable_signup = false`) — users created via Auth Admin only |
| **JWT expiry** | Default or align with local `jwt_expiry = 3600` after session UX review |
| **Email** | SMTP configured (staff invites; Owner first access — see gaps) |

Local `supabase/config.toml` uses `http://127.0.0.1:54421` — **must not** ship to production project settings.

## Application auth flows (current product)

| Flow | Status | Production implication |
|------|--------|------------------------|
| Email + password sign-in | Implemented (`signInWithPassword`) | Owner/staff must have password set in Auth |
| Sign-out | Implemented | OK |
| Registration | Disabled | OK |
| Magic link / password reset UI | **Deferred** (M0) | **Gap** — see blockers |
| Staff provisioning | `inviteUserByEmail` default | Requires SMTP + redirect URL allowlist |
| Center provisioning | `createUser` + `email_confirm: true`, **no password** | Operator must set password or send invite **outside app** today |

## Session & cookies

- `@supabase/ssr` cookie session via `src/lib/supabase/server.ts` and `proxy.ts`.
- Locale cookie `LOCALE_COOKIE` — `sameSite: lax`, `path: /` (production: ensure `Secure` flag when host sets secure cookies — verify in M8-T04).

## CORS / origins

- Browser talks to Supabase project URL directly with publishable key (Supabase-managed CORS).
- Next.js app origin must match Auth redirect allowlist.
- No custom API routes in repo — no separate CORS layer.

## RLS & service role (unchanged semantics)

| Role | Use |
|------|-----|
| `authenticated` | Normal staff/Owner JWT — all product RPCs and RLS |
| `service_role` | Operator scripts, provisioning orchestration, subscription lifecycle RPCs |
| Primary Owner | Commercial reads + onboarding; cannot EXECUTE operator subscription mutations (M7) |

## M7 commercial gating (production)

- `has_permission()` / `is_active_app_user()` require **active** subscription for normal use.
- Provisioning subscription → Owner onboarding → operator **activate** before full staff use.
- Document operator step in [08 — Release runbook](./08-release-rollback-runbook.md).

## Gap summary

| ID | Current behavior | Production risk | M8 task |
|----|------------------|-------------------|---------|
| A-01 | Owner Auth user without password after center provision | Owner cannot sign in | M8-T04 |
| A-02 | No in-app password reset | Lockout / support burden | M8-T04 (minimal reset or documented operator procedure) |
| A-03 | Local Inbucket for mail | Staff invites fail silently | M8-T04 SMTP |
| A-04 | Auth site URL localhost in config.toml only | Misconfiguration if copied to cloud | M8-T03 dashboard checklist |
