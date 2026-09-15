export const ATTENDANCE_STATUSES = ["present", "absent", "late", "excused"] as const;
export type AttendanceStatus = (typeof ATTENDANCE_STATUSES)[number];

export const SESSION_EXECUTION_STATUSES = [
  "scheduled",
  "in_progress",
  "completed",
  "cancelled",
] as const;
export type SessionExecutionStatus = (typeof SESSION_EXECUTION_STATUSES)[number];

export const OBSERVATION_RATINGS = ["low", "medium", "high"] as const;
export type ObservationRating = (typeof OBSERVATION_RATINGS)[number];

export const OBSERVATION_STATUSES = ["draft", "recorded", "void"] as const;
