#!/usr/bin/env node
/**
 * M8-T10 repository recovery gate (static contracts + local synthetic DR rehearsal).
 */

import { spawnSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { runRecoveryDrill } from "./recovery-drill.mjs";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const staticOnly = process.argv.includes("--static-only");
const results = [];

function record(id, name, passed, detail = "") {
  results.push({ id, name, passed, detail });
  console.log(`${passed ? "PASS" : "FAIL"} RC-${id}: ${name}${detail ? ` — ${detail}` : ""}`);
}

function runStaticContracts() {
  const runbook = join(root, "docs", "m8", "19-backup-restore-dr-runbook.md");
  record(1, "T10 runbook exists", existsSync(runbook));

  const contract = readFileSync(join(root, "docs", "m8", "19-backup-restore-dr-runbook.md"), "utf8");
  record(2, "rebuild vs restore documented", /rebuild/i.test(contract) && /restore/i.test(contract));

  const drillSrc = readFileSync(join(root, "scripts", "recovery-drill.mjs"), "utf8");
  record(
    3,
    "recovery drill refuses Cloud by default",
    drillSrc.includes("assertLocalRecoveryTarget") && drillSrc.includes("assertProductionRestoreAllowed"),
  );

  const child = spawnSync(process.execPath, [join(root, "scripts", "recovery-drill.mjs")], {
    cwd: root,
    env: {
      ...process.env,
      NEXT_PUBLIC_SUPABASE_URL: "https://exampleproject.supabase.co",
      OLLI_CONFIRM_PRODUCTION_RESTORE: "",
      OLLI_RECOVERY_SKIP_SUPABASE_STATUS: "1",
    },
    encoding: "utf8",
  });
  const combined = `${child.stdout}\n${child.stderr}`;
  record(
    4,
    "Cloud URL blocked without production restore confirm",
    child.status !== 0 && /Refusing recovery drill against Supabase Cloud/i.test(combined),
    `exit=${child.status}`,
  );

  const backup = spawnSync(process.execPath, [join(root, "scripts", "backup-check.mjs"), "--static-only"], {
    cwd: root,
    encoding: "utf8",
  });
  record(5, "backup-check static pass", backup.status === 0, `exit=${backup.status}`);
}

async function main() {
  console.log("==> M8-T10 recovery gate");
  runStaticContracts();

  if (!staticOnly) {
    try {
      runRecoveryDrill({ quiet: false });
      record(6, "local synthetic backup/restore rehearsal", true);
    } catch (error) {
      record(6, "local synthetic backup/restore rehearsal", false, error.message);
    }
  } else {
    record(6, "local synthetic backup/restore rehearsal", true, "skipped (--static-only)");
  }

  const failed = results.filter((r) => !r.passed);
  console.log(`\nRecovery gate: ${results.length - failed.length}/${results.length} passed`);
  if (failed.length) process.exit(1);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
