import type { NextConfig } from "next";
import createNextIntlPlugin from "next-intl/plugin";
import { execSync } from "node:child_process";
import {
  buildBrowserSecurityHeaders,
  inferSecurityPolicyTier,
} from "./scripts/lib/browser-security-policy.mjs";

const withNextIntl = createNextIntlPlugin("./src/i18n/request.ts");

function resolveGitSha(): string {
  if (process.env.VERCEL_GIT_COMMIT_SHA?.trim()) {
    return process.env.VERCEL_GIT_COMMIT_SHA.trim();
  }
  if (process.env.OLLI_GIT_SHA?.trim()) {
    return process.env.OLLI_GIT_SHA.trim();
  }
  try {
    return execSync("git rev-parse HEAD", { encoding: "utf8" }).trim();
  } catch {
    return "unknown";
  }
}

const nextConfig: NextConfig = {
  env: {
    OLLI_GIT_SHA: resolveGitSha(),
    NEXT_PUBLIC_OLLI_CANONICAL_APP_ORIGIN:
      process.env.NEXT_PUBLIC_OLLI_CANONICAL_APP_ORIGIN ?? "https://olli.riuda.click",
  },
  async headers() {
    const tier = inferSecurityPolicyTier(process.env);
    const securityHeaders = buildBrowserSecurityHeaders(process.env, tier);
    return [
      {
        source: "/:path*",
        headers: securityHeaders,
      },
    ];
  },
};

export default withNextIntl(nextConfig);
