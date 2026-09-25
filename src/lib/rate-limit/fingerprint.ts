import "server-only";

import { createHash } from "node:crypto";

const PREFIX = "v1";

export function hashRateLimitSubject(value: string): string {
  return createHash("sha256").update(value, "utf8").digest("hex").slice(0, 40);
}

export function buildRateLimitBucketKey(actionId: string, subject: string): string {
  return `${PREFIX}:${actionId}:${subject}`;
}

export function normalizeEmailForRateLimit(email: string): string {
  return email.trim().toLowerCase();
}
