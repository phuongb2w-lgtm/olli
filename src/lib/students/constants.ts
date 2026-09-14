export const STUDENT_STATUSES = [
  "prospect",
  "active",
  "inactive",
  "graduated",
  "withdrawn",
] as const;

export type StudentStatus = (typeof STUDENT_STATUSES)[number];

export const DEFAULT_STUDENT_STATUS: StudentStatus = "active";

export const STUDENT_CODE_MAX_LENGTH = 64;
