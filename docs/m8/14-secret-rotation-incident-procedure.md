# M8 — Secret rotation & suspected leak response

**Scope:** Olli production/staging credentials managed by RIUDA. No automated rotation in-repo.

## Environment matrix (where secrets live)

| Secret | Owner | Configured in | Used by |
|--------|-------|---------------|---------|
| Supabase publishable key | RIUDA | Vercel Production/Preview env, `.env.local` (dev) | Browser + server user clients |
| Supabase service role (`SUPABASE_SECRET_KEY`) | RIUDA | Vercel **Production** server env only; operator secret store | `createAdminClient()`, provisioning Server Actions |
| Supabase personal access token | RIUDA | Operator machine / CI secret (remote jobs only) | `supabase login` non-interactive |
| Postgres DB password | RIUDA | Supabase Dashboard | Operator CLI, not Next.js |
| Auth SMTP | RIUDA | Supabase Dashboard → Auth → SMTP | Supabase Auth email only |
| Vercel/hosting token | RIUDA | Vercel team settings | Deploy pipeline |

See [03 — Environment contract](./03-environment-secrets-contract.md) for full variable inventory.

## Rotation procedure (each credential)

For every rotation:

1. **Rotate at provider** (Supabase Dashboard, Vercel, SMTP vendor).
2. **Update secret store** (Vercel env, operator vault — never commit).
3. **Redeploy / restart** Next.js production if app env changed; re-link CLI if project token changed.
4. **Revoke old credential** at provider when dual-write window ends.
5. **Verify:** `GET /api/health`, `npm run app:production:smoke`, `npm run db:production:smoke`, one Owner invite + staff invite smoke on staging.

### Supabase service role

1. Supabase Dashboard → Project Settings → API → rotate service role key.
2. Update `SUPABASE_SECRET_KEY` on Vercel Production (and staging if used).
3. Redeploy application; run provisioning smokes on staging.
4. Confirm old key rejected (401 on service-role-only call).

### Supabase access token (`SUPABASE_ACCESS_TOKEN`)

1. Revoke token in Supabase account settings; create new token.
2. Update CI/operator env only.
3. Re-run `db:production:link-verify` from release SHA.

### Database password

1. Reset in Supabase Dashboard (Database settings).
2. Update operator/CI stores; update any direct `postgres://` tooling (not app runtime).
3. Confirm migrations/smokes still pass via CLI link.

### Auth SMTP

1. Rotate SMTP user/password at mail provider.
2. Update Supabase Auth SMTP settings only.
3. Send test reset + invite from staging project.

### Hosting / Vercel token

1. Rotate in Vercel team settings.
2. Update CI/deploy automation secrets.
3. Trigger dry-run deploy.

## Suspected secret leak

1. **Contain:** rotate affected credential immediately (assume compromise).
2. **Scope:** identify whether leak was git, logs, bundle, or host env (use `npm run test:env` + provider audit logs).
3. **Evict:** revoke old keys/tokens at provider.
4. **Redeploy** all hosts that received the secret.
5. **Review:** Auth logs for anomalous Admin API use; RLS still enforced for user paths.
6. **Document** incident time, rotated credentials, and verification smokes in RIUDA ops log.

**Never** paste live secrets into tickets, chat, or docs.
