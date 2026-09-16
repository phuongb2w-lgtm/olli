export function formatPersonName(givenName: string, familyName: string): string {
  return `${familyName} ${givenName}`.trim();
}
