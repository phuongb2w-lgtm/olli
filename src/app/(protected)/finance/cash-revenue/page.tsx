import Link from "next/link";
import { getTranslations } from "next-intl/server";
import { ReportingPeriodFilterForm } from "@/components/finance/reporting-period-filter-form";
import { formatFinanceMoney } from "@/lib/finance/format-finance-value";
import {
  fetchCashPayments,
  fetchRecognitionEvents,
} from "@/lib/reporting/finance-read-model";
import { parseReportingSearchParams } from "@/lib/reporting/parse-reporting-search-params";
import { can } from "@/lib/permissions/can";
import { resolveLocale } from "@/i18n/resolve-locale";
import { getIdentityState } from "@/lib/auth/get-identity-state";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

type Props = {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
};

export default async function FinanceCashRevenuePage({ searchParams }: Props) {
  const t = await getTranslations("finance.intelligence");
  const identity = await getIdentityState();
  const locale = await resolveLocale(identity.kind === "active" ? identity.appUser : null);
  const { period } = parseReportingSearchParams(await searchParams);

  const canPayments = await can("payment.read");
  const canRevenue = await can("revenue.read");

  if (!canPayments && !canRevenue) {
    return (
      <section className="rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-600">
        <p>{t("denied")}</p>
      </section>
    );
  }

  const supabase = await createClient();
  const payments = canPayments ? await fetchCashPayments(supabase, period) : { rows: [], error: null };
  const events = canRevenue ? await fetchRecognitionEvents(supabase, period) : { rows: [], error: null };

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h2 className="text-lg font-semibold">{t("cashRevenueTitle")}</h2>
        <Link href="/finance" className="text-sm underline">
          {t("backToOverview")}
        </Link>
      </div>

      <ReportingPeriodFilterForm
        startDate={period.startDate}
        endDate={period.endDate}
        action="/finance/cash-revenue"
        showComparisonToggle={false}
      />

      {canPayments ? (
        <section className="space-y-3">
          <h3 className="text-sm font-semibold text-slate-800">{t("cashCollected")}</h3>
          {payments.rows.length === 0 ? (
            <p className="text-sm text-slate-600">{t("noCashPayments")}</p>
          ) : (
            <div className="overflow-x-auto rounded border border-slate-200">
              <table className="min-w-full text-sm">
                <thead className="bg-slate-50 text-left">
                  <tr>
                    <th className="px-3 py-2">{t("paidAt")}</th>
                    <th className="px-3 py-2">{t("payer")}</th>
                    <th className="px-3 py-2">{t("method")}</th>
                    <th className="px-3 py-2">{t("amount")}</th>
                    <th className="px-3 py-2">{t("allocated")}</th>
                  </tr>
                </thead>
                <tbody>
                  {payments.rows.map((row) => (
                    <tr key={row.paymentId} className="border-t border-slate-100">
                      <td className="px-3 py-2">{new Date(row.paidAt).toLocaleString(locale)}</td>
                      <td className="px-3 py-2">{row.payerName ?? "—"}</td>
                      <td className="px-3 py-2">{row.methodCode}</td>
                      <td className="px-3 py-2">{formatFinanceMoney(row.amount, locale)}</td>
                      <td className="px-3 py-2">{formatFinanceMoney(row.allocatedAmount, locale)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </section>
      ) : null}

      {canRevenue ? (
        <section className="space-y-3">
          <h3 className="text-sm font-semibold text-slate-800">{t("recognizedRevenue")}</h3>
          {events.rows.length === 0 ? (
            <p className="text-sm text-slate-600">{t("noRecognitionEvents")}</p>
          ) : (
            <div className="overflow-x-auto rounded border border-slate-200">
              <table className="min-w-full text-sm">
                <thead className="bg-slate-50 text-left">
                  <tr>
                    <th className="px-3 py-2">{t("recognizedAt")}</th>
                    <th className="px-3 py-2">{t("class")}</th>
                    <th className="px-3 py-2">{t("amount")}</th>
                  </tr>
                </thead>
                <tbody>
                  {events.rows.map((row) => (
                    <tr key={row.eventId} className="border-t border-slate-100">
                      <td className="px-3 py-2">
                        {new Date(row.recognizedAt).toLocaleString(locale)}
                      </td>
                      <td className="px-3 py-2">{row.className ?? "—"}</td>
                      <td className="px-3 py-2">{formatFinanceMoney(row.amount, locale)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </section>
      ) : null}
    </div>
  );
}
