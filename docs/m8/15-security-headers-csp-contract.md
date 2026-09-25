# M8-T06 — Security headers & Content-Security-Policy

**Task:** M8-T06  
**Baseline SHA:** `94be916ab9cdf1f26bd0304ca16bca061bced62e`  
**Scope:** Repository acceptance only (browser HTTP response policy for the Next.js app edge).

## Purpose

Harden Olli’s browser-facing HTTP posture for hosted deployment without changing M1–M7 domain semantics, RLS, or Supabase authorization models. Centralize policy generation so production, preview, and local development stay explicitly separated (aligned with [03 — Environment & secrets contract](./03-environment-secrets-contract.md)).

## Threat model (concise)

| Concern | Mitigation in T06 |
|--------|-------------------|
| XSS payload execution | CSP `default-src 'self'`, explicit `script-src` / `connect-src`, `object-src 'none'` |
| Clickjacking | CSP `frame-ancestors 'self'` |
| MIME confusion | `X-Content-Type-Options: nosniff` |
| Cross-origin referrer leakage | `Referrer-Policy: strict-origin-when-cross-origin` |
| Unneeded browser capabilities | Restrictive `Permissions-Policy` |
| SSL downgrade (production HTTPS) | `upgrade-insecure-requests` + HSTS on production tier only |
| Preview/dev weakening production | Tier-specific builder; production CSP never lists localhost dev origins |

Out of scope for T06 (documented elsewhere): application rate limiting ([09 — Risk register](./09-risk-register.md) M-03), WAF rules, Supabase Dashboard CORS, dependency audit automation.

## Architecture

Single source of truth:

- `scripts/lib/browser-security-policy.mjs` — builds CSP and companion headers from `process.env` + deployment tier.
- `next.config.ts` — applies `buildBrowserSecurityHeaders()` on `/:path*`.
- `src/lib/security/browser-security-policy.ts` — TypeScript re-export for importers inside `src/`.

No duplicate header layers (middleware/proxy does not re-emit CSP). Session refresh remains in `src/proxy.ts`.

Tier inference reuses `inferDeploymentTierFromEnv` from M8-T05 (`OLLI_DEPLOYMENT_TIER`, `VERCEL_ENV`, `NODE_ENV`).

## Response header policy (by tier)

| Header | development | preview | production |
|--------|-------------|---------|------------|
| `Content-Security-Policy` | Yes (dev connect + HMR) | Yes (hosted-style) | Yes + `upgrade-insecure-requests` |
| `X-Content-Type-Options: nosniff` | Yes | Yes | Yes |
| `Referrer-Policy: strict-origin-when-cross-origin` | Yes | Yes | Yes |
| `Permissions-Policy` (camera, mic, geo, payment, usb disabled) | Yes | Yes | Yes |
| `Strict-Transport-Security` | **No** | **No** | `max-age=63072000` (no `preload`, no `includeSubDomains`) |

`X-Frame-Options` was removed in favor of CSP `frame-ancestors` to avoid redundant framing policies.

## CSP directive rationale

| Directive | Production / preview value | Rationale |
|-----------|---------------------------|-----------|
| `default-src` | `'self'` | Baseline same-origin default |
| `base-uri` | `'self'` | Blocks base tag hijacks |
| `object-src` | `'none'` | No plugins/embed objects |
| `frame-ancestors` | `'self'` | Same-origin framing only |
| `form-action` | `'self'` | Auth/forms post to app origin |
| `script-src` | `'self' 'unsafe-inline'` | Next.js App Router inline bootstrap/hydration scripts (see relaxation note) |
| `style-src` | `'self' 'unsafe-inline'` | React inline `style` attributes + Next chunks |
| `img-src` | `'self' data: blob:` | App assets; no third-party image CDNs in codebase |
| `font-src` | `'self'` | Fonts from `_next/static` |
| `connect-src` | `'self'` + `NEXT_PUBLIC_SUPABASE_URL` origin | Supabase Auth/REST from browser; no Realtime usage in app |
| `worker-src` | `'self' blob:` | Next/worker bundles |
| `upgrade-insecure-requests` | production only | HTTPS enforcement on canonical production tier |

### Development-only additions

When tier is `development`:

- `connect-src` adds local Supabase (`http://127.0.0.1:54421`) and Next dev WebSocket hosts.
- `script-src` adds `'unsafe-eval'` for Next.js HMR (never emitted on production/preview tiers).

### Documented CSP relaxations

1. **`script-src 'unsafe-inline'` (production/preview)** — Required today because Next.js 16 App Router serves inline script blocks for hydration/bootstrap and nonce middleware is not configured. Narrower future work: nonce-based CSP via `proxy.ts` + `strict-dynamic`.
2. **`style-src 'unsafe-inline'`** — Required for React inline styles and framework behavior; global CSS remains `'self'`.

No `'unsafe-eval'` on production or preview tiers.

## Runtime sources audited (pre-implementation)

| Source | Finding |
|--------|---------|
| Fonts / CSS | `globals.css` + Tailwind v4; no Google Fonts CDN |
| Images | Same-origin; no `next/image` external domains |
| Scripts | Next bundles only; no third-party analytics SDKs |
| Browser `fetch` | Supabase client to `NEXT_PUBLIC_SUPABASE_URL` |
| Auth | Supabase SSR + `/auth/callback`; no extra OAuth iframes in UI |
| API routes | Same-origin; health check server-side fetch only |

## Environment differences

- **Production** — Fail-closed env validation (T05) plus strict CSP without localhost/`127.0.0.1` tokens; HSTS enabled without preload/`includeSubDomains` until operator deliberately opts in after DNS/TLS proof.
- **Preview** — Same CSP shape as production (no dev localhost entries); no HSTS (preview hosts are not the canonical production HSTS target).
- **Development** — Local Supabase and HMR exceptions; no HSTS (local HTTP).

## Verification (repository)

```bash
npm run test:security
npm run lint
npm run typecheck
npm run build
npm run verify
git diff --check
npm run db:migrations:count   # expect 58
```

### Repository acceptance evidence

| Check | Result |
|-------|--------|
| `npm run test:security` | PASS (9 contract checks) |
| `npm run lint` | PASS |
| `npm run typecheck` | PASS |
| `npm run build` | PASS |
| `npm run verify` | PASS (exit 0; includes Playwright 219/219 on green run) |
| `git diff --check` | PASS |
| `npm run db:migrations:count` | **58** |

## Deferred live-production evidence

Repository tests do **not** substitute for:

- TLS certificate validation on `https://olli.riuda.click`
- Browser DevTools confirmation of headers on a live Vercel production deployment
- Supabase Cloud link/push/smoke
- Auth Site URL / redirect URL validation on production project
- SMTP and live invitation flows

After first production deploy, operators should spot-check one authenticated page: CSP present, no console CSP violations, Supabase auth refresh working.

## Related

- [12 — Application deployment operator procedure](./12-application-deployment-operator-procedure.md)
- [08 — Release & rollback runbook](./08-release-rollback-runbook.md)
- [09 — Risk register](./09-risk-register.md) (H-03, M-03)
