import "server-only";

import { headers } from "next/headers";
import { hashRateLimitSubject } from "@/lib/rate-limit/fingerprint";

/**
 * Trusted client IP for rate limiting on Vercel/serverless deployments.
 * Uses the first hop in `x-forwarded-for` (Vercel-injected) or `x-real-ip`.
 * Not used for authorization; only hashed for bucket keys.
 */
export async function getTrustedClientIpFingerprint(): Promise<string> {
  const headerStore = await headers();
  const forwarded = headerStore.get("x-forwarded-for");
  if (forwarded) {
    const first = forwarded.split(",")[0]?.trim();
    if (first) {
      return hashRateLimitSubject(`ip:${first}`);
    }
  }
  const realIp = headerStore.get("x-real-ip")?.trim();
  if (realIp) {
    return hashRateLimitSubject(`ip:${realIp}`);
  }
  return hashRateLimitSubject("ip:unknown");
}
