import { getTranslations } from "next-intl/server";
import { CrmReportsDashboard } from "@/components/crm/crm-reports-dashboard";
import { ReportPeriodForm } from "@/components/reports/report-period-form";
import { parseCrmReportParams } from "@/lib/crm-reports/parse-report-params";
import { queryCrmAttributionReport } from "@/lib/crm-reports/query-crm-attribution-report";
import { can } from "@/lib/permissions/can";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

type Props = {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
};

export default async function CrmReportsPage({ searchParams }: Props) {
  const t = await getTranslations("crm.reports");
  const hasRead = await can("lead.read");

  if (!hasRead) {
    return (
      <div className="space-y-4">
        <h1 className="text-xl font-semibold">{t("title")}</h1>
        <section className="rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-600">
          <p>{t("denied")}</p>
        </section>
      </div>
    );
  }

  const rawParams = await searchParams;
  const { startDate, endDate } = parseCrmReportParams(rawParams);
  const supabase = await createClient();
  const { report, error } = await queryCrmAttributionReport(supabase, startDate, endDate);

  if (error || !report) {
    return (
      <div className="space-y-4">
        <h1 className="text-xl font-semibold">{t("title")}</h1>
        <section className="rounded-lg border border-red-200 bg-red-50 p-4 text-sm text-red-800">
          <p>{t("loadError")}</p>
        </section>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-xl font-semibold text-slate-900">{t("title")}</h1>
        <p className="mt-1 text-sm text-slate-600">{t("subtitle")}</p>
      </div>

      <ReportPeriodForm
        startDate={startDate}
        endDate={endDate}
        fromLabel={t("fromDate")}
        toLabel={t("toDate")}
        periodLabel={t("dateWindow")}
        submitLabel={t("applyPeriod")}
      />

      <CrmReportsDashboard report={report} />
    </div>
  );
}
