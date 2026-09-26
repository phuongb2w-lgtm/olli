/**
 * M8-T09: npm run verify must retain mandatory release gates (composition only).
 */

import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..");

/** Substrings that must appear in the verify script (actual command names). */
export const REQUIRED_VERIFY_SUBSTRINGS = [
  "db:verify",
  "test:i18n",
  "test:env",
  "test:security",
  "test:rate-limit",
  "test:operator",
  "test:recovery",
  "test:auth-redirect",
  "test:smoke:static",
  "lint",
  "typecheck",
  "build",
  "test:app",
];

export function readVerifyScript() {
  const pkgPath = join(root, "package.json");
  const pkg = JSON.parse(readFileSync(pkgPath, "utf8"));
  const verify = pkg.scripts?.verify;
  if (!verify || typeof verify !== "string") {
    throw new Error("package.json scripts.verify is missing or not a string");
  }
  return verify;
}

export function assertVerifyGateComposition() {
  const verify = readVerifyScript();
  const missing = REQUIRED_VERIFY_SUBSTRINGS.filter((token) => !verify.includes(token));
  if (missing.length > 0) {
    throw new Error(
      `npm run verify is missing mandatory gate(s): ${missing.join(", ")}`,
    );
  }
  return verify;
}
