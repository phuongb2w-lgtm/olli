export const ALLOCATION_BASIS_CODES = [
  "equal",
  "active_enrollment_count",
  "delivered_session_count",
  "recognized_revenue",
] as const;

export const ALLOCATION_SOURCE_SCOPES = [
  "operating_overhead",
  "shared_personnel",
  "marketing_sales",
  "depreciation",
] as const;

export type AllocationBasisCode = (typeof ALLOCATION_BASIS_CODES)[number];
export type AllocationSourceScope = (typeof ALLOCATION_SOURCE_SCOPES)[number];
