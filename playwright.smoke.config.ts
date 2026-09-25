import path from "node:path";
import { defineConfig, devices } from "@playwright/test";

if (!process.env.PLAYWRIGHT_BROWSERS_PATH && process.env.LOCALAPPDATA) {
  process.env.PLAYWRIGHT_BROWSERS_PATH = path.join(process.env.LOCALAPPDATA, "ms-playwright");
}

const port = process.env.PLAYWRIGHT_PORT ?? "3001";
const baseURL = process.env.PLAYWRIGHT_BASE_URL ?? `http://127.0.0.1:${port}`;

/** Focused production-critical routes — not a substitute for full `npm run test:app`. */
export default defineConfig({
  globalSetup: "./scripts/playwright-global-setup.mjs",
  globalTeardown: "./scripts/playwright-global-teardown.mjs",
  testDir: "./tests/e2e",
  testMatch: ["m8-production-critical-smoke.spec.ts"],
  fullyParallel: false,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  workers: 1,
  reporter: "list",
  timeout: 90_000,
  expect: { timeout: 60_000 },
  use: {
    baseURL,
    trace: "off",
    actionTimeout: 30_000,
  },
  webServer: {
    command: "node scripts/playwright-webserver.mjs",
    url: baseURL,
    reuseExistingServer: false,
    timeout: 120_000,
  },
  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],
});
