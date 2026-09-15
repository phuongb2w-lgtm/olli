export const ENROLLMENT_STATUSES = [
  "pending",
  "active",
  "transferred",
  "withdrawn",
  "completed",
] as const;
export type EnrollmentStatus = (typeof ENROLLMENT_STATUSES)[number];

export const OPERATIONAL_ENROLLMENT_STATUSES = ["pending", "active"] as const;
export type OperationalEnrollmentStatus = (typeof OPERATIONAL_ENROLLMENT_STATUSES)[number];

export const CREATE_ENROLLMENT_STATUSES = ["pending", "active"] as const;
export type CreateEnrollmentStatus = (typeof CREATE_ENROLLMENT_STATUSES)[number];

export const TERMINAL_ENROLLMENT_STATUSES = ["transferred", "withdrawn", "completed"] as const;

export const ROSTER_STATUS_FILTERS = ["operational", "all", ...ENROLLMENT_STATUSES] as const;
export type RosterStatusFilter = (typeof ROSTER_STATUS_FILTERS)[number];

export const PAGE_SIZES = [25, 50, 100] as const;
export type PageSize = (typeof PAGE_SIZES)[number];

export const MIN_STUDENT_SEARCH_LENGTH = 2;
