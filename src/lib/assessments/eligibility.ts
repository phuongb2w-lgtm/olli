import type { EnrollmentStatus } from "@/lib/enrollments/constants";

export type EnrollmentEligibilityRow = {
  startDate: string;
  endDate: string | null;
  status: EnrollmentStatus;
};

/** Date interval eligibility — ignores current lifecycle status. */
export function isEnrollmentEligibleOnAssessmentDate(
  enrollment: Pick<EnrollmentEligibilityRow, "startDate" | "endDate">,
  assessmentDate: string,
): boolean {
  if (enrollment.startDate > assessmentDate) return false;
  if (enrollment.endDate && enrollment.endDate < assessmentDate) return false;
  return true;
}

/** Result roster visibility: date-eligible and not pending. */
export function isEnrollmentVisibleForAssessmentResult(
  enrollment: EnrollmentEligibilityRow,
  assessmentDate: string,
): boolean {
  if (!isEnrollmentEligibleOnAssessmentDate(enrollment, assessmentDate)) return false;
  if (enrollment.status === "pending") return false;
  return true;
}

export function derivePercentage(rawScore: number, maxScore: number): number | null {
  if (maxScore <= 0) return null;
  return Math.round((rawScore / maxScore) * 1000) / 10;
}
