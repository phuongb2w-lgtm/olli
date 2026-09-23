import { defineConfig, devices } from "@playwright/test";

const port = process.env.PLAYWRIGHT_PORT ?? "3001";
const baseURL = process.env.PLAYWRIGHT_BASE_URL ?? `http://127.0.0.1:${port}`;

export default defineConfig({
  globalSetup: "./scripts/playwright-global-setup.mjs",
  testDir: "./tests/e2e",
  fullyParallel: false,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  workers: 1,
  reporter: "list",
  // Full-suite local runs: signIn waits up to 60s for GoTrue; default 30s test timeout caused flakes.
  timeout: 90_000,
  expect: {
    timeout: 60_000,
  },
  use: {
    baseURL,
    trace: "off",
    actionTimeout: 30_000,
  },
  webServer: {
    command: `node scripts/playwright-webserver.mjs`,
    url: baseURL,
    reuseExistingServer: false,
    timeout: 120_000,
  },
  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],
});
