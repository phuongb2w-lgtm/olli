/**
 * Parse supabase db diff CLI output (text + trailing JSON blob).
 * Used by production drift check and local contract tests.
 */

/** @returns {string} SQL diff body, or "" when no effective schema change. */
export function extractDiffSql(stdout) {
  const raw = (stdout ?? "").trim();
  if (!raw) return "";
  if (/no schema changes found/i.test(raw)) return "";

  const jsonLine = raw
    .split("\n")
    .map((line) => line.trim())
    .find((line) => line.startsWith("{") && line.includes('"diff"'));
  if (jsonLine) {
    try {
      const parsed = JSON.parse(jsonLine);
      return String(parsed.diff ?? "").trim();
    } catch {
      // fall through to text heuristics
    }
  }

  const withoutBanner = raw
    .split("\n")
    .filter(
      (line) =>
        !/^Found drop statements in schema diff/i.test(line) &&
        !/^Finished supabase db diff/i.test(line) &&
        !/^Diffing schemas/i.test(line) &&
        !/^Applying migration/i.test(line) &&
        !/^Creating shadow database/i.test(line) &&
        !/^\{"diff"/.test(line.trim()) &&
        !/^A new version of Supabase CLI/i.test(line),
    )
    .join("\n")
    .trim();

  return withoutBanner;
}

/** @returns {boolean} */
export function isEffectiveDiffEmpty(diffSql) {
  const trimmed = (diffSql ?? "").trim();
  if (!trimmed) return true;
  if (/^no schema changes found/i.test(trimmed)) return true;
  return false;
}
