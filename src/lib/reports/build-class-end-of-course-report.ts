import type { SupabaseClient } from "@supabase/supabase-js";
import { buildClassAssessmentReport } from "./build-class-assessment-report";
import { buildClassAttendanceReport } from "./build-class-attendance-report";
import {
  fetchClassEnrollments,
  fetchObservationsForSessions,
  fetchSessionsInPeriod,
} from "./fetch-report-data";
import { computeMeanPercentage } from "./metrics";
import { validateReportPeriod } from "./period";
import type { ClassEndOfCourseReport, ObservationSummaryRow } from "./types";

export type BuildClassEndOfCourseReportInput = {
  classId: string;
  startDate?: string;
  endDate?: string;
  includeObservations?: boolean;
};

function aggregateObservations(
  observations: Awaited<ReturnType<typeof fetchObservationsForSessions>>,
): { ratingDistribution: ObservationSummaryRow[]; commentCount: number; sessionCount: number } {
  const distribution = new Map<string, number>();
  const sessionIds = new Set<string>();
  let commentCount = 0;

  for (const obs of observations) {
    sessionIds.add(obs.teachingSessionId);
    if (obs.comment?.trim()) commentCount += 1;
    for (const [indicatorCode, ratingCode] of Object.entries(obs.ratings)) {
      const key = `${indicatorCode}:${ratingCode}`;
      distribution.set(key, (distribution.get(key) ?? 0) + 1);
    }
  }

  const ratingDistribution: ObservationSummaryRow[] = [...distribution.entries()]
    .map(([key, count]) => {
      const [indicatorCode, ratingCode] = key.split(":");
      return { indicatorCode, ratingCode, count };
    })
    .sort((a, b) => a.indicatorCode.localeCompare(b.indicatorCode));

  return {
    ratingDistribution,
    commentCount,
    sessionCount: sessionIds.size,
  };
}

export async function buildClassEndOfCourseReport(
  supabase: SupabaseClient,
  input: BuildClassEndOfCourseReportInput,
): Promise<
  | { ok: true; report: ClassEndOfCourseReport }
  | { ok: false; error: "not_found" | "invalid_range" | "invalid_date" }
> {
  const [attendanceResult, assessmentResult] = await Promise.all([
    buildClassAttendanceReport(supabase, input),
    buildClassAssessmentReport(supabase, input),
  ]);

  if (!attendanceResult.ok) return attendanceResult;
  if (!assessmentResult.ok) return assessmentResult;

  const { report: attendanceReport } = attendanceResult;
  const { report: assessmentReport } = assessmentResult;
  const periodResult = validateReportPeriod({
    startDate: input.startDate,
    endDate: input.endDate,
    termStartDate: attendanceReport.context.termStartDate,
    termEndDate: attendanceReport.context.termEndDate,
  });
  if (!periodResult.ok) return { ok: false, error: periodResult.error };

  const enrollments = await fetchClassEnrollments(
    supabase,
    input.classId,
    periodResult.period,
  );
  const byStatus: Record<string, number> = {};
  for (const enr of enrollments) {
    byStatus[enr.status] = (byStatus[enr.status] ?? 0) + 1;
  }

  const rates = attendanceReport.learners
    .map((l) => l.attendanceRate)
    .filter((r): r is number => r !== null);

  let observations: ClassEndOfCourseReport["observations"] = null;
  if (input.includeObservations) {
    const sessions = await fetchSessionsInPeriod(supabase, input.classId, periodResult.period);
    const completedSessions = sessions.filter((s) => s.status === "completed");
    const obsRows = await fetchObservationsForSessions(supabase, completedSessions);
    observations = aggregateObservations(obsRows);
  }

  return {
    ok: true,
    report: {
      branding: attendanceReport.branding,
      context: attendanceReport.context,
      period: attendanceReport.period,
      generatedAt: attendanceReport.generatedAt,
      includesObservations: Boolean(input.includeObservations),
      sessions: {
        completed: attendanceReport.sessionTotals.completed,
        cancelled: attendanceReport.sessionTotals.cancelled,
        total: attendanceReport.sessionTotals.materialized,
      },
      enrollments: {
        total: enrollments.length,
        byStatus,
      },
      attendance: {
        learnersWithData: attendanceReport.learners.filter((l) => l.recordedSessions > 0).length,
        averageAttendanceRate: computeMeanPercentage(rates),
        totalNotRecorded: attendanceReport.learners.reduce(
          (sum, l) => sum + l.notRecordedCount,
          0,
        ),
      },
      assessments: {
        count: assessmentReport.assessments.length,
        resultsRecorded: assessmentReport.aggregates.scoredCount,
        meanPercentage: assessmentReport.aggregates.meanPercentage,
      },
      observations,
      attendanceReport,
      assessmentReport,
    },
  };
}
