import Link from "next/link";
import { getTranslations } from "next-intl/server";
import { ReportingPeriodFilterForm } from "@/components/finance/reporting-period-filter-form";
import { can } from "@/lib/permissions/can";
import {
  fetchConsultantCrmOverview,
  fetchConsultantWorkQueue,
} from "@/lib/reporting/crm-admissions-read-model";
import { parseReportingSearchParams } from "@/lib/reporting/parse-reporting-search-params";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

type Props = {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
};

function formatRate(rate: number | null): string {
  if (rate === null) return "—";
  return `${(rate * 100).toFixed(1)}%`;
}

export default async function ConsultantMyWorkPage({ searchParams }: Props) {
  const t = await getTranslations("crm.myWork");
  const rawParams = await searchParams;
  const { period } = parseReportingSearchParams(rawParams);

  if (!(await can("lead.read"))) {
    return (
      <section className="rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-600">
        <p>{t("denied")}</p>
      </section>
    );
  }

  const supabase = await createClient();
  const [{ data: overview, error }, { items: queue, error: queueError }] = await Promise.all([
    fetchConsultantCrmOverview(supabase, period),
    fetchConsultantWorkQueue(supabase),
  ]);

  if (error || !overview) {
    return (
      <section className="rounded-lg border border-red-200 bg-red-50 p-4 text-sm text-red-800">
        <p>{t("loadError")}</p>
      </section>
    );
  }

  const declarations = overview.declarations;

  return (
    <div className="space-y-6">
      <div>
        <h2 className="text-lg font-semibold text-slate-900">{t("title")}</h2>
        <p className="mt-1 text-sm text-slate-600">{t("subtitle")}</p>
      </div>

      <ReportingPeriodFilterForm
        action="/crm/my-work"
        startDate={period.startDate}
        endDate={period.endDate}
        comparePrevious={false}
      />

      <section className="rounded-lg border border-slate-200 bg-white p-4">
        <h3 className="text-sm font-semibold text-slate-800">{t("workQueueTitle")}</h3>
        {queueError || queue.length === 0 ? (
          <p className="mt-2 text-sm text-slate-600">{t("workQueueEmpty")}</p>
        ) : (
          <ul className="mt-3 space-y-2 text-sm">
            {queue.map((item, index) => (
              <li
                key={`${item.queue_type}-${item.lead_id ?? index}`}
                className="flex items-center justify-between gap-2 rounded border border-slate-100 bg-slate-50 px-3 py-2"
              >
                <span>{t(`queueType.${item.queue_type}` as "queueType.overdue_follow_up")}</span>
                {item.lead_id ? (
                  <Link href={item.drill_down_path} className="text-xs font-medium underline">
                    {t("viewLead")}
                  </Link>
                ) : null}
              </li>
            ))}
          </ul>
        )}
      </section>

      <section className="rounded-lg border border-slate-200 bg-white p-4">
        <h3 className="text-sm font-semibold text-slate-800">{t("performanceTitle")}</h3>
        <dl className="mt-3 grid gap-3 sm:grid-cols-2 lg:grid-cols-3 text-sm">
          <div>
            <dt className="text-slate-600">{t("leadsOwned")}</dt>
            <dd className="font-medium">{overview.leads_owned}</dd>
          </div>
          <div>
            <dt className="text-slate-600">{t("activitiesInPeriod")}</dt>
            <dd className="font-medium">{overview.activities_in_period}</dd>
          </div>
          <div>
            <dt className="text-slate-600">{t("trialsScheduled")}</dt>
            <dd className="font-medium">{overview.trials_scheduled_in_period}</dd>
          </div>
          <div>
            <dt className="text-slate-600">{t("conversionsAttributed")}</dt>
            <dd className="font-medium">{overview.conversions_attributed_in_period}</dd>
          </div>
          <div>
            <dt className="text-slate-600">{t("conversionRate")}</dt>
            <dd className="font-medium">{formatRate(overview.conversion_rate_attributed)}</dd>
          </div>
        </dl>
      </section>

      <section className="rounded-lg border border-slate-200 bg-white p-4">
        <h3 className="text-sm font-semibold text-slate-800">{t("declarationsTitle")}</h3>
        <p className="mt-1 text-xs text-slate-600">{declarations.semantic_note}</p>
        <dl className="mt-3 grid gap-3 sm:grid-cols-2 text-sm">
          <div>
            <dt className="text-slate-600">{t("pendingDeclarations")}</dt>
            <dd className="font-medium">
              {declarations.pending_count} ({declarations.pending_amount})
            </dd>
          </div>
          <div>
            <dt className="text-slate-600">{t("approvedDeclarations")}</dt>
            <dd className="font-medium">
              {declarations.approved_count} ({declarations.approved_amount})
            </dd>
          </div>
          <div>
            <dt className="text-slate-600">{t("returnedDeclarations")}</dt>
            <dd className="font-medium">
              {declarations.returned_count} ({declarations.returned_amount})
            </dd>
          </div>
        </dl>
      </section>
    </div>
  );
}
