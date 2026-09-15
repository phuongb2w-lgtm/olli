import Link from "next/link";
import { notFound } from "next/navigation";
import { getLocale, getTranslations } from "next-intl/server";
import { ClassEndOfCourseReportView } from "@/components/reports/class-end-of-course-report-view";
import { ReportPeriodForm } from "@/components/reports/report-period-form";
import { ReportPrintButton } from "@/components/reports/report-print-button";
import type { Locale } from "@/i18n/config";
import { buildClassEndOfCourseReport } from "@/lib/reports/build-class-end-of-course-report";
import { buildReportLabels } from "@/lib/reports/report-labels";
import { can } from "@/lib/permissions/can";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

type Props = {
  params: Promise<{ id: string }>;
  searchParams: Promise<Record<string, string | string[] | undefined>>;
};

export default async function ClassEndOfCourseReportPage({ params, searchParams }: Props) {
  const t = await getTranslations("reports");
  const tEnroll = await getTranslations("status.enrollment");
  const locale = (await getLocale()) as Locale;
  const { id: classId } = await params;
  const rawParams = await searchParams;

  const [hasAttendance, hasAssessment, hasObservation] = await Promise.all([
    can("attendance.read"),
    can("assessment.read"),
    can("observation.read"),
  ]);

  if (!hasAttendance && !hasAssessment) {
    return (
      <div className="space-y-4">
        <h1 className="text-xl font-semibold">{t("endOfCourseReport")}</h1>
        <section className="rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-600">
          <p>{t("deniedProgress")}</p>
        </section>
      </div>
    );
  }

  const startDate = typeof rawParams.startDate === "string" ? rawParams.startDate : undefined;
  const endDate = typeof rawParams.endDate === "string" ? rawParams.endDate : undefined;

  const supabase = await createClient();
  const result = await buildClassEndOfCourseReport(supabase, {
    classId,
    startDate,
    endDate,
    includeObservations: hasObservation,
  });
  if (!result.ok) {
    if (result.error === "not_found") notFound();
    return (
      <div className="space-y-4">
        <h1 className="text-xl font-semibold">{t("endOfCourseReport")}</h1>
        <p className="text-sm text-red-700">{t("invalidPeriod")}</p>
      </div>
    );
  }

  let report = result.report;
  if (!hasAttendance) {
    report = {
      ...report,
      attendanceReport: { ...report.attendanceReport, learners: [] },
      attendance: { learnersWithData: 0, averageAttendanceRate: null, totalNotRecorded: 0 },
    };
  }
  if (!hasAssessment) {
    report = {
      ...report,
      assessmentReport: {
        ...report.assessmentReport,
        assessments: [],
        learners: [],
        aggregates: {
          scoredCount: 0,
          withoutScoreCount: 0,
          meanPercentage: null,
          minPercentage: null,
          maxPercentage: null,
        },
      },
      assessments: { count: 0, resultsRecorded: 0, meanPercentage: null },
    };
  }

  const labels = buildReportLabels(t, { title: t("endOfCourseReport") });
  const attendanceLabels = buildReportLabels(t, { title: t("attendanceReport") });
  const assessmentLabels = buildReportLabels(t, { title: t("assessmentReport") });
  const enrollmentStatusLabels = {
    pending: tEnroll("pending"),
    active: tEnroll("active"),
    completed: tEnroll("completed"),
    transferred: tEnroll("transferred"),
    withdrawn: tEnroll("withdrawn"),
  };

  return (
    <div className="space-y-6">
      <div className="report-no-print flex flex-wrap items-center justify-between gap-3">
        <Link href={`/classes/${classId}/reports`} className="text-sm text-slate-600 underline">
          {t("backToReports")}
        </Link>
        <ReportPrintButton label={t("print")} />
      </div>
      <ReportPeriodForm
        startDate={report.period.startDate}
        endDate={report.period.endDate}
        fromLabel={t("from")}
        toLabel={t("to")}
        periodLabel={t("reportingPeriod")}
        submitLabel={t("applyPeriod")}
      />
      <ClassEndOfCourseReportView
        report={report}
        locale={locale}
        labels={labels}
        attendanceLabels={attendanceLabels}
        assessmentLabels={assessmentLabels}
        enrollmentStatusLabels={enrollmentStatusLabels}
      />
    </div>
  );
}
