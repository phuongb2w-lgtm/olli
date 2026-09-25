# M8 — Auth, Domain & SMTP Operator Procedure (M8-T04)

**Application origin:** `https://olli.riuda.click`  
**Supabase Auth:** production project Dashboard (not in git)  
**Repository:** password recovery UI, `/auth/callback`, invite-based Owner provisioning

This procedure complements [05 — Auth & domain contract](./05-auth-domain-contract.md) and [03 — Environment & secrets](./03-environment-secrets-contract.md).

## 1. Separation of concerns

| Layer | Owner | Verified by |
|-------|-------|-------------|
| DNS + TLS | RIUDA / DNS provider | Browser + Vercel domain UI |
| Vercel custom domain | RIUDA | Vercel Production domain |
| Next.js env | RIUDA | `npm run app:production:env-check` |
| Supabase Auth Site URL / redirects | RIUDA | Manual checklist + staging smokes |
| Supabase SMTP | RIUDA | Test email delivery |
| Product flows | Repository | `npm run verify`, Playwright |

**Live email acceptance** requires completed SMTP + Dashboard steps. The repository does not store SMTP passwords.

## 2. DNS and TLS

1. Create **CNAME** (or A/AAAA per Vercel instructions) for `olli.riuda.click` → Vercel production.
2. Wait for certificate issuance (Vercel → Domains).
3. Confirm apex/`www` policy: canonical host is **`https://olli.riuda.click`** (no mixed canonical hosts unless redirect rules are added).

## 3. Vercel production environment

Set on **Production** scope (see [12 — Application deployment](./12-application-deployment-operator-procedure.md)):

```
NEXT_PUBLIC_OLLI_CANONICAL_APP_ORIGIN=https://olli.riuda.click
NEXT_PUBLIC_SUPABASE_URL=https://<ref>.supabase.co
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=<publishable>
SUPABASE_SECRET_KEY=<service_role>
OLLI_SUPABASE_PROJECT_REF=<ref>
```

Optional (defaults are production-safe):

```
OLLI_CENTER_PROVISION_USE_INVITE=true
OLLI_STAFF_PROVISION_USE_INVITE=true
```

Run:

```powershell
npm run app:production:env-check
```

## 4. Supabase Auth dashboard (production project)

**Authentication → URL configuration**

| Setting | Value |
|---------|--------|
| **Site URL** | `https://olli.riuda.click` |
| **Redirect URLs** | `https://olli.riuda.click/auth/callback**` and `https://olli.riuda.click/**` per Supabase glob syntax — **must include** `/auth/callback` |

Rules:

- Do **not** set Site URL to a `*.vercel.app` preview hostname.
- Add staging origins to Redirect URLs only if staging is used; keep Site URL on production canonical origin.
- **Enable signup:** OFF (matches local `enable_signup = false`).

## 5. SMTP (Supabase → Project Settings → Auth → SMTP)

Configure a **transactional sender** on the RIUDA mail domain (dedicated mailbox or subdomain). Cloudflare Email Routing alone does **not** provide SMTP submission for Supabase.

Document in your secret store (not git):

| Field | Notes |
|-------|--------|
| Host / port | Provider-specific (often 587 STARTTLS or 465 SSL) |
| Username / password | SMTP credentials |
| Sender email | e.g. `noreply@…` or `olli@…` on authenticated domain |
| Sender name | `Olli` or `Olli by RIUDA` |

**SPF / DKIM / DMARC:** follow your mail provider’s DNS instructions. Do not mark sender auth PASS until DNS probes succeed.

**Rate limits:** follow provider; Supabase may also throttle Auth emails.

## 6. Email templates (Auth → Email templates)

Minimum templates to review:

| Template | Used for |
|----------|----------|
| **Invite user** | Primary Owner (center provision) + staff provision |
| **Reset password** | Forgot-password flow |
| **Confirm signup** | Only if enabled (product keeps signup off) |

Each template should:

- Name **Olli** clearly
- Link to **`https://olli.riuda.click`** paths (links are generated from Site URL + `redirectTo`)
- Avoid embedding secrets or initial passwords
- Use EN copy; add VI if RIUDA requires localized Auth mail (optional MVP)

## 7. Product flows (repository behavior)

| Flow | Mechanism |
|------|-----------|
| Primary Owner first login | `inviteUserByEmail` during center provisioning → email → `/auth/callback` → `/update-password` |
| Staff first login | Existing M6 invite + same callback → `/update-password` |
| Password recovery | `/forgot-password` → `resetPasswordForEmail` → callback → `/update-password` |
| Sign-in | Unchanged email + password |

RIUDA **never** receives or stores a reusable Owner plaintext password from provisioning.

Operator checklist script (prints steps):

```powershell
node scripts/auth-production-config-checklist.mjs
```

Redirect safety regression:

```powershell
npm run test:auth-redirect
```

## 8. Staging / preview safety

- Preview deployments must **not** use production Supabase when `OLLI_PRODUCTION_SUPABASE_PROJECT_REF` guard is set (see `scripts/lib/app-production.mjs`).
- Do not widen Redirect URLs to `**` on untrusted preview hosts for production Site URL.

## 9. Acceptance

**Repository:** M8-T04 CLOSED when `npm run verify` passes including new auth tests.

**Live Auth/email:** RIUDA sign-off when:

1. Owner invite email received after `provision-customer-center`
2. Owner completes `/update-password` and signs in
3. Staff invite email received
4. Forgot-password email received and completes reset

Until then: **IMPLEMENTATION COMPLETE / LIVE AUTH-EMAIL ACCEPTANCE PENDING**.
