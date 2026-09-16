import Link from "next/link";
import { getTranslations } from "next-intl/server";
import { formatFinanceMoney } from "@/lib/finance/format-finance-value";
import { queryPaymentsList } from "@/lib/finance/query-payments-list";
import { can } from "@/lib/permissions/can";
import { resolveLocale } from "@/i18n/resolve-locale";
import { getIdentityState } from "@/lib/auth/get-identity-state";
import { formatDate } from "@/lib/formatting";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

export default async function PaymentsPage() {
  const t = await getTranslations("finance.payments");
  const tMethod = await getTranslations("paymentMethod");
  const tAlloc = await getTranslations("paymentAllocation");
  const identity = await getIdentityState();
  const locale = await resolveLocale(identity.kind === "active" ? identity.appUser : null);

  if (!(await can("payment.read"))) {
    return (
      <section className="rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-600">
        <p>{t("denied")}</p>
      </section>
    );
  }

  const canRecord = await can("payment.record");
  const supabase = await createClient();
  const { items, error } = await queryPaymentsList(supabase);

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h2 className="text-lg font-semibold">{t("title")}</h2>
        {canRecord ? (
          <Link
            href="/finance/payments/new"
            className="rounded bg-slate-900 px-4 py-2 text-sm font-medium text-white hover:bg-slate-800"
          >
            {t("recordPayment")}
          </Link>
        ) : null}
      </div>

      {error ? (
        <section className="rounded-lg border border-red-200 bg-red-50 p-4 text-sm text-red-800">
          <p>{t("loadError")}</p>
        </section>
      ) : null}

      {!error && items.length === 0 ? (
        <section className="rounded-lg border border-slate-200 bg-white p-6 text-sm text-slate-600">
          <p>{t("empty")}</p>
        </section>
      ) : null}

      {items.length > 0 ? (
        <div className="overflow-x-auto rounded-lg border border-slate-200 bg-white">
          <table className="min-w-full divide-y divide-slate-200 text-sm">
            <thead className="bg-slate-50">
              <tr>
                <th className="px-4 py-3 text-left font-medium text-slate-700">{t("date")}</th>
                <th className="px-4 py-3 text-left font-medium text-slate-700">{t("payer")}</th>
                <th className="px-4 py-3 text-left font-medium text-slate-700">{t("student")}</th>
                <th className="px-4 py-3 text-left font-medium text-slate-700">{t("method")}</th>
                <th className="px-4 py-3 text-right font-medium text-slate-700">{t("amount")}</th>
                <th className="px-4 py-3 text-right font-medium text-slate-700">{t("allocated")}</th>
                <th className="px-4 py-3 text-right font-medium text-slate-700">{t("unallocated")}</th>
                <th className="px-4 py-3 text-left font-medium text-slate-700">{t("status")}</th>
                <th className="px-4 py-3 text-left font-medium text-slate-700">{t("reference")}</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-200">
              {items.map((item) => (
                <tr key={item.id}>
                  <td className="px-4 py-3">
                    <Link href={`/finance/payments/${item.id}`} className="text-slate-900 underline">
                      {formatDate(item.paidAt, locale)}
                    </Link>
                  </td>
                  <td className="px-4 py-3">{item.payerName ?? "—"}</td>
                  <td className="px-4 py-3">{item.studentName ?? "—"}</td>
                  <td className="px-4 py-3">{tMethod(item.methodCode as "cash")}</td>
                  <td className="px-4 py-3 text-right">{formatFinanceMoney(item.amount, locale)}</td>
                  <td className="px-4 py-3 text-right">{formatFinanceMoney(item.allocatedAmount, locale)}</td>
                  <td className="px-4 py-3 text-right">{formatFinanceMoney(item.unallocatedAmount, locale)}</td>
                  <td className="px-4 py-3">
                    {item.allocationStatus ? tAlloc(item.allocationStatus as "fully_allocated") : item.status}
                  </td>
                  <td className="px-4 py-3">{item.referenceNumber ?? "—"}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      ) : null}
    </div>
  );
}
