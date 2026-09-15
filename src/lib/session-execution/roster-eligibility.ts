import type { EnrollmentStatus } from "@/lib/enrollments/constants";

export type EnrollmentRosterRow = {
  id: string;
  studentId: string;
  startDate: string;
  endDate: string | null;
  status: EnrollmentStatus;
};

/** Date interval eligibility — ignores current lifecycle status. */
export function isEnrollmentEligibleOnSessionDate(
  enrollment: Pick<EnrollmentRosterRow, "startDate" | "endDate">,
  sessionDate: string,
): boolean {
  if (enrollment.startDate > sessionDate) return false;
  if (enrollment.endDate && enrollment.endDate < sessionDate) return false;
  return true;
}

/** Roster visibility: eligible on date and not pending (not yet participating). */
export function isEnrollmentVisibleOnSessionRoster(
  enrollment: EnrollmentRosterRow,
  sessionDate: string,
): boolean {
  if (!isEnrollmentEligibleOnSessionDate(enrollment, sessionDate)) return false;
  if (enrollment.status === "pending") return false;
  return true;
}

/** Operational attendance marking: active participation on session date. */
export function isEnrollmentOperationalForAttendance(
  enrollment: EnrollmentRosterRow,
  sessionDate: string,
): boolean {
  if (!isEnrollmentEligibleOnSessionDate(enrollment, sessionDate)) return false;
  return enrollment.status === "active";
}

export function resolveSessionOccurrenceDate(session: {
  occurrenceDate: string | null;
  scheduledStartAt: string;
}): string {
  if (session.occurrenceDate) return session.occurrenceDate;
  return session.scheduledStartAt.slice(0, 10);
}
