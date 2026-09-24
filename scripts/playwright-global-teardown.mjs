#!/usr/bin/env node
/**
 * Restores fixture org commercial state after E2E (e.g. M7 suspend specs).
 */

import { restoreFixtureOrgCommercialState } from "./playwright-fixture-orgs.mjs";

export default async function globalTeardown() {
  restoreFixtureOrgCommercialState();
}
