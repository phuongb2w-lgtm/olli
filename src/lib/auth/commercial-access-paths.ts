import type { IdentityState } from "@/types/app-user";

export const SUBSCRIPTION_STATUS_PATH = "/subscription-status";
export const COMMERCIAL_ACCESS_PATH = "/commercial-access";

export function commercialRestrictedPath(
  identity: Extract<IdentityState, { kind: "commercially_restricted" }>,
): string {
  return identity.isPrimaryOwner ? SUBSCRIPTION_STATUS_PATH : COMMERCIAL_ACCESS_PATH;
}
