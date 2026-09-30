/**
 * Wait until GoTrue admin API is reachable through Kong (same path as seed-auth-users.mjs).
 */

import { execSync } from "node:child_process";

const DEFAULT_MAX_ATTEMPTS = 90;
const DEFAULT_POLL_MS = 2000;
const FETCH_TIMEOUT_MS = 8000;

export function loadSupabaseStatusEnv(maxStatusAttempts = 5) {
  let lastError;
  for (let attempt = 1; attempt <= maxStatusAttempts; attempt++) {
    try {
      const raw = execSync("npx supabase status -o env", {
        encoding: "utf8",
        stdio: ["ignore", "pipe", "pipe"],
      });
      const env = {};
      for (const line of raw.split("\n")) {
        const match = line.match(/^([A-Z0-9_]+)="?(.*?)"?$/);
        if (match) env[match[1]] = match[2];
      }
      if (env.API_URL && env.SECRET_KEY) {
        return env;
      }
      lastError = new Error("supabase status missing API_URL or SECRET_KEY");
    } catch (error) {
      lastError = error;
    }
    if (attempt < maxStatusAttempts) {
      sleepSync(2000 * attempt);
    }
  }
  throw lastError ?? new Error("Failed to load supabase status env");
}

function sleepSync(ms) {
  const end = Date.now() + ms;
  while (Date.now() < end) {
    // brief sync backoff while waiting for supabase status after container restart
  }
}

export async function sleep(ms) {
  await new Promise((resolve) => setTimeout(resolve, ms));
}

function formatFetchFailure(error) {
  const parts = [error?.message ?? String(error)];
  const cause = error?.cause;
  if (cause?.code) parts.push(`cause=${cause.code}`);
  if (cause?.message && cause.message !== error.message) parts.push(cause.message);
  return parts.join("; ");
}

/**
 * Probe Kong-routed GoTrue admin list users (service role), matching @supabase/supabase-js admin calls.
 */
export async function probeKongAuthAdmin(apiUrl, serviceRoleKey) {
  const base = apiUrl.replace(/\/$/, "");
  const url = `${base}/auth/v1/admin/users?page=1&per_page=1`;
  try {
    const response = await fetch(url, {
      method: "GET",
      headers: {
        Authorization: `Bearer ${serviceRoleKey}`,
        apikey: serviceRoleKey,
      },
      signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
    });
    if (response.ok) {
      return { ready: true, detail: `HTTP ${response.status}`, url };
    }
    const snippet = (await response.text()).slice(0, 160);
    return {
      ready: false,
      detail: `HTTP ${response.status}${snippet ? `: ${snippet}` : ""}`,
      url,
    };
  } catch (error) {
    return {
      ready: false,
      detail: formatFetchFailure(error),
      url,
    };
  }
}

export async function waitForKongAuthAdminReady(options = {}) {
  const maxAttempts = options.maxAttempts ?? DEFAULT_MAX_ATTEMPTS;
  const pollMs = options.pollIntervalMs ?? DEFAULT_POLL_MS;
  const logEvery = options.logEvery ?? 5;
  const onAttempt = options.onAttempt;

  const env = options.env ?? loadSupabaseStatusEnv();
  const apiUrl = env.API_URL;
  const serviceRoleKey = env.SECRET_KEY;

  let lastDetail = "unknown";
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    const probe = await probeKongAuthAdmin(apiUrl, serviceRoleKey);
    lastDetail = probe.detail;
    if (probe.ready) {
      return { env, attempts: attempt, detail: probe.detail, adminUrl: probe.url };
    }
    if (onAttempt) {
      onAttempt({ attempt, maxAttempts, apiUrl, detail: probe.detail });
    } else if (attempt === 1 || attempt % logEvery === 0 || attempt === maxAttempts) {
      console.log(
        `Waiting for Auth admin via Kong at ${apiUrl} (attempt ${attempt}/${maxAttempts}): ${probe.detail}`,
      );
    }
    if (attempt < maxAttempts) {
      await sleep(pollMs);
    }
  }

  const err = new Error(
    `Auth admin API not ready after ${maxAttempts} attempts at ${apiUrl}: ${lastDetail}`,
  );
  err.apiUrl = apiUrl;
  err.lastDetail = lastDetail;
  throw err;
}
