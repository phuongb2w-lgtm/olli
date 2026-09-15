import type { SupabaseClient } from "@supabase/supabase-js";
import { isEnrollmentVisibleForAssessmentResult } from "@/lib/assessments/eligibility";
import { buildClassAttendanceReport } from "./build-class-attendance-report";
import {
  fetchAssessmentsInPeriod,
  fetchAssessmentResults,
  fetchObservationsForSessions,
  fetchOrganizationBranding,
  fetchSessionsInPeriod,
  fetchStudentEnrollments,
} from "./fetch-report-data";
import { computeMeanPercentage, deriveScorePercentage } from "./metrics";
import { enrollmentOverlapsPeriod, validateReportPeriod } from "./period";
import type { AttendanceLearnerRow, ReportPeriod, StudentProgressReport } from "./types";

export type BuildStudentProgressReportInput = {
  studentId: string;
  enrollmentId?: string;
  startDate?: string;
  endDate?: string;
  includeObservations?: boolean;
};

export async function buildStudentProgressReport(
  supabase: SupabaseClient,
  input: BuildStudentProgressReportInput,
): Promise<
  | { ok: true; report: StudentProgressReport }
  | { ok: false; error: "not_found" | "invalid_range" | "invalid_date" }
> {
  const { data: student, error: studentError } = await supabase
    .from("student")
    .select("id, given_name, family_name, student_code")
    .eq("id", input.studentId)
    .maybeSingle();
  if (studentError || !student) return { ok: false, error: "not_found" };

  const studentName = `${student.family_name} ${student.given_name}`.trim();
  const enrollments = await fetchStudentEnrollments(supabase, input.studentId);
  if (enrollments.length === 0) {
    const branding = (await fetchOrganizationBranding(supabase)) ?? {
      name: "—",
      hasLogo: false,
    };
    const today = new Date().toISOString().slice(0, 10);
    return {
      ok: true,
      report: {
        branding,
        studentId: input.studentId,
        studentName,
        studentCode: student.student_code,
        period: { startDate: today, endDate: today },
        generatedAt: new Date().toISOString(),
        includesObservations: false,
        enrollmentScope: null,
        attendance: null,
        assessments: [],
        averagePercentage: null,
        observations: null,
      },
    };
  }

  const scopedEnrollment = input.enrollmentId
    ? enrollments.find((e) => e.id === input.enrollmentId)
    : enrollments[0];
  if (input.enrollmentId && !scopedEnrollment) {
    return { ok: false, error: "not_found" };
  }

  const periodResult = validateReportPeriod({
    startDate: input.startDate,
    endDate: input.endDate,
    termStartDate: scopedEnrollment?.startDate,
    termEndDate: scopedEnrollment?.endDate,
  });
  if (!periodResult.ok) return { ok: false, error: periodResult.error };
  const period: ReportPeriod = periodResult.period;

  const branding = (await fetchOrganizationBranding(supabase)) ?? {
    name: "—",
    hasLogo: false,
  };

  let attendance: AttendanceLearnerRow | null = null;
  let assessments: StudentProgressReport["assessments"] = [];
  let observations: StudentProgressReport["observations"] = null;

  if (scopedEnrollment) {
    const classReport = await buildClassAttendanceReport(supabase, {
      classId: scopedEnrollment.classId,
      startDate: period.startDate,
      endDate: period.endDate,
    });
    if (classReport.ok) {
      attendance =
        classReport.report.learners.find((l) => l.enrollmentId === scopedEnrollment.id) ??
        null;
    }

    const assessmentRows = await fetchAssessmentsInPeriod(
      supabase,
      scopedEnrollment.classId,
      period,
    );
    const results = await fetchAssessmentResults(
      supabase,
      assessmentRows.map((a) => a.id),
    );
    const resultByAssessment = new Map(
      results
        .filter((r) => r.enrollmentId === scopedEnrollment.id)
        .map((r) => [r.assessmentId, r]),
    );

    assessments = assessmentRows
      .filter((a) =>
        isEnrollmentVisibleForAssessmentResult(
          {
            startDate: scopedEnrollment.startDate,
            endDate: scopedEnrollment.endDate,
            status: scopedEnrollment.status,
          },
          a.assessedOn,
        ),
      )
      .map((a) => {
        const result = resultByAssessment.get(a.id);
        return {
          assessmentId: a.id,
          title: a.title,
          assessedOn: a.assessedOn,
          rawScore: result?.rawScore ?? null,
          maxScore: result ? result.maxScore : a.maxScore,
          percentage:
            result !== undefined
              ? deriveScorePercentage(result.rawScore, result.maxScore)
              : null,
        };
      });

    if (input.includeObservations) {
      const sessions = await fetchSessionsInPeriod(
        supabase,
        scopedEnrollment.classId,
        period,
      );
      const completedSessions = sessions.filter((s) => s.status === "completed");
      const obsRows = await fetchObservationsForSessions(supabase, completedSessions);
      observations = obsRows
        .filter((o) => o.enrollmentId === scopedEnrollment.id)
        .map((o) => ({
          sessionDate: o.sessionDate,
          className: scopedEnrollment.className,
          ratings: o.ratings,
          comment: o.comment,
        }))
        .sort((a, b) => b.sessionDate.localeCompare(a.sessionDate));
    }
  } else {
    const allAssessments: StudentProgressReport["assessments"] = [];
    for (const enr of enrollments) {
      if (!enrollmentOverlapsPeriod(enr.startDate, enr.endDate, period)) continue;
      const rows = await fetchAssessmentsInPeriod(supabase, enr.classId, period);
      const results = await fetchAssessmentResults(
        supabase,
        rows.map((a) => a.id),
      );
      const resultByAssessment = new Map(
        results.filter((r) => r.enrollmentId === enr.id).map((r) => [r.assessmentId, r]),
      );
      for (const a of rows) {
        if (
          !isEnrollmentVisibleForAssessmentResult(
            { startDate: enr.startDate, endDate: enr.endDate, status: enr.status },
            a.assessedOn,
          )
        ) {
          continue;
        }
        const result = resultByAssessment.get(a.id);
        allAssessments.push({
          assessmentId: a.id,
          title: a.title,
          assessedOn: a.assessedOn,
          rawScore: result?.rawScore ?? null,
          maxScore: result ? result.maxScore : a.maxScore,
          percentage:
            result !== undefined
              ? deriveScorePercentage(result.rawScore, result.maxScore)
              : null,
        });
      }
    }
    assessments = allAssessments.sort((a, b) => b.assessedOn.localeCompare(a.assessedOn));
  }

  const percentages = assessments
    .map((a) => a.percentage)
    .filter((p): p is number => p !== null);

  return {
    ok: true,
    report: {
      branding,
      studentId: input.studentId,
      studentName,
      studentCode: student.student_code,
      period,
      generatedAt: new Date().toISOString(),
      includesObservations: Boolean(input.includeObservations),
      enrollmentScope: scopedEnrollment
        ? {
            enrollmentId: scopedEnrollment.id,
            classId: scopedEnrollment.classId,
            className: scopedEnrollment.className,
            courseCode: scopedEnrollment.courseCode,
            enrollmentStatus: scopedEnrollment.status,
            startDate: scopedEnrollment.startDate,
            endDate: scopedEnrollment.endDate,
          }
        : null,
      attendance,
      assessments,
      averagePercentage: computeMeanPercentage(percentages),
      observations,
    },
  };
}
