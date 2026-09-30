#!/usr/bin/env node
/**
 * Verification harness: block until Kong-routed GoTrue admin API accepts service-role requests.
 */

import { waitForKongAuthAdminReady } from "./lib/local-supabase-auth-ready.mjs";

async function main() {
  const result = await waitForKongAuthAdminReady();
  console.log(
    `Auth admin ready via Kong (${result.attempts} attempt(s), ${result.detail}).`,
  );
}

main().catch((error) => {
  console.error(error.message ?? error);
  process.exit(1);
});
