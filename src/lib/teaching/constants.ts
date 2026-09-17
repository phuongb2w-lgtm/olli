export const WEEKDAY_CODES = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"] as const;
export type WeekdayCode = (typeof WEEKDAY_CODES)[number];

export const SCHEDULE_STATUSES = ["active", "ended"] as const;
export type ScheduleStatus = (typeof SCHEDULE_STATUSES)[number];

export const SESSION_STATUSES = ["scheduled", "in_progress", "completed", "cancelled"] as const;
export type SessionStatus = (typeof SESSION_STATUSES)[number];

export const TEACHER_ASSIGNMENT_STATUSES = ["active", "ended"] as const;
export type TeacherAssignmentStatus = (typeof TEACHER_ASSIGNMENT_STATUSES)[number];

export const TEACHER_ASSIGNMENT_ROLES = ["primary", "assistant"] as const;
export type TeacherAssignmentRole = (typeof TEACHER_ASSIGNMENT_ROLES)[number];

export const ROOM_STATUSES = ["active", "inactive"] as const;
export type RoomStatus = (typeof ROOM_STATUSES)[number];

export const UNAVAILABILITY_BLOCK_TYPES = ["recurring", "one_off"] as const;
export type UnavailabilityBlockType = (typeof UNAVAILABILITY_BLOCK_TYPES)[number];

export const UNAVAILABILITY_STATUSES = ["active", "ended"] as const;
export type UnavailabilityStatus = (typeof UNAVAILABILITY_STATUSES)[number];

export const TEACHER_ELIGIBLE_STATUSES = ["active"] as const;

/** Maximum inclusive generation span in days (application guard). */
export const MAX_GENERATION_RANGE_DAYS = 366;
