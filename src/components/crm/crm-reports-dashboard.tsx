import Link from "next/link";
import { getTranslations } from "next-intl/server";
import type { CrmAttributionReport } from "@/lib/crm-reports/query-crm-attribution-report";

type Props = {
  report: CrmAttributionReport;
};

function formatRate(value: number): string {
  return `${(value * 100).toFixed(1)}%`;
}

function formatAmount(value: number | null | undefined): string {
  if (value == null) return "—";
  return new Intl.NumberFormat(undefined, { maximumFractionDigits: 0 }).format(value);
}

function leadListHref(params: Record<string, string>): string {
  const search = new URLSearchParams(params);
  return `/crm/leads?${search.toString()}`;
}

export async function CrmReportsDashboard({ report }: Props) {
  const t = await getTranslations("crm.reports");
  const { funnel, permissions } = report;
  const showFinancials =
    permissions.can_view_charged ||
    permissions.can_view_collected ||
    permissions.can_view_recognized_revenue;

  const funnelStages = [
    { key: "leads", count: funnel.leads_created, rate: null },
    { key: "contacted", count: funnel.contacted_leads, rate: null },
    { key: "qualified", count: funnel.qualified_leads, rate: null },
    { key: "trialScheduled", count: funnel.trial_scheduled_leads, rate: funnel.trial_scheduling_rate },
    { key: "trialCompleted", count: funnel.trial_completed_leads, rate: funnel.trial_completion_rate },
    { key: "converted", count: funnel.converted_leads, rate: funnel.conversion_rate },
    { key: "enrolled", count: funnel.enrolled_leads, rate: funnel.converted_to_enrolled_rate },
  ] as const;

  return (
    <div className="space-y-6">
      <section className="rounded-lg border border-slate-200 bg-white p-4">
        <h2 className="text-base font-semibold text-slate-900">{t("headlineMetrics")}</h2>
        <dl className="mt-3 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
          <div>
            <dt className="text-xs text-slate-500">{t("leadsCreated")}</dt>
            <dd className="text-2xl font-semibold">{funnel.leads_created}</dd>
          </div>
          <div>
            <dt className="text-xs text-slate-500">{t("convertedLeads")}</dt>
            <dd className="text-2xl font-semibold">{funnel.converted_leads}</dd>
          </div>
          <div>
            <dt className="text-xs text-slate-500">{t("conversionRate")}</dt>
            <dd className="text-2xl font-semibold">{formatRate(funnel.conversion_rate)}</dd>
          </div>
          <div>
            <dt className="text-xs text-slate-500">{t("lostLeads")}</dt>
            <dd className="text-2xl font-semibold">{funnel.lost_leads}</dd>
          </div>
        </dl>
        <p className="mt-3 text-xs text-slate-500">{t("semanticsNote")}</p>
      </section>

      <section className="rounded-lg border border-slate-200 bg-white p-4">
        <h2 className="text-base font-semibold text-slate-900">{t("funnelTitle")}</h2>
        <div className="mt-3 overflow-x-auto">
          <table className="min-w-full text-sm">
            <thead>
              <tr className="border-b border-slate-200 text-left text-slate-600">
                <th className="py-2 pr-4">{t("stageColumn")}</th>
                <th className="py-2 pr-4">{t("countColumn")}</th>
                <th className="py-2">{t("rateColumn")}</th>
              </tr>
            </thead>
            <tbody>
              {funnelStages.map((stage) => (
                <tr key={stage.key} className="border-b border-slate-100">
                  <td className="py-2 pr-4 font-medium">{t(`stages.${stage.key}`)}</td>
                  <td className="py-2 pr-4">
                    {stage.key === "converted" ? (
                      <Link
                        href={leadListHref({ status: "converted" })}
                        className="underline text-slate-900"
                      >
                        {stage.count}
                      </Link>
                    ) : (
                      stage.count
                    )}
                  </td>
                  <td className="py-2">{stage.rate != null ? formatRate(stage.rate) : "—"}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <p className="mt-2 text-xs text-slate-500">
          {t("trialVolumeNote", {
            scheduled: funnel.trial_events_scheduled,
            completed: funnel.trial_events_completed,
            students: funnel.converted_students,
          })}
        </p>
      </section>

      <section className="rounded-lg border border-slate-200 bg-white p-4">
        <h2 className="text-base font-semibold text-slate-900">{t("sourceTitle")}</h2>
        <div className="mt-3 overflow-x-auto">
          <table className="min-w-full text-sm">
            <thead>
              <tr className="border-b border-slate-200 text-left text-slate-600">
                <th className="py-2 pr-4">{t("sourceColumn")}</th>
                <th className="py-2 pr-4">{t("leadsColumn")}</th>
                <th className="py-2 pr-4">{t("qualifiedColumn")}</th>
                <th className="py-2 pr-4">{t("trialScheduledColumn")}</th>
                <th className="py-2 pr-4">{t("convertedColumn")}</th>
                <th className="py-2 pr-4">{t("enrolledColumn")}</th>
                {showFinancials ? (
                  <>
                    <th className="py-2 pr-4">{t("collectedColumn")}</th>
                    <th className="py-2">{t("recognizedRevenueColumn")}</th>
                  </>
                ) : null}
              </tr>
            </thead>
            <tbody>
              {report.sources.map((row) => (
                <tr key={row.lead_source_id ?? "unattributed"} className="border-b border-slate-100">
                  <td className="py-2 pr-4">
                    <Link
                      href={leadListHref({
                        sourceId: row.lead_source_id ?? "unattributed",
                      })}
                      className="underline text-slate-900"
                    >
                      {row.code === "unattributed" ? t("unattributed") : row.display_name}
                    </Link>
                  </td>
                  <td className="py-2 pr-4">{row.leads_created}</td>
                  <td className="py-2 pr-4">{row.qualified_leads}</td>
                  <td className="py-2 pr-4">{row.trial_scheduled_leads}</td>
                  <td className="py-2 pr-4">{row.converted_leads}</td>
                  <td className="py-2 pr-4">{row.enrolled_leads}</td>
                  {showFinancials ? (
                    <>
                      <td className="py-2 pr-4">
                        {permissions.can_view_collected
                          ? formatAmount(row.financials?.collected_amount)
                          : "—"}
                      </td>
                      <td className="py-2">
                        {permissions.can_view_recognized_revenue
                          ? formatAmount(row.financials?.recognized_revenue)
                          : "—"}
                      </td>
                    </>
                  ) : null}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        {!showFinancials ? (
          <p className="mt-2 text-xs text-slate-500">{t("financialsHidden")}</p>
        ) : null}
      </section>

      <section className="rounded-lg border border-slate-200 bg-white p-4">
        <h2 className="text-base font-semibold text-slate-900">{t("campaignTitle")}</h2>
        <div className="mt-3 overflow-x-auto">
          <table className="min-w-full text-sm">
            <thead>
              <tr className="border-b border-slate-200 text-left text-slate-600">
                <th className="py-2 pr-4">{t("campaignColumn")}</th>
                <th className="py-2 pr-4">{t("leadsColumn")}</th>
                <th className="py-2 pr-4">{t("convertedColumn")}</th>
                <th className="py-2 pr-4">{t("enrolledColumn")}</th>
                <th className="py-2 pr-4">{t("spendColumn")}</th>
                {showFinancials ? (
                  <th className="py-2">{t("collectedColumn")}</th>
                ) : null}
              </tr>
            </thead>
            <tbody>
              {report.campaigns.map((row) => (
                <tr key={row.lead_campaign_id ?? "unattributed"} className="border-b border-slate-100">
                  <td className="py-2 pr-4">
                    <Link
                      href={leadListHref({
                        campaignId: row.lead_campaign_id ?? "unattributed",
                      })}
                      className="underline text-slate-900"
                    >
                      {row.code === "unattributed" ? t("unattributed") : row.name}
                    </Link>
                  </td>
                  <td className="py-2 pr-4">{row.leads_created}</td>
                  <td className="py-2 pr-4">{row.conversions_in_period}</td>
                  <td className="py-2 pr-4">{row.enrollments_from_conversions}</td>
                  <td className="py-2 pr-4">
                    {row.campaign_spend != null ? formatAmount(row.campaign_spend) : t("spendUnavailable")}
                  </td>
                  {showFinancials ? (
                    <td className="py-2">
                      {permissions.can_view_collected
                        ? formatAmount(row.financials?.collected_amount)
                        : "—"}
                    </td>
                  ) : null}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>

      {report.lost_reasons.length > 0 ? (
        <section className="rounded-lg border border-slate-200 bg-white p-4">
          <h2 className="text-base font-semibold text-slate-900">{t("lostReasonTitle")}</h2>
          <ul className="mt-3 space-y-2 text-sm">
            {report.lost_reasons.map((row) => (
              <li key={row.lost_reason_id} className="flex justify-between gap-4">
                <span>{row.display_name}</span>
                <span className="text-slate-600">
                  {row.lost_count} ({formatRate(row.share_of_lost)})
                </span>
              </li>
            ))}
          </ul>
        </section>
      ) : null}
    </div>
  );
}
