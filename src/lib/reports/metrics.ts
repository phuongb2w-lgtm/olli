import type { AttendanceStatus } from "@/lib/session-execution/constants";

export type AttendanceCounts = {
  presentCount: number;
  absentCount: number;
  lateCount: number;
  excusedCount: number;
  notRecordedCount: number;
  eligibleSessions: number;
};

export function emptyAttendanceCounts(): AttendanceCounts {
  return {
    presentCount: 0,
    absentCount: 0,
    lateCount: 0,
    excusedCount: 0,
    notRecordedCount: 0,
    eligibleSessions: 0,
  };
}

export function incrementAttendanceCount(
  counts: AttendanceCounts,
  status: AttendanceStatus | null,
): AttendanceCounts {
  const next = { ...counts, eligibleSessions: counts.eligibleSessions + 1 };
  if (status === "present") next.presentCount += 1;
  else if (status === "absent") next.absentCount += 1;
  else if (status === "late") next.lateCount += 1;
  else if (status === "excused") next.excusedCount += 1;
  else next.notRecordedCount += 1;
  return next;
}

/** Recorded eligible sessions exclude not-recorded. Rate = (present + late) / recorded. */
export function computeAttendanceRate(counts: AttendanceCounts): number | null {
  const recorded =
    counts.presentCount +
    counts.absentCount +
    counts.lateCount +
    counts.excusedCount;
  if (recorded === 0) return null;
  return roundPercentage(((counts.presentCount + counts.lateCount) / recorded) * 100);
}

export function deriveScorePercentage(rawScore: number, maxScore: number): number | null {
  if (maxScore <= 0) return null;
  return roundPercentage((rawScore / maxScore) * 100);
}

export function roundPercentage(value: number): number {
  return Math.round(value * 10) / 10;
}

export function computeMeanPercentage(values: number[]): number | null {
  if (values.length === 0) return null;
  const sum = values.reduce((a, b) => a + b, 0);
  return roundPercentage(sum / values.length);
}
