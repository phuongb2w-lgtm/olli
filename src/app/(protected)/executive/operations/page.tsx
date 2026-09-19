import Link from "next/link";
import { getTranslations } from "next-intl/server";
import { TeachingOpsExceptionsPanel } from "@/components/operations/teaching-ops-exceptions-panel";
import { FinanceComparisonMetricCard } from "@/components/finance/finance-comparison-metric-card";
import { ReportingPeriodFilterForm } from "@/components/finance/reporting-period-filter-form";
import { resolveLocale } from "@/i18n/resolve-locale";
import { getIdentityState } from "@/lib/auth/get-identity-state";
import { can } from "@/lib/permissions/can";
import { parseReportingSearchParams } from "@/lib/reporting/parse-reporting-search-params";
import {
  fetchTeachingOpsExceptions,
  fetchTeachingOpsIntelligenceOverview,
  teachingOpsMetricDelta,
} from "@/lib/reporting/teaching-ops-read-model";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

type Props = {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
};

function formatRate(rate: number | null): string {
  if (rate === null) return "—";
  return `${(rate * 100).toFixed(1)}%`;
}

export default async function ExecutiveOperationsPage({ searchParams }: Props) {
  const t = await getTranslations("teachingOps.intelligence");
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
  const { data: overview, error } = await fetchTeachingOpsIntelligenceOverview(
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

  const sessions = overview.sessionMetrics.current;
  const sessionsPrev = overview.sessionMetrics.previous;
  const changes = overview.changeMetrics.current;
  const changesPrev = overview.changeMetrics.previous;

  const { exceptions } = await fetchTeachingOpsExceptions(supabase, period);

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <h1 className="text-xl font-semibold">{t("title")}</h1>
        <Link href="/executive" className="text-sm underline">
          {t("backToExecutive")}
        </Link>
      </div>

      <p className="text-sm text-slate-600">{t("semanticsNote")}</p>

      <ReportingPeriodFilterForm
        action="/executive/operations"
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
          value={sessions.delivered_sessions}
          change={teachingOpsMetricDelta(
            sessions.delivered_sessions,
            sessionsPrev?.delivered_sessions,
          )}
          locale={locale}
          variant="neutral"
          sublabel={t("materializedSessions", { count: sessions.materialized_sessions })}
        />
        <FinanceComparisonMetricCard
          label={t("projectedOccurrences")}
          value={sessions.projected_occurrences}
          change={teachingOpsMetricDelta(
            sessions.projected_occurrences,
            sessionsPrev?.projected_occurrences,
          )}
          locale={locale}
          variant="neutral"
          sublabel={t("projectedSeparateNote")}
        />
        <FinanceComparisonMetricCard
          label={t("scheduledSessions")}
          value={sessions.scheduled_sessions}
          change={teachingOpsMetricDelta(
            sessions.scheduled_sessions,
            sessionsPrev?.scheduled_sessions,
          )}
          locale={locale}
          variant="neutral"
          sublabel={t("deliveryRatioSublabel", {
            rate: formatRate(sessions.delivery_ratio),
          })}
        />
        <FinanceComparisonMetricCard
          label={t("cancelledSessions")}
          value={sessions.cancelled_sessions}
          change={teachingOpsMetricDelta(
            sessions.cancelled_sessions,
            sessionsPrev?.cancelled_sessions,
          )}
          locale={locale}
          variant="neutral"
        />
        <FinanceComparisonMetricCard
          label={t("rescheduleEvents")}
          value={changes.reschedule.event_count}
          change={teachingOpsMetricDelta(
            changes.reschedule.event_count,
            changesPrev?.reschedule.event_count,
          )}
          locale={locale}
          variant="neutral"
          sublabel={t("rescheduleSessions", {
            count: changes.reschedule.affected_session_count,
          })}
        />
        <FinanceComparisonMetricCard
          label={t("substitutionEvents")}
          value={changes.teacher_substitution.event_count}
          change={teachingOpsMetricDelta(
            changes.teacher_substitution.event_count,
            changesPrev?.teacher_substitution.event_count,
          )}
          locale={locale}
          variant="neutral"
        />
        <FinanceComparisonMetricCard
          label={t("roomChangeEvents")}
          value={changes.room_change.event_count}
          change={teachingOpsMetricDelta(
            changes.room_change.event_count,
            changesPrev?.room_change.event_count,
          )}
          locale={locale}
          variant="neutral"
        />
      </div>

      <TeachingOpsExceptionsPanel
        exceptions={exceptions}
        title={t("exceptionsTitle")}
        emptyLabel={t("exceptionsEmpty")}
        viewLabel={t("viewDrillDown")}
      />

      <section className="rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-700">
        <h2 className="font-semibold text-slate-900">{t("workloadSection")}</h2>
        <p className="mt-2 text-slate-600">{overview.utilizationPercentageRule}</p>
        <Link href="/operations/workload" className="mt-3 inline-block font-medium underline">
          {t("workloadDrillDown")}
        </Link>
      </section>
    </div>
  );
}
