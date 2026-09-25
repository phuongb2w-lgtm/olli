/**
 * Mirrors src/lib/auth/safe-redirect.ts for Node smoke scripts.
 */

export function resolveSafeRedirectPath(input, fallback = "/") {
  if (input == null || typeof input !== "string") {
    return fallback;
  }

  const trimmed = input.trim();
  if (!trimmed.startsWith("/") || trimmed.startsWith("//")) {
    return fallback;
  }
  if (/^https?:\/\//i.test(trimmed)) {
    return fallback;
  }
  if (trimmed.includes("\\") || trimmed.includes("\0")) {
    return fallback;
  }

  return trimmed;
}
