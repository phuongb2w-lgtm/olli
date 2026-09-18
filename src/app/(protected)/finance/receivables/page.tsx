import Link from "next/link";
import { getTranslations } from "next-intl/server";
import { formatFinanceMoney } from "@/lib/finance/format-finance-value";
import { fetchReceivables } from "@/lib/reporting/finance-read-model";
import { can } from "@/lib/permissions/can";
import { resolveLocale } from "@/i18n/resolve-locale";
import { getIdentityState } from "@/lib/auth/get-identity-state";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

export default async function FinanceReceivablesPage() {
  const t = await getTranslations("finance.intelligence");
  const identity = await getIdentityState();
  const locale = await resolveLocale(identity.kind === "active" ? identity.appUser : null);

  if (!(await can("charge.read"))) {
    return (
      <section className="rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-600">
        <p>{t("denied")}</p>
      </section>
    );
  }

  const supabase = await createClient();
  const { rows } = await fetchReceivables(supabase);

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h2 className="text-lg font-semibold">{t("receivablesTitle")}</h2>
        <Link href="/finance" className="text-sm underline">
          {t("backToOverview")}
        </Link>
      </div>

      {rows.length === 0 ? (
        <p className="text-sm text-slate-600">{t("noReceivables")}</p>
      ) : (
        <div className="overflow-x-auto rounded border border-slate-200">
          <table className="min-w-full text-sm">
            <thead className="bg-slate-50 text-left">
              <tr>
                <th className="px-3 py-2">{t("student")}</th>
                <th className="px-3 py-2">{t("dueDate")}</th>
                <th className="px-3 py-2">{t("outstanding")}</th>
                <th className="px-3 py-2">{t("status")}</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((row) => (
                <tr key={row.chargeId} className="border-t border-slate-100">
                  <td className="px-3 py-2">{row.studentName ?? "—"}</td>
                  <td className="px-3 py-2">{row.dueDate ?? "—"}</td>
                  <td className="px-3 py-2">
                    {formatFinanceMoney(row.outstandingBalance, locale)}
                  </td>
                  <td className="px-3 py-2">{row.collectionStatus}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
