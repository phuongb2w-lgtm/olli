#!/usr/bin/env node
/**
 * Production-safe HTTP smoke checks against a deployed Next.js host.
 * Does not mutate data or run Playwright fixtures.
 */

import { assertHostedAppRuntimeEnv, resolveAppBaseUrl } from "./lib/app-production.mjs";

let failed = false;

function pass(msg) {
  console.log(`PASS: ${msg}`);
}

function fail(msg) {
  console.error(`FAIL: ${msg}`);
  failed = true;
}

async function fetchStatus(label, path, { expectStatus = 200, expectJson } = {}) {
  const base = resolveAppBaseUrl();
  const url = `${base}${path.startsWith("/") ? path : `/${path}`}`;
  console.log(`==> ${label}: GET ${url}`);
  let response;
  try {
    response = await fetch(url, { redirect: "manual", cache: "no-store" });
  } catch (error) {
    fail(`${label}: network error (${error.message})`);
    return;
  }

  if (response.status !== expectStatus) {
    fail(`${label}: expected HTTP ${expectStatus}, got ${response.status}`);
    return;
  }

  if (expectJson) {
    let body;
    try {
      body = await response.json();
    } catch {
      fail(`${label}: response is not JSON`);
      return;
    }
    for (const [key, value] of Object.entries(expectJson)) {
      if (body[key] !== value) {
        fail(`${label}: expected ${key}=${JSON.stringify(value)}, got ${JSON.stringify(body[key])}`);
        return;
      }
    }
  }

  pass(label);
}

try {
  assertHostedAppRuntimeEnv();
} catch (error) {
  fail(error.message);
  process.exit(1);
}

await fetchStatus("health endpoint", "/api/health", {
  expectStatus: 200,
  expectJson: { status: "ok", app: "olli" },
});

await fetchStatus("login page", "/login", { expectStatus: 200 });

const base = resolveAppBaseUrl();
const rootResponse = await fetch(`${base}/`, { redirect: "manual", cache: "no-store" });
if (rootResponse.status !== 307 && rootResponse.status !== 302 && rootResponse.status !== 303) {
  fail(`protected root redirect: expected 302/307/303, got ${rootResponse.status}`);
} else {
  pass("protected root redirects unauthenticated users");
}

const staticProbe = await fetch(`${base}/favicon.ico`, { cache: "no-store" });
if (!staticProbe.ok) {
  fail(`static asset probe (/favicon.ico): HTTP ${staticProbe.status}`);
} else {
  pass("static asset probe (/favicon.ico)");
}

if (failed) {
  console.error("Application production smoke FAILED.");
  process.exit(1);
}
console.log("Application production smoke PASSED.");
