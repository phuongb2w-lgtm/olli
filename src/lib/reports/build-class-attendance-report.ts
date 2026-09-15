import type { SupabaseClient } from "@supabase/supabase-js";
import {
  isEnrollmentVisibleOnSessionRoster,
} from "@/lib/session-execution/roster-eligibility";
import {
  fetchAttendanceForSessions,
  fetchClassEnrollments,
  fetchClassReportContext,
  fetchOrganizationBranding,
  fetchSessionsInPeriod,
} from "./fetch-report-data";
import {
  computeAttendanceRate,
  emptyAttendanceCounts,
  incrementAttendanceCount,
} from "./metrics";
import { validateReportPeriod } from "./period";
import type { AttendanceLearnerRow, ClassAttendanceReport, ReportPeriod } from "./types";

const ATTENDANCE_OPPORTUNITY_STATUSES = new Set(["completed", "in_progress"]);

export type BuildClassAttendanceReportInput = {
  classId: string;
  startDate?: string;
  endDate?: string;
};

export async function buildClassAttendanceReport(
  supabase: SupabaseClient,
  input: BuildClassAttendanceReportInput,
): Promise<
  | { ok: true; report: ClassAttendanceReport }
  | { ok: false; error: "not_found" | "invalid_range" | "invalid_date" }
> {
  const context = await fetchClassReportContext(supabase, input.classId);
  if (!context) return { ok: false, error: "not_found" };

  const periodResult = validateReportPeriod({
    startDate: input.startDate,
    endDate: input.endDate,
    termStartDate: context.termStartDate,
    termEndDate: context.termEndDate,
  });
  if (!periodResult.ok) return { ok: false, error: periodResult.error };
  const period: ReportPeriod = periodResult.period;

  const branding = (await fetchOrganizationBranding(supabase)) ?? {
    name: "—",
    hasLogo: false,
  };

  const [enrollments, sessions] = await Promise.all([
    fetchClassEnrollments(supabase, input.classId, period),
    fetchSessionsInPeriod(supabase, input.classId, period),
  ]);

  const opportunitySessions = sessions.filter((s) =>
    ATTENDANCE_OPPORTUNITY_STATUSES.has(s.status),
  );
  const completedSessions = sessions.filter((s) => s.status === "completed");

  const attendanceRows = await fetchAttendanceForSessions(
    supabase,
    opportunitySessions.map((s) => s.id),
  );
  const attendanceByKey = new Map(
    attendanceRows.map((a) => [`${a.teachingSessionId}:${a.enrollmentId}`, a.status]),
  );

  const countsByEnrollment = new Map<string, ReturnType<typeof emptyAttendanceCounts>>();

  for (const session of opportunitySessions) {
    for (const enrollment of enrollments) {
      const rosterRow = {
        id: enrollment.id,
        studentId: enrollment.studentId,
        startDate: enrollment.startDate,
        endDate: enrollment.endDate,
        status: enrollment.status,
      };
      if (!isEnrollmentVisibleOnSessionRoster(rosterRow, session.occurrenceDate)) continue;

      const key = enrollment.id;
      const current = countsByEnrollment.get(key) ?? emptyAttendanceCounts();
      const status =
        attendanceByKey.get(`${session.id}:${enrollment.id}`) ?? null;
      countsByEnrollment.set(key, incrementAttendanceCount(current, status));
    }
  }

  const learners: AttendanceLearnerRow[] = enrollments
    .map((enrollment) => {
      const counts = countsByEnrollment.get(enrollment.id) ?? emptyAttendanceCounts();
      const recordedSessions =
        counts.presentCount +
        counts.absentCount +
        counts.lateCount +
        counts.excusedCount;
      return {
        enrollmentId: enrollment.id,
        studentId: enrollment.studentId,
        studentName: enrollment.studentName,
        studentCode: enrollment.studentCode,
        enrollmentStatus: enrollment.status,
        eligibleSessions: counts.eligibleSessions,
        presentCount: counts.presentCount,
        absentCount: counts.absentCount,
        lateCount: counts.lateCount,
        excusedCount: counts.excusedCount,
        notRecordedCount: counts.notRecordedCount,
        recordedSessions,
        attendanceRate: computeAttendanceRate(counts),
      };
    })
    .sort((a, b) => a.studentName.localeCompare(b.studentName));

  return {
    ok: true,
    report: {
      branding,
      context,
      period,
      generatedAt: new Date().toISOString(),
      sessionTotals: {
        materialized: sessions.length,
        completed: completedSessions.length,
        cancelled: sessions.filter((s) => s.status === "cancelled").length,
        inProgress: sessions.filter((s) => s.status === "in_progress").length,
        scheduled: sessions.filter((s) => s.status === "scheduled").length,
      },
      learners,
    },
  };
}
