#!/usr/bin/env node
/**
 * Ensures fixture orgs A/B are commercially active before E2E runs.
 */

import { restoreFixtureOrgCommercialState } from "./playwright-fixture-orgs.mjs";

export default async function globalSetup() {
  try {
    restoreFixtureOrgCommercialState();
  } catch (error) {
    console.warn("[playwright globalSetup] fixture restore skipped:", error);
  }
}
