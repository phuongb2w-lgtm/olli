/**
 * Same-origin path redirects only — rejects external and protocol-relative targets.
 */
export function resolveSafeRedirectPath(
  input: string | null | undefined,
  fallback = "/",
): string {
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
