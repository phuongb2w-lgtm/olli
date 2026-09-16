export const LEAD_STATUSES = [
  "new",
  "contacted",
  "qualified",
  "trial_scheduled",
  "trial_completed",
  "converted",
  "lost",
  "reactivated",
] as const;

export type LeadStatus = (typeof LEAD_STATUSES)[number];

export const LEAD_LIST_STATUSES = [
  "all",
  ...LEAD_STATUSES,
] as const;

export type LeadListStatus = (typeof LEAD_LIST_STATUSES)[number];

export const LEAD_ACTIVITY_TYPES = [
  "call",
  "message",
  "consultation",
  "note",
  "appointment",
  "status_change",
  "follow_up",
  "other",
] as const;

export type LeadActivityType = (typeof LEAD_ACTIVITY_TYPES)[number];

export const LEAD_USER_ACTIVITY_TYPES = [
  "call",
  "message",
  "consultation",
  "note",
  "appointment",
  "other",
] as const;

export type LeadUserActivityType = (typeof LEAD_USER_ACTIVITY_TYPES)[number];

export const LEAD_FOLLOW_UP_STATUSES = [
  "pending",
  "completed",
  "cancelled",
] as const;

export type LeadFollowUpStatus = (typeof LEAD_FOLLOW_UP_STATUSES)[number];

export const DEFAULT_LEAD_PAGE_SIZE = 25;

/** Terminal pipeline states excluded from active workload counts. */
export const LEAD_INACTIVE_STATUSES = ["lost", "converted"] as const;

export type LeadInactiveStatus = (typeof LEAD_INACTIVE_STATUSES)[number];

export const LEAD_OWNERSHIP_FILTERS = [
  "all",
  "me",
  "unassigned",
  "user",
] as const;

export type LeadOwnershipFilter = (typeof LEAD_OWNERSHIP_FILTERS)[number];

export const LEAD_TRIAL_STATUSES = [
  "scheduled",
  "completed",
  "cancelled",
  "no_show",
] as const;

export type LeadTrialStatus = (typeof LEAD_TRIAL_STATUSES)[number];

export const LEAD_TRIAL_EVENT_TYPES = [
  "scheduled",
  "rescheduled",
  "completed",
  "cancelled",
  "no_show",
] as const;

export type LeadTrialEventType = (typeof LEAD_TRIAL_EVENT_TYPES)[number];

export const LEAD_TRIAL_FILTERS = ["all", "scheduled"] as const;

export type LeadTrialFilter = (typeof LEAD_TRIAL_FILTERS)[number];

export const LEAD_TRANSITION_TARGETS: Partial<Record<LeadStatus, LeadStatus[]>> = {
  new: ["contacted", "qualified", "trial_scheduled", "lost"],
  contacted: ["qualified", "trial_scheduled", "lost"],
  qualified: ["trial_scheduled", "trial_completed", "lost"],
  trial_scheduled: ["trial_completed", "lost", "qualified"],
  trial_completed: ["lost", "qualified"],
  lost: ["contacted", "qualified", "new"],
  reactivated: ["contacted", "qualified", "new"],
};
