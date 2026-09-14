# M0-T05 — Auth Application Flow

## Public configuration

Browser code uses:

- `NEXT_PUBLIC_SUPABASE_URL`
- `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`

Legacy `NEXT_PUBLIC_SUPABASE_ANON_KEY` is **not** canonical. Secret/service keys never reach client bundles.

## Client architecture

| Module | Use |
|--------|-----|
| `src/lib/supabase/client.ts` | Client Components only |
| `src/lib/supabase/server.ts` | Server Components, Server Actions, Route Handlers |
| `src/lib/supabase/proxy.ts` | Session refresh logic |
| `src/proxy.ts` | Next.js 16 network boundary (replaces deprecated `middleware.ts`) |

## Identity validation

1. `supabase.auth.getClaims()` validates the Auth session server-side.
2. `app_user` row resolved by `auth_user_id = auth.uid()`.
3. `organization` loaded via trusted `app_user.organization_id`.

### Outcomes

| State | Behavior |
|-------|----------|
| No Auth session | Redirect `/login` |
| Auth without `app_user` | Access denied screen |
| Inactive `app_user` | Access denied |
| Active mapped user | Protected shell |

Organization context is **never** taken from client-supplied UUIDs.

## Staff-only scope (M0-T05)

Implemented: email/password sign-in, sign-out.

Deferred: registration, magic link, password reset product flows, invitations.

## Elevated credentials

Server Components use the **user session** client. Secret key is reserved for fixture scripts (`scripts/seed-auth-users.mjs`) only.
