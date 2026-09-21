/** Fixed server policy — not client-configurable. */
export const PROVISIONING_LEASE_MINUTES = 5;

/** Bounded Auth reconciliation scan (listUsers pagination). */
export const MAX_AUTH_RECONCILIATION_PAGES = 5;
export const AUTH_RECONCILIATION_PER_PAGE = 200;

export const PROVISIONING_METADATA_KEY = "olli_provisioning_request_id";

export const STAFF_CANONICAL_ROLES = [
  "accountant",
  "consultant",
  "academic_operations",
  "teacher",
] as const;

export type StaffCanonicalRole = (typeof STAFF_CANONICAL_ROLES)[number];
