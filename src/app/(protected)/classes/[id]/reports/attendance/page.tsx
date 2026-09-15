import Link from "next/link";
import { notFound } from "next/navigation";
import { getLocale, getTranslations } from "next-intl/server";
import { ClassAttendanceReportView } from "@/components/reports/class-attendance-report-view";
import { ReportPeriodForm } from "@/components/reports/report-period-form";
import { ReportPrintButton } from "@/components/reports/report-print-button";
import type { Locale } from "@/i18n/config";
import { buildClassAttendanceReport } from "@/lib/reports/build-class-attendance-report";
import { buildReportLabels } from "@/lib/reports/report-labels";
import { can } from "@/lib/permissions/can";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

type Props = {
  params: Promise<{ id: string }>;
  searchParams: Promise<Record<string, string | string[] | undefined>>;
};

export default async function ClassAttendanceReportPage({ params, searchParams }: Props) {
  const t = await getTranslations("reports");
  const locale = (await getLocale()) as Locale;
  const { id: classId } = await params;
  const rawParams = await searchParams;

  const hasRead = await can("attendance.read");
  if (!hasRead) {
    return (
      <div className="space-y-4">
        <h1 className="text-xl font-semibold">{t("attendanceReport")}</h1>
        <section className="rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-600">
          <p>{t("deniedAttendance")}</p>
        </section>
      </div>
    );
  }

  const startDate = typeof rawParams.startDate === "string" ? rawParams.startDate : undefined;
  const endDate = typeof rawParams.endDate === "string" ? rawParams.endDate : undefined;

  const supabase = await createClient();
  const result = await buildClassAttendanceReport(supabase, { classId, startDate, endDate });
  if (!result.ok) {
    if (result.error === "not_found") notFound();
    return (
      <div className="space-y-4">
        <h1 className="text-xl font-semibold">{t("attendanceReport")}</h1>
        <p className="text-sm text-red-700">{t("invalidPeriod")}</p>
      </div>
    );
  }

  const labels = buildReportLabels(t, { title: t("attendanceReport") });

  return (
    <div className="space-y-6">
      <div className="report-no-print flex flex-wrap items-center justify-between gap-3">
        <Link href={`/classes/${classId}/reports`} className="text-sm text-slate-600 underline">
          {t("backToReports")}
        </Link>
        <ReportPrintButton label={t("print")} />
      </div>
      <ReportPeriodForm
        startDate={result.report.period.startDate}
        endDate={result.report.period.endDate}
        fromLabel={t("from")}
        toLabel={t("to")}
        periodLabel={t("reportingPeriod")}
        submitLabel={t("applyPeriod")}
      />
      <ClassAttendanceReportView report={result.report} locale={locale} labels={labels} />
    </div>
  );
}
