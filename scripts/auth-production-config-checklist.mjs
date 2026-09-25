#!/usr/bin/env node
/**
 * Operator checklist for Supabase Auth + SMTP (dashboard-only settings — not scraped).
 */

import { OLLI_CANONICAL_PRODUCTION_ORIGIN } from "./lib/auth-app-origin.mjs";

const items = [
  `DNS: olli.riuda.click → Vercel (HTTPS/TLS active)`,
  `Vercel Production custom domain: ${OLLI_CANONICAL_PRODUCTION_ORIGIN}`,
  `NEXT_PUBLIC_OLLI_CANONICAL_APP_ORIGIN=${OLLI_CANONICAL_PRODUCTION_ORIGIN} on production host`,
  `Supabase Auth Site URL: ${OLLI_CANONICAL_PRODUCTION_ORIGIN} (not a *.vercel.app preview host)`,
  `Supabase Redirect URLs include: ${OLLI_CANONICAL_PRODUCTION_ORIGIN}/auth/callback** (confirm glob in Dashboard)`,
  `Optional staging origin only if used — never set Site URL to preview hostname`,
  `Enable signup: OFF (Auth Admin provisioning only)`,
  `SMTP: host, port, TLS, username, password configured in Supabase → Project Settings → Auth → SMTP`,
  `Sender: transactional mailbox on RIUDA domain (e.g. noreply@…); SPF/DKIM/DMARC per provider docs`,
  `Templates: Invite, Reset password, Confirm signup (if used) — Olli branding, no secrets in body`,
  `After SMTP: send test invite + reset from staging; Owner center provision sends invite (not plaintext password)`,
  `OLLI_CENTER_PROVISION_USE_INVITE: omit or true in production`,
  `OLLI_STAFF_PROVISION_USE_INVITE: omit or true in production`,
];

console.log("M8 Auth / SMTP operator checklist (manual Dashboard + DNS steps):\n");
for (const line of items) {
  console.log(`[ ] ${line}`);
}
console.log("\nRun npm run test:auth-redirect and npm run app:production:env-check after host env is set.");
