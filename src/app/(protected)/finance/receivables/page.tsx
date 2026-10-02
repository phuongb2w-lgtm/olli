import Link from "next/link";
import { getTranslations } from "next-intl/server";
import { formatFinanceMoney } from "@/lib/finance/format-finance-value";
import { FinanceStudentAccountsWithPersonalFields } from "@/components/custom-fields/finance-receivables-with-personal-fields";
import { fetchFinanceStudentAccounts, fetchReceivables } from "@/lib/reporting/finance-read-model";
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

  const canPersonalFields =
    (await can("student_personal_field.manage")) || (await can("consultant_custom_field.manage"));
  const supabase = await createClient();
  const [{ rows }, { rows: studentRows }] = await Promise.all([
    fetchReceivables(supabase),
    fetchFinanceStudentAccounts(supabase),
  ]);

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h2 className="text-lg font-semibold">{t("receivablesTitle")}</h2>
        <Link href="/finance" className="text-sm underline">
          {t("backToOverview")}
        </Link>
      </div>

      <section className="space-y-2" data-testid="finance-student-accounts">
        <h3 className="text-base font-semibold">{t("studentAccountsTitle")}</h3>
        <p className="text-xs text-slate-600">{t("studentAccountsHint")}</p>
        {studentRows.length === 0 ? (
          <p className="text-sm text-slate-600">{t("noStudentAccounts")}</p>
        ) : canPersonalFields ? (
          <FinanceStudentAccountsWithPersonalFields rows={studentRows} locale={locale} />
        ) : (
          <div className="overflow-x-auto rounded border border-slate-200">
            <table className="min-w-full text-sm">
              <thead className="bg-slate-50 text-left">
                <tr>
                  <th className="px-3 py-2">{t("student")}</th>
                  <th className="px-3 py-2">{t("studentCode")}</th>
                  <th className="px-3 py-2">{t("totalCharged")}</th>
                  <th className="px-3 py-2">{t("totalPaid")}</th>
                  <th className="px-3 py-2">{t("outstanding")}</th>
                </tr>
              </thead>
              <tbody>
                {studentRows.map((row) => (
                  <tr key={row.id} className="border-t border-slate-100" data-testid="finance-student-row">
                    <td className="px-3 py-2">{`${row.familyName} ${row.givenName}`.trim() || "—"}</td>
                    <td className="px-3 py-2">{row.studentCode ?? "—"}</td>
                    <td className="px-3 py-2">{formatFinanceMoney(row.totalCharged, locale)}</td>
                    <td className="px-3 py-2">{formatFinanceMoney(row.totalPaid, locale)}</td>
                    <td className="px-3 py-2">{formatFinanceMoney(row.outstandingBalance, locale)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <section className="space-y-2" data-testid="finance-charge-receivables">
        <h3 className="text-base font-semibold">{t("chargeReceivablesTitle")}</h3>
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
                    <td className="px-3 py-2">{formatFinanceMoney(row.outstandingBalance, locale)}</td>
                    <td className="px-3 py-2">{row.collectionStatus}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>
    </div>
  );
}
