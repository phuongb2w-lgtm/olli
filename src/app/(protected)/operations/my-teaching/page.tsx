import { getTranslations } from "next-intl/server";
import { OperationsSubnav } from "@/components/operations/operations-subnav";
import { ReportingPeriodFilterForm } from "@/components/finance/reporting-period-filter-form";
import { parseReportingSearchParams } from "@/lib/reporting/parse-reporting-search-params";
import { fetchMyTeachingOpsOverview } from "@/lib/reporting/teaching-ops-read-model";
import { createClient } from "@/lib/supabase/server";
import { formatMinutesAsHours } from "@/lib/teaching/query-workload-analytics";

export const dynamic = "force-dynamic";

type Props = {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
};

export default async function MyTeachingPage({ searchParams }: Props) {
  const t = await getTranslations("teachingOps.personal");
  const rawParams = await searchParams;
  const { period } = parseReportingSearchParams(rawParams);

  const supabase = await createClient();
  const { data, error } = await fetchMyTeachingOpsOverview(supabase, period);

  if (error || !data) {
    return (
      <div className="space-y-4">
        <h1 className="text-xl font-semibold">{t("title")}</h1>
        <OperationsSubnav />
        <section className="rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-600">
          <p>{t("denied")}</p>
        </section>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <header>
        <h1 className="text-xl font-semibold text-slate-900">{t("title")}</h1>
        <p className="text-sm text-slate-600">{t("subtitle")}</p>
      </header>

      <OperationsSubnav />

      <ReportingPeriodFilterForm
        action="/operations/my-teaching"
        startDate={period.startDate}
        endDate={period.endDate}
        comparePrevious={false}
      />

      <section className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <article className="rounded-lg border border-slate-200 bg-white p-4">
          <p className="text-xs text-slate-600">{t("upcomingSessions")}</p>
          <p className="text-2xl font-semibold">{data.upcoming_sessions}</p>
        </article>
        <article className="rounded-lg border border-slate-200 bg-white p-4">
          <p className="text-xs text-slate-600">{t("scheduledSessions")}</p>
          <p className="text-2xl font-semibold">{data.scheduled_sessions}</p>
          <p className="text-xs text-slate-600">
            {formatMinutesAsHours(data.scheduled_minutes)} {t("scheduledHours")}
          </p>
        </article>
        <article className="rounded-lg border border-slate-200 bg-white p-4">
          <p className="text-xs text-slate-600">{t("completedSessions")}</p>
          <p className="text-2xl font-semibold">{data.completed_sessions}</p>
          <p className="text-xs text-slate-600">
            {formatMinutesAsHours(data.delivered_minutes)} {t("teachingHours")}
          </p>
        </article>
        <article className="rounded-lg border border-slate-200 bg-white p-4">
          <p className="text-xs text-slate-600">{t("projectedSessions")}</p>
          <p className="text-2xl font-semibold">{data.projected_sessions}</p>
        </article>
        <article className="rounded-lg border border-slate-200 bg-white p-4">
          <p className="text-xs text-slate-600">{t("cancelledSessions")}</p>
          <p className="text-2xl font-semibold">{data.cancelled_sessions}</p>
        </article>
      </section>

      <p className="text-xs text-slate-600">{data.attribution_rule}</p>
    </div>
  );
}
