#!/usr/bin/env node
/**
 * Show local vs linked migration state and highlight pending remote applies.
 */

import { migrationCount, listMigrationFiles, latestMigrationVersion } from "./lib/migration-inventory.mjs";
import {
  assertLinkedProjectMatches,
  assertProductionRuntimeEnv,
  assertProductionSupabaseUrl,
  execSupabase,
  requireExpectedProjectRef,
} from "./lib/supabase-production.mjs";

function parseMigrationList(output) {
  const remote = new Set();
  try {
    const json = JSON.parse(output);
    for (const row of json.migrations ?? []) {
      if (row.remote) remote.add(String(row.remote));
    }
    return { remote };
  } catch {
    for (const line of output.split("\n")) {
      const jsonMatch = line.match(/"remote"\s*:\s*"(\d+)"/);
      if (jsonMatch) {
        remote.add(jsonMatch[1]);
        continue;
      }
  
      const tableMatch = line.match(
        /^\s*`?\d+`?\s*\|\s*`?(\d+)`?\s*\|/
      );
      if (tableMatch) {
        remote.add(tableMatch[1]);
      }
    }
  
    return { remote };
  }
}

try {
  const { url } = assertProductionRuntimeEnv();
  const urlRef = assertProductionSupabaseUrl(url);
  const expectedRef = requireExpectedProjectRef(urlRef);
  assertLinkedProjectMatches(expectedRef);

  const repoCount = migrationCount();
  const repoLatest = latestMigrationVersion();
  const repoFiles = listMigrationFiles();

  console.log(`Repository migrations: ${repoCount} (latest version prefix: ${repoLatest})`);

  const raw = execSupabase("migration list --linked");
  console.log(raw.trimEnd());

  const { remote } = parseMigrationList(raw);
  const pending = repoFiles.filter((file) => {
    const version = file.match(/^(\d+)/)?.[1];
    return version && !remote.has(version);
  });

  if (pending.length === 0) {
    console.log("PASS: No pending repository migrations for linked remote (by version prefix).");
  } else {
    console.log(`PENDING: ${pending.length} migration(s) not recorded on remote:`);
    for (const file of pending) console.log(`  - ${file}`);
    process.exitCode = 2;
  }
} catch (error) {
  console.error(`FAIL: ${error.message}`);
  process.exit(1);
}
