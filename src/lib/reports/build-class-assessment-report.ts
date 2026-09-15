import type { SupabaseClient } from "@supabase/supabase-js";
import { isEnrollmentVisibleForAssessmentResult } from "@/lib/assessments/eligibility";
import {
  fetchAssessmentsInPeriod,
  fetchAssessmentResults,
  fetchClassEnrollments,
  fetchClassReportContext,
  fetchOrganizationBranding,
} from "./fetch-report-data";
import { computeMeanPercentage, deriveScorePercentage } from "./metrics";
import { validateReportPeriod } from "./period";
import type { ClassAssessmentReport, ReportPeriod } from "./types";

export type BuildClassAssessmentReportInput = {
  classId: string;
  startDate?: string;
  endDate?: string;
  assessmentId?: string;
};

export async function buildClassAssessmentReport(
  supabase: SupabaseClient,
  input: BuildClassAssessmentReportInput,
): Promise<
  | { ok: true; report: ClassAssessmentReport }
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

  const [enrollments, assessments] = await Promise.all([
    fetchClassEnrollments(supabase, input.classId),
    fetchAssessmentsInPeriod(supabase, input.classId, period, input.assessmentId),
  ]);

  const results = await fetchAssessmentResults(
    supabase,
    assessments.map((a) => a.id),
  );
  const resultByKey = new Map(
    results.map((r) => [`${r.assessmentId}:${r.enrollmentId}`, r]),
  );

  const allPercentages: number[] = [];
  let scoredCount = 0;
  let withoutScoreCount = 0;

  const learners = enrollments
    .map((enrollment) => {
      const cells = assessments.map((assessment) => {
        const eligible = isEnrollmentVisibleForAssessmentResult(
          {
            startDate: enrollment.startDate,
            endDate: enrollment.endDate,
            status: enrollment.status,
          },
          assessment.assessedOn,
        );
        if (!eligible) {
          return {
            assessmentId: assessment.id,
            rawScore: null,
            maxScore: null,
            percentage: null,
            hasScore: false,
          };
        }

        const result = resultByKey.get(`${assessment.id}:${enrollment.id}`);
        if (!result) {
          withoutScoreCount += 1;
          return {
            assessmentId: assessment.id,
            rawScore: null,
            maxScore: assessment.maxScore,
            percentage: null,
            hasScore: false,
          };
        }

        const percentage = deriveScorePercentage(result.rawScore, result.maxScore);
        scoredCount += 1;
        if (percentage !== null) allPercentages.push(percentage);

        return {
          assessmentId: assessment.id,
          rawScore: result.rawScore,
          maxScore: result.maxScore,
          percentage,
          hasScore: true,
        };
      });

      const hasVisibleCell = cells.some(
        (c, i) =>
          isEnrollmentVisibleForAssessmentResult(
            {
              startDate: enrollment.startDate,
              endDate: enrollment.endDate,
              status: enrollment.status,
            },
            assessments[i]?.assessedOn ?? "",
          ),
      );
      if (!hasVisibleCell) return null;

      return {
        enrollmentId: enrollment.id,
        studentName: enrollment.studentName,
        studentCode: enrollment.studentCode,
        cells,
      };
    })
    .filter((row): row is NonNullable<typeof row> => row !== null)
    .sort((a, b) => a.studentName.localeCompare(b.studentName));

  return {
    ok: true,
    report: {
      branding,
      context,
      period,
      generatedAt: new Date().toISOString(),
      assessments: assessments.map((a) => ({
        id: a.id,
        title: a.title,
        assessedOn: a.assessedOn,
        maxScore: a.maxScore,
      })),
      learners,
      aggregates: {
        scoredCount,
        withoutScoreCount,
        meanPercentage: computeMeanPercentage(allPercentages),
        minPercentage:
          allPercentages.length > 0 ? Math.min(...allPercentages) : null,
        maxPercentage:
          allPercentages.length > 0 ? Math.max(...allPercentages) : null,
      },
    },
  };
}
