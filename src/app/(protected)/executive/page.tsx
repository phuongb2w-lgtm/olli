import Link from "next/link";
import { getTranslations } from "next-intl/server";
import { ExecutiveAttentionPanel } from "@/components/executive/executive-attention-panel";
import { FinanceComparisonMetricCard } from "@/components/finance/finance-comparison-metric-card";
import { ReportingPeriodFilterForm } from "@/components/finance/reporting-period-filter-form";
import { resolveLocale } from "@/i18n/resolve-locale";
import { getIdentityState } from "@/lib/auth/get-identity-state";
import { can } from "@/lib/permissions/can";
import { fetchExecutiveOverview } from "@/lib/reporting/executive-read-model";
import { parseReportingSearchParams } from "@/lib/reporting/parse-reporting-search-params";
import { teachingOpsMetricDelta } from "@/lib/reporting/teaching-ops-read-model";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

type Props = {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
};

function formatRate(rate: number | null): string {
  if (rate === null) return "—";
  return `${(rate * 100).toFixed(1)}%`;
}

export default async function ExecutiveOverviewPage({ searchParams }: Props) {
  const t = await getTranslations("executive.overview");
  const tFinance = await getTranslations("finance.intelligence");
  const tCrm = await getTranslations("crm.intelligence");
  const tQuality = await getTranslations("academic.intelligence");
  const tOps = await getTranslations("teachingOps.intelligence");
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
  const { data: overview, error } = await fetchExecutiveOverview(
    supabase,
    period,
    comparePrevious,
  );

  if (error || !overview) {
    return (
      <div className="space-y-4">
        <h1 className="text-xl font-semibold">{t("title")}</h1>
        <section className="rounded-lg border border-red-200 bg-red-50 p-4 text-sm text-red-800">
          <p>{t("loadError")}</p>
        </section>
      </div>
    );
  }

  const finance = overview.finance;
  const admissions = overview.admissions;
  const quality = overview.quality;
  const operations = overview.operations;
  const intake = admissions.leadIntake;
  const activity = admissions.activity;
  const conversions = admissions.conversions;
  const delivery = quality.teachingDelivery;
  const attendance = quality.attendance;
  const backlog = quality.reviewBacklog;
  const sessions = operations.sessionMetrics.current;
  const sessionsPrev = operations.sessionMetrics.previous;
  const changes = operations.changeMetrics.current;

  const domainLabels = {
    finance: t("domainFinance"),
    admissions: t("domainAdmissions"),
    quality: t("domainQuality"),
    operations: t("domainOperations"),
  };

  return (
    <div className="space-y-6">
      <div className="space-y-1">
        <h1 className="text-xl font-semibold">{t("title")}</h1>
        <p className="text-sm text-slate-600">{t("description")}</p>
        <p className="text-xs text-slate-500">
          {t("periodHint", {
            start: overview.period.startDate,
            end: overview.period.endDate,
            timezone: overview.period.timezone,
          })}
        </p>
      </div>

      <ReportingPeriodFilterForm
        action="/executive"
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

      <section className="space-y-3 rounded-lg border border-emerald-200 bg-emerald-50/40 p-4">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <h2 className="text-sm font-semibold text-emerald-900">{t("financeSection")}</h2>
          <Link href="/finance" className="text-xs font-medium underline">
            {t("viewDetails")}
          </Link>
        </div>
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          <FinanceComparisonMetricCard
            label={tFinance("cashCollected")}
            value={finance.cashCollected.current}
            change={comparePrevious ? finance.cashCollected.change : null}
            locale={locale}
            variant="cash"
          />
          <FinanceComparisonMetricCard
            label={tFinance("recognizedRevenue")}
            value={finance.recognizedRevenue.current}
            change={comparePrevious ? finance.recognizedRevenue.change : null}
            locale={locale}
            variant="revenue"
          />
          <FinanceComparisonMetricCard
            label={tFinance("outstandingTuition")}
            value={finance.receivables.totalOutstanding}
            change={null}
            locale={locale}
            variant="receivable"
          />
          <FinanceComparisonMetricCard
            label={tFinance("operatingResult")}
            value={finance.operatingResult.current}
            change={comparePrevious ? finance.operatingResult.change : null}
            locale={locale}
            variant="neutral"
          />
        </div>
      </section>

      <section className="space-y-3 rounded-lg border border-sky-200 bg-sky-50/40 p-4">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <h2 className="text-sm font-semibold text-sky-900">{t("admissionsSection")}</h2>
          <Link href="/executive/admissions" className="text-xs font-medium underline">
            {t("viewDetails")}
          </Link>
        </div>
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          <FinanceComparisonMetricCard
            label={tCrm("leadsCreated")}
            value={intake.leads_created}
            change={null}
            locale={locale}
            variant="neutral"
          />
          <FinanceComparisonMetricCard
            label={tCrm("conversionsInPeriod")}
            value={conversions.conversions_in_period}
            change={null}
            locale={locale}
            variant="revenue"
          />
          <FinanceComparisonMetricCard
            label={tCrm("cohortConversionRate")}
            value={conversions.cohort_conversions}
            change={null}
            locale={locale}
            variant="revenue"
            hint={formatRate(conversions.cohort_conversion_rate)}
          />
          <FinanceComparisonMetricCard
            label={tCrm("pendingFollowUps")}
            value={activity.pending_follow_ups}
            change={null}
            locale={locale}
            variant="obligation"
            sublabel={tCrm("overdueFollowUps", { count: activity.overdue_follow_ups })}
          />
        </div>
      </section>

      <section className="space-y-3 rounded-lg border border-violet-200 bg-violet-50/40 p-4">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <h2 className="text-sm font-semibold text-violet-900">{t("qualitySection")}</h2>
          <Link href="/executive/quality" className="text-xs font-medium underline">
            {t("viewDetails")}
          </Link>
        </div>
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          <FinanceComparisonMetricCard
            label={tQuality("deliveredSessions")}
            value={delivery.deliveredSessions}
            change={null}
            locale={locale}
            variant="neutral"
          />
          <FinanceComparisonMetricCard
            label={tQuality("attendanceRate")}
            value={attendance.current.attendanceRate ?? 0}
            change={comparePrevious ? attendance.rateChange : null}
            locale={locale}
            variant="revenue"
            hint={
              attendance.current.attendanceRate === null
                ? t("notApplicable")
                : formatRate(attendance.current.attendanceRate)
            }
          />
          <FinanceComparisonMetricCard
            label={tQuality("reviewBacklog")}
            value={
              backlog.attendancePending +
              backlog.scoresPending +
              backlog.commentsPending +
              backlog.translationPending
            }
            change={null}
            locale={locale}
            variant="obligation"
          />
          <FinanceComparisonMetricCard
            label={tQuality("assessmentCoverage")}
            value={quality.assessment.finalizedResults}
            change={null}
            locale={locale}
            variant="neutral"
            sublabel={tQuality("totalResults", { count: quality.assessment.totalResults })}
          />
        </div>
      </section>

      <section className="space-y-3 rounded-lg border border-amber-200 bg-amber-50/40 p-4">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <h2 className="text-sm font-semibold text-amber-900">{t("operationsSection")}</h2>
          <Link href="/executive/operations" className="text-xs font-medium underline">
            {t("viewDetails")}
          </Link>
        </div>
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          <FinanceComparisonMetricCard
            label={tOps("deliveredSessions")}
            value={sessions.delivered_sessions}
            change={
              comparePrevious
                ? teachingOpsMetricDelta(
                    sessions.delivered_sessions,
                    sessionsPrev?.delivered_sessions,
                  )
                : null
            }
            locale={locale}
            variant="neutral"
          />
          <FinanceComparisonMetricCard
            label={tOps("projectedOccurrences")}
            value={sessions.projected_occurrences}
            change={
              comparePrevious
                ? teachingOpsMetricDelta(
                    sessions.projected_occurrences,
                    sessionsPrev?.projected_occurrences,
                  )
                : null
            }
            locale={locale}
            variant="neutral"
            sublabel={tOps("materializedSessions", { count: sessions.materialized_sessions })}
          />
          <FinanceComparisonMetricCard
            label={tOps("cancelledSessions")}
            value={sessions.cancelled_sessions}
            change={
              comparePrevious
                ? teachingOpsMetricDelta(
                    sessions.cancelled_sessions,
                    sessionsPrev?.cancelled_sessions,
                  )
                : null
            }
            locale={locale}
            variant="obligation"
          />
          <FinanceComparisonMetricCard
            label={tOps("rescheduleEvents")}
            value={changes.reschedule.event_count}
            change={null}
            locale={locale}
            variant="neutral"
          />
        </div>
      </section>

      <ExecutiveAttentionPanel
        items={overview.attention}
        locale={locale}
        title={t("attentionTitle")}
        emptyLabel={t("attentionEmpty")}
        viewLabel={t("viewException")}
        domainLabels={domainLabels}
      />
    </div>
  );
}
