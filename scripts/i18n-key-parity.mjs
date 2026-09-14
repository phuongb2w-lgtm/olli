#!/usr/bin/env node
/**
 * M0-T06: structural key parity between messages/vi.json and messages/en.json.
 * Requires exact same nested key structure; values may differ.
 */

import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");

function collectKeys(obj, prefix = "") {
  const keys = [];
  for (const [key, value] of Object.entries(obj)) {
    const path = prefix ? `${prefix}.${key}` : key;
    if (value !== null && typeof value === "object" && !Array.isArray(value)) {
      keys.push(...collectKeys(value, path));
    } else {
      keys.push(path);
    }
  }
  return keys.sort();
}

function loadMessages(name) {
  const path = join(root, "messages", `${name}.json`);
  return JSON.parse(readFileSync(path, "utf8"));
}

const vi = loadMessages("vi");
const en = loadMessages("en");
const viKeys = collectKeys(vi);
const enKeys = collectKeys(en);

const viSet = new Set(viKeys);
const enSet = new Set(enKeys);

const missingInEn = viKeys.filter((k) => !enSet.has(k));
const missingInVi = enKeys.filter((k) => !viSet.has(k));

let failed = false;

if (missingInEn.length > 0) {
  failed = true;
  console.error("Missing in en.json:");
  for (const key of missingInEn) console.error(`  - ${key}`);
}

if (missingInVi.length > 0) {
  failed = true;
  console.error("Missing in vi.json:");
  for (const key of missingInVi) console.error(`  - ${key}`);
}

if (failed) {
  process.exit(1);
}

console.log(`PASS: i18n key parity (${viKeys.length} keys in vi, ${enKeys.length} keys in en)`);
