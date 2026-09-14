import { escapeIlike } from "@/lib/students/escape-ilike";

/**
 * Build ilike patterns for PostgREST filters.
 * Unicode characters in filter values are not reliably matched via ilike; ASCII-prefix
 * patterns (e.g. "Ph" → "Phương") provide V1 best-effort Vietnamese search.
 */
export function buildSearchPatterns(term: string): string[] {
  const trimmed = term.trim();
  if (!trimmed) {
    return [];
  }

  const patterns = new Set<string>();

  for (const normalized of [trimmed.normalize("NFC"), trimmed.normalize("NFD")]) {
    if (normalized.length >= 2 && isAsciiOnly(normalized)) {
      patterns.add(`*${escapeIlike(normalized)}*`);
    }
  }

  for (const token of trimmed.split(/\s+/)) {
    const asciiPrefix = token.match(/^[A-Za-z0-9]+/)?.[0] ?? "";
    if (asciiPrefix.length >= 2) {
      patterns.add(`*${escapeIlike(asciiPrefix)}*`);
    }
  }

  return [...patterns];
}

function isAsciiOnly(value: string): boolean {
  return /^[\x00-\x7F]+$/.test(value);
}
