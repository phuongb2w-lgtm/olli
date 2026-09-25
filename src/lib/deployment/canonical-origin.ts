/** Authoritative production browser origin (M8). Staging uses a different hostname in host/DNS config. */
export const OLLI_CANONICAL_PRODUCTION_ORIGIN = "https://olli.riuda.click" as const;

export function resolvePublicCanonicalAppOrigin(): string {
  return (
    process.env.NEXT_PUBLIC_OLLI_CANONICAL_APP_ORIGIN?.trim() ||
    OLLI_CANONICAL_PRODUCTION_ORIGIN
  );
}
