export const RECOGNITION_BASIS_CODES = [
  "per_lesson",
  "stage",
  "stage_checkpoint",
  "deferred",
] as const;

export type RecognitionBasisCode = (typeof RECOGNITION_BASIS_CODES)[number];

export const ELIGIBLE_ATTENDANCE_STATUSES = ["present", "late"] as const;

export type EligibleAttendanceStatus = (typeof ELIGIBLE_ATTENDANCE_STATUSES)[number];

export const RECOGNITION_EVENT_STATUSES = ["posted", "void"] as const;

export type RecognitionEventStatus = (typeof RECOGNITION_EVENT_STATUSES)[number];
