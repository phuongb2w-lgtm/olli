export const GUARDIAN_STATUSES = ["active", "inactive"] as const;
export type GuardianStatus = (typeof GUARDIAN_STATUSES)[number];

export const DEFAULT_GUARDIAN_STATUS: GuardianStatus = "active";

export const RELATIONSHIP_TYPES = ["mother", "father", "guardian", "other"] as const;
export type RelationshipType = (typeof RELATIONSHIP_TYPES)[number];

export const LINK_STATUSES = ["active", "ended"] as const;
export type LinkStatus = (typeof LINK_STATUSES)[number];

export const GUARDIAN_EMAIL_MAX_LENGTH = 254;
export const GUARDIAN_PHONE_MAX_LENGTH = 32;

export const MIN_GUARDIAN_SEARCH_LENGTH = 2;
