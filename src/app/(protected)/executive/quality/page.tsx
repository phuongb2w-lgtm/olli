import Link from "next/link";
import { getTranslations } from "next-intl/server";
import { AcademicExceptionsPanel } from "@/components/academic/academic-exceptions-panel";
import { FinanceComparisonMetricCard } from "@/components/finance/finance-comparison-metric-card";
import { ReportingPeriodFilterForm } from "@/components/finance/reporting-period-filter-form";
import { resolveLocale } from "@/i18n/resolve-locale";
import { getIdentityState } from "@/lib/auth/get-identity-state";
import { can } from "@/lib/permissions/can";
import {
  fetchAcademicExceptions,
  fetchAcademicQualityOverview,
} from "@/lib/reporting/academic-read-model";
import { buildReportingHref } from "@/lib/reporting/build-reporting-href";
import { parseReportingSearchParams } from "@/lib/reporting/parse-reporting-search-params";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

type Props = {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
};

export default async function ExecutiveQualityPage({ searchParams }: Props) {
  const t = await getTranslations("academic.intelligence");
  const identity = await getIdentityState();
  const locale = await resolveLocale(identity.kind === "active" ? identity.appUser : null);
  const rawParams = await searchParams;
  const { period, comparePrevious } = parseReportingSearchParams(rawParams);

  if (!(await can("report.executive.read"))) {
    return (
      <div className="space-y-4">
        <h1 className="text-xl font-semibold">{t("title")}</h1>
        <section className="rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-600">
          <p>{t("denied")}</p>
        </section>
      </div>
    );
  }

  const supabase = await createClient();
  const { data: overview, error } = await fetchAcademicQualityOverview(
    supabase,
    period,
    comparePrevious,
  );

  if (error || !overview) {
    return (
      <section className="rounded-lg border border-red-200 bg-red-50 p-4 text-sm text-red-800">
        <p>{t("loadError")}</p>
      </section>
    );
  }

  const { exceptions } = await fetchAcademicExceptions(supabase, period);
  const delivery = overview.teachingDelivery;
  const attendance = overview.attendance;
  const assessment = overview.assessment;
  const observation = overview.observation;
  const backlog = overview.reviewBacklog;

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <h1 className="text-xl font-semibold">{t("title")}</h1>
        <Link
          href={buildReportingHref("/executive", period, { comparePrevious })}
          className="text-sm underline"
        >
          {t("backToExecutive")}
        </Link>
      </div>

      <ReportingPeriodFilterForm
        action="/executive/quality"
        startDate={period.startDate}
        endDate={period.endDate}
        comparePrevious={comparePrevious}
      />

      {overview.comparisonPeriod ? (
        <p className="text-xs text-slate-600">
          {t("comparisonHint", {
            start: overview.comparisonPeriod.startDate,
            end: overview.comparisonPeriod.endDate,
          })}
        </p>
      ) : null}

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <FinanceComparisonMetricCard
          label={t("deliveredSessions")}
          value={delivery.deliveredSessions}
          change={null}
          locale={locale}
          valueKind="count"
          variant="neutral"
          sublabel={t("materializedSessions", { count: delivery.materializedSessions })}
        />
        <FinanceComparisonMetricCard
          label={t("attendanceRate")}
          value={attendance.current.attendanceRate}
          change={comparePrevious ? attendance.rateChange : null}
          locale={locale}
          valueKind="rate"
          variant="revenue"
        />
        <FinanceComparisonMetricCard
          label={t("assessmentCoverage")}
          value={assessment.finalizedResults}
          change={null}
          locale={locale}
          valueKind="count"
          variant="neutral"
          sublabel={t("totalResults", { count: assessment.totalResults })}
        />
        <FinanceComparisonMetricCard
          label={t("observationCoverage")}
          value={observation.confirmedObservations}
          change={null}
          locale={locale}
          valueKind="count"
          variant="neutral"
          sublabel={t("totalObservations", { count: observation.observationCount })}
        />
        <FinanceComparisonMetricCard
          label={t("reviewBacklog")}
          value={
            backlog.attendancePending +
            backlog.scoresPending +
            backlog.commentsPending +
            backlog.translationPending
          }
          change={null}
          locale={locale}
          valueKind="count"
          variant="obligation"
        />
        <FinanceComparisonMetricCard
          label={t("cancelledSessions")}
          value={delivery.cancelledSessions}
          change={null}
          locale={locale}
          valueKind="count"
          variant="cost"
        />
      </div>

      <AcademicExceptionsPanel
        exceptions={exceptions}
        title={t("exceptionsTitle")}
        emptyLabel={t("exceptionsEmpty")}
        viewLabel={t("viewDetail")}
      />
    </div>
  );
}
