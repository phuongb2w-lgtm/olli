# M0-T05 — i18n Foundation

## Locales

- `vi` — default
- `en`

Message files: `messages/vi.json`, `messages/en.json` (matching key structure).

## URL strategy

No mandatory `/vi/...` or `/en/...` prefixes for the admin app. Locale is resolved without path segments.

## Fallback chain (authenticated)

```
app_user.preferred_locale
→ organization.default_locale
→ olli_locale cookie
→ vi
```

Pre-auth login defaults to Vietnamese with a visible language switch (persists via `olli_locale` cookie only).

Authenticated language switch:

1. Updates visible UI immediately
2. Sets `olli_locale` cookie
3. Persists `app_user.preferred_locale` via `set_own_preferred_locale()` RPC (RLS-governed, no service credential)
4. Keeps user on the same application context

## Formatting

`src/lib/formatting/index.ts` — locale-aware date, date/time, integer, and VND currency via `Intl` APIs.

## Translation namespaces

Machine codes use dotted namespaces, e.g.:

- `status.enrollment.active`
- `permissions.student.read`

Only keys exposed in the M0 shell are translated; the convention is established for later modules.
