import Link from "next/link";
import { notFound } from "next/navigation";
import { getLocale, getTranslations } from "next-intl/server";
import { ReportPrintButton } from "@/components/reports/report-print-button";
import { StudentEnrollmentScopeForm } from "@/components/reports/student-enrollment-scope-form";
import { StudentProgressReportView } from "@/components/reports/student-progress-report-view";
import type { Locale } from "@/i18n/config";
import { buildStudentProgressReport } from "@/lib/reports/build-student-progress-report";
import { fetchStudentEnrollments } from "@/lib/reports/fetch-report-data";
import { buildReportLabels } from "@/lib/reports/report-labels";
import { can } from "@/lib/permissions/can";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

type Props = {
  params: Promise<{ id: string }>;
  searchParams: Promise<Record<string, string | string[] | undefined>>;
};

export default async function StudentProgressReportPage({ params, searchParams }: Props) {
  const t = await getTranslations("reports");
  const tEnroll = await getTranslations("status.enrollment");
  const tObsInd = await getTranslations("observationIndicators");
  const tObsRat = await getTranslations("observationRatings");
  const locale = (await getLocale()) as Locale;
  const { id: studentId } = await params;
  const rawParams = await searchParams;

  const [hasStudentRead, hasAttendance, hasAssessment, hasObservation, hasEnrollment] =
    await Promise.all([
      can("student.read"),
      can("attendance.read"),
      can("assessment.read"),
      can("observation.read"),
      can("enrollment.read"),
    ]);

  if (!hasStudentRead && !hasEnrollment && !hasAssessment && !hasAttendance) {
    return (
      <div className="space-y-4">
        <h1 className="text-xl font-semibold">{t("learnerProgressReport")}</h1>
        <section className="rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-600">
          <p>{t("deniedProgress")}</p>
        </section>
      </div>
    );
  }

  const enrollmentId =
    typeof rawParams.enrollmentId === "string" ? rawParams.enrollmentId : undefined;
  const startDate = typeof rawParams.startDate === "string" ? rawParams.startDate : undefined;
  const endDate = typeof rawParams.endDate === "string" ? rawParams.endDate : undefined;

  const supabase = await createClient();
  const result = await buildStudentProgressReport(supabase, {
    studentId,
    enrollmentId,
    startDate,
    endDate,
    includeObservations: hasObservation,
  });
  if (!result.ok) {
    if (result.error === "not_found") notFound();
    return (
      <div className="space-y-4">
        <h1 className="text-xl font-semibold">{t("learnerProgressReport")}</h1>
        <p className="text-sm text-red-700">{t("invalidPeriod")}</p>
      </div>
    );
  }

  let report = result.report;
  if (!hasAttendance) report = { ...report, attendance: null };
  if (!hasAssessment) {
    report = { ...report, assessments: [], averagePercentage: null };
  }
  if (!hasObservation) {
    report = { ...report, includesObservations: false, observations: null };
  }

  const enrollments = await fetchStudentEnrollments(supabase, studentId);
  const enrollmentOptions = enrollments.map((enr) => ({
    id: enr.id,
    label: `${enr.className} (${enr.startDate}${enr.endDate ? ` — ${enr.endDate}` : ""})`,
  }));

  const labels = buildReportLabels(t, { title: t("learnerProgressReport") });
  const enrollmentStatusLabels = {
    pending: tEnroll("pending"),
    active: tEnroll("active"),
    completed: tEnroll("completed"),
    transferred: tEnroll("transferred"),
    withdrawn: tEnroll("withdrawn"),
  };
  const observationIndicatorLabels = {
    concentration: tObsInd("concentration"),
    engagement: tObsInd("engagement"),
    participation: tObsInd("participation"),
  };
  const observationRatingLabels = {
    low: tObsRat("low"),
    medium: tObsRat("medium"),
    high: tObsRat("high"),
  };

  return (
    <div className="space-y-6">
      <div className="report-no-print flex flex-wrap items-center justify-between gap-3">
        <Link href={`/students/${studentId}/enrollments`} className="text-sm text-slate-600 underline">
          {t("backToEnrollments")}
        </Link>
        <ReportPrintButton label={t("print")} />
      </div>
      <StudentEnrollmentScopeForm
        enrollments={enrollmentOptions}
        selectedEnrollmentId={enrollmentId}
        allHistoryLabel={t("allHistory")}
        selectEnrollmentLabel={t("selectEnrollment")}
        submitLabel={t("applyPeriod")}
        startDate={report.period.startDate}
        endDate={report.period.endDate}
        fromLabel={t("from")}
        toLabel={t("to")}
      />
      <StudentProgressReportView
        report={report}
        locale={locale}
        labels={labels}
        enrollmentStatusLabels={enrollmentStatusLabels}
        observationIndicatorLabels={observationIndicatorLabels}
        observationRatingLabels={observationRatingLabels}
      />
    </div>
  );
}
