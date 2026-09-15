export const COURSE_STATUSES = ["active", "inactive", "archived"] as const;
export type CourseStatus = (typeof COURSE_STATUSES)[number];
export const DEFAULT_COURSE_STATUS: CourseStatus = "active";

export const CLASS_STATUSES = ["planned", "trial", "active", "closed"] as const;
export type ClassStatus = (typeof CLASS_STATUSES)[number];
export const DEFAULT_CLASS_STATUS: ClassStatus = "planned";

export const CLASS_LIFECYCLE_CONFIRM_STATUSES: ClassStatus[] = ["active", "closed"];

export const PAGE_SIZES = [25, 50, 100] as const;
export type PageSize = (typeof PAGE_SIZES)[number];

export const COURSE_CODE_MAX_LENGTH = 32;
export const CLASS_NAME_MAX_LENGTH = 128;
