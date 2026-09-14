/** Canonical display: family_name + space + given_name (same order in vi and en). */
export function formatPersonName(familyName: string, givenName: string): string {
  return `${familyName} ${givenName}`.trim();
}
