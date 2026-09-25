import type { NextConfig } from "next";
import createNextIntlPlugin from "next-intl/plugin";
import { execSync } from "node:child_process";

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
    return [
      {
        source: "/:path*",
        headers: [
          { key: "X-Content-Type-Options", value: "nosniff" },
          { key: "X-Frame-Options", value: "SAMEORIGIN" },
          { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
          {
            key: "Permissions-Policy",
            value: "camera=(), microphone=(), geolocation=()",
          },
          {
            key: "Strict-Transport-Security",
            value: "max-age=63072000; includeSubDomains",
          },
        ],
      },
    ];
  },
};

export default withNextIntl(nextConfig);
