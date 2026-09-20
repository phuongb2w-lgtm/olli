import Link from "next/link";
import { getTranslations } from "next-intl/server";
import { ConsultantProductivityTable } from "@/components/crm/consultant-productivity-table";
import { CrmAdmissionsExceptionsPanel } from "@/components/crm/crm-admissions-exceptions-panel";
import { FinanceComparisonMetricCard } from "@/components/finance/finance-comparison-metric-card";
import { ReportingPeriodFilterForm } from "@/components/finance/reporting-period-filter-form";
import { resolveLocale } from "@/i18n/resolve-locale";
import { getIdentityState } from "@/lib/auth/get-identity-state";
import { can } from "@/lib/permissions/can";
import {
  fetchCrmAdmissionsExceptions,
  fetchCrmAdmissionsOverview,
  parseConsultantProductivityRows,
} from "@/lib/reporting/crm-admissions-read-model";
import { buildReportingHref } from "@/lib/reporting/build-reporting-href";
import { formatReportingRate } from "@/lib/reporting/format-reporting-metric";
import { parseReportingSearchParams } from "@/lib/reporting/parse-reporting-search-params";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

type Props = {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
};

export default async function ExecutiveAdmissionsPage({ searchParams }: Props) {
  const t = await getTranslations("crm.intelligence");
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
  const { data: overview, error } = await fetchCrmAdmissionsOverview(
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

  const { exceptions } = await fetchCrmAdmissionsExceptions(supabase, period);
  const intake = overview.leadIntake;
  const activity = overview.activity;
  const trials = overview.trials;
  const conversions = overview.conversions;
  const productivity = parseConsultantProductivityRows(overview.consultantProductivity);
  const productivityMeta = Array.isArray(overview.consultantProductivity)
    ? null
    : overview.consultantProductivity;

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

      <p className="text-sm text-slate-600">{t("semanticsNote")}</p>

      <ReportingPeriodFilterForm
        action="/executive/admissions"
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
          label={t("leadsCreated")}
          value={intake.leads_created}
          change={null}
          locale={locale}
          valueKind="count"
          variant="neutral"
          sublabel={t("unassignedLeads", { count: intake.unassigned_count })}
        />
        <FinanceComparisonMetricCard
          label={t("activitiesRecorded")}
          value={activity.activities_recorded}
          change={null}
          locale={locale}
          valueKind="count"
          variant="neutral"
          sublabel={t("overdueFollowUps", { count: activity.overdue_follow_ups })}
        />
        <FinanceComparisonMetricCard
          label={t("trialsCompleted")}
          value={trials.trials_completed}
          change={null}
          locale={locale}
          valueKind="count"
          variant="neutral"
          sublabel={t("trialsScheduled", { count: trials.trials_scheduled })}
        />
        <FinanceComparisonMetricCard
          label={t("conversionsInPeriod")}
          value={conversions.conversions_in_period}
          change={null}
          locale={locale}
          valueKind="count"
          variant="revenue"
        />
        <FinanceComparisonMetricCard
          label={t("cohortConversionRate")}
          value={conversions.cohort_conversions}
          change={null}
          locale={locale}
          valueKind="count"
          variant="revenue"
          hint={formatReportingRate(conversions.cohort_conversion_rate, locale)}
          sublabel={t("cohortDenominator", { count: conversions.cohort_leads_created })}
        />
        <FinanceComparisonMetricCard
          label={t("pendingFollowUps")}
          value={activity.pending_follow_ups}
          change={null}
          locale={locale}
          valueKind="count"
          variant="obligation"
        />
      </div>

      <section className="rounded-lg border border-slate-200 bg-white p-4">
        <h2 className="text-sm font-semibold text-slate-800">{t("consultantProductivityTitle")}</h2>
        <p className="mt-1 text-xs text-slate-600">{t("consultantProductivityNote")}</p>
        {productivityMeta?.cohort_attribution_rule ? (
          <p className="mt-1 text-xs text-slate-500">{productivityMeta.cohort_attribution_rule}</p>
        ) : null}
        <div className="mt-3">
          <ConsultantProductivityTable
            rows={productivity}
            emptyLabel={t("consultantProductivityEmpty")}
            headers={{
              consultant: t("consultantColumn"),
              currentOwned: t("currentLeadsOwnedColumn"),
              cohortLeads: t("cohortLeadsColumn"),
              activities: t("activitiesColumn"),
              trials: t("trialsColumn"),
              conversionsInPeriod: t("conversionsInPeriodColumn"),
              cohortConversionRate: t("cohortConversionRateColumn"),
              approvedDeclarations: t("approvedDeclarationsColumn"),
              pendingDeclarations: t("pendingDeclarationsColumn"),
            }}
          />
        </div>
      </section>

      {Array.isArray(overview.sources) && overview.sources.length > 0 ? (
        <section className="rounded-lg border border-slate-200 bg-white p-4">
          <h2 className="text-sm font-semibold text-slate-800">{t("sourceTitle")}</h2>
          <ul className="mt-3 space-y-2 text-sm">
            {overview.sources.slice(0, 8).map((source) => (
              <li key={source.source_id ?? source.source_name} className="flex justify-between gap-4">
                <span>{source.source_name}</span>
                <span className="text-slate-600">
                  {t("sourceRow", {
                    leads: source.leads_created,
                    conversions: source.conversions_in_period,
                    rate: formatReportingRate(source.cohort_conversion_rate, locale),
                  })}
                </span>
              </li>
            ))}
          </ul>
        </section>
      ) : null}

      <CrmAdmissionsExceptionsPanel
        exceptions={exceptions}
        title={t("exceptionsTitle")}
        emptyLabel={t("exceptionsEmpty")}
        viewLabel={t("viewDetail")}
      />
    </div>
  );
}
