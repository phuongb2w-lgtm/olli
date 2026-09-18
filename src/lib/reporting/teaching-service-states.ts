/**
 * M5 teaching service-state semantics.
 * Materialized teaching_session rows are NOT automatically delivered service.
 */

export const TEACHING_SESSION_STATUS = {
  scheduled: "scheduled",
  inProgress: "in_progress",
  completed: "completed",
  cancelled: "cancelled",
} as const;

export type TeachingSessionStatus =
  (typeof TEACHING_SESSION_STATUS)[keyof typeof TEACHING_SESSION_STATUS];

/** Schedule occurrence not yet materialized as teaching_session. */
export type ProjectedOccurrence = {
  kind: "projected";
};

/** Concrete teaching_session row exists (any non-cancelled lifecycle state). */
export type MaterializedSession = {
  kind: "materialized";
  status: TeachingSessionStatus;
};

/** Canonical delivered evidence: session execution sets status = completed (M1). */
export function isDeliveredTeachingSession(status: string): boolean {
  return status === TEACHING_SESSION_STATUS.completed;
}

export function isCancelledTeachingSession(status: string): boolean {
  return status === TEACHING_SESSION_STATUS.cancelled;
}

/** Materialized but not yet delivered (scheduled or in_progress). */
export function isMaterializedNonDeliveredSession(status: string): boolean {
  return (
    status === TEACHING_SESSION_STATUS.scheduled ||
    status === TEACHING_SESSION_STATUS.inProgress
  );
}

/**
 * M5 KPI `teaching_ops.delivered_sessions` is reserved until read models use
 * isDeliveredTeachingSession — never count mere materialized existence.
 */
export const DELIVERED_SESSION_EVIDENCE =
  "teaching_session.status = completed" as const;
