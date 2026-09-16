import Link from "next/link";
import { notFound } from "next/navigation";
import { getTranslations } from "next-intl/server";
import { EnrollmentFinanceSummary } from "@/components/finance/enrollment-finance-summary";
import { FinancialTermsForm } from "@/components/finance/financial-terms-form";
import { formatFinanceMoney } from "@/lib/finance/format-finance-value";
import { queryEnrollmentFinanceContext } from "@/lib/finance/query-enrollment-finance";
import { can } from "@/lib/permissions/can";
import { resolveLocale } from "@/i18n/resolve-locale";
import { getIdentityState } from "@/lib/auth/get-identity-state";
import { formatDate } from "@/lib/formatting";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

type Props = { params: Promise<{ id: string; enrollmentId: string }> };

export default async function EnrollmentFinancePage({ params }: Props) {
  const t = await getTranslations("finance.enrollment");
  const { id: studentId, enrollmentId } = await params;
  const identity = await getIdentityState();
  const locale = await resolveLocale(identity.kind === "active" ? identity.appUser : null);

  if (!(await can("charge.read"))) {
    return (
      <section className="rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-600">
        <p>{t("denied")}</p>
      </section>
    );
  }

  const canManage = await can("charge.create");
  const supabase = await createClient();
  const { data: enrollment } = await supabase
    .from("enrollment")
    .select("id, class:class_id(name)")
    .eq("id", enrollmentId)
    .eq("student_id", studentId)
    .maybeSingle();

  if (!enrollment) notFound();

  const ctx = await queryEnrollmentFinanceContext(supabase, enrollmentId);
  const cls = enrollment.class as { name?: string } | null;

  return (
    <div className="space-y-6">
      <div>
        <Link href={`/students/${studentId}/enrollments`} className="text-sm text-slate-600 underline">
          ← {t("backToEnrollments")}
        </Link>
        <h1 className="mt-2 text-xl font-semibold">{t("title")}</h1>
        <p className="text-sm text-slate-600">{cls?.name}</p>
      </div>

      <section className="space-y-3">
        <h2 className="font-medium">{t("summary")}</h2>
        <EnrollmentFinanceSummary summary={ctx.summary} />
      </section>

      <section className="space-y-3">
        <h2 className="font-medium">{t("financialTerms")}</h2>
        <FinancialTermsForm
          enrollmentId={enrollmentId}
          draftTerms={ctx.draftTerms}
          activeTerms={ctx.terms}
          canManage={canManage}
        />
      </section>

      <section className="space-y-3">
        <h2 className="font-medium">{t("paymentSchedule")}</h2>
        {ctx.schedule.length === 0 ? (
          <p className="text-sm text-slate-600">{t("noSchedule")}</p>
        ) : (
          <ul className="space-y-2 text-sm">
            {ctx.schedule.map((item) => (
              <li key={item.id} className="flex justify-between rounded border border-slate-200 bg-white p-3">
                <span>{formatDate(item.dueDate, locale)} {item.label ? `— ${item.label}` : ""}</span>
                <span>{formatFinanceMoney(item.amount, locale)}</span>
              </li>
            ))}
          </ul>
        )}
      </section>

      <section className="space-y-3">
        <h2 className="font-medium">{t("charges")}</h2>
        {ctx.charges.length === 0 ? (
          <p className="text-sm text-slate-600">{t("noCharges")}</p>
        ) : (
          <div className="overflow-x-auto rounded-lg border border-slate-200 bg-white">
            <table className="min-w-full text-sm">
              <thead className="bg-slate-50">
                <tr>
                  <th className="px-4 py-2 text-left">{t("dueDate")}</th>
                  <th className="px-4 py-2 text-right">{t("chargeAmount")}</th>
                  <th className="px-4 py-2 text-right">{t("outstanding")}</th>
                  <th className="px-4 py-2 text-left">{t("status")}</th>
                </tr>
              </thead>
              <tbody>
                {ctx.charges.map((c) => (
                  <tr key={c.id} className="border-t border-slate-100">
                    <td className="px-4 py-2">{formatDate(c.dueDate, locale)}</td>
                    <td className="px-4 py-2 text-right">{formatFinanceMoney(c.amount, locale)}</td>
                    <td className="px-4 py-2 text-right">{formatFinanceMoney(c.outstandingBalance, locale)}</td>
                    <td className="px-4 py-2">{c.status}</td>
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
