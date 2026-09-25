/**
 * M8-T09: Foundation CI must orchestrate repository gates (not a divergent policy).
 */

import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const workflowPath = join(root, ".github", "workflows", "foundation-ci.yml");

/** Commands or steps that must appear in foundation-ci.yml */
export const REQUIRED_CI_SUBSTRINGS = [
  "supabase start",
  "supabase db reset",
  "npm run test:env",
  "npm run test:security",
  "npm run test:rate-limit",
  "npm run test:operator",
  "npm run test:auth-redirect",
  "npm run lint",
  "npm run typecheck",
  "npm run build",
  "npm run test:api",
  "npm run test:app",
];

export function readFoundationCiWorkflow() {
  return readFileSync(workflowPath, "utf8");
}

export function assertFoundationCiContract() {
  const yaml = readFoundationCiWorkflow();
  const missing = REQUIRED_CI_SUBSTRINGS.filter((token) => !yaml.includes(token));
  if (missing.length > 0) {
    throw new Error(
      `foundation-ci.yml is missing mandatory step(s): ${missing.join(", ")}`,
    );
  }
}
