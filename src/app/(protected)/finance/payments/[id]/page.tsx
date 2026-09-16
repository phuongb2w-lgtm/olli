import Link from "next/link";
import { notFound } from "next/navigation";
import { getTranslations } from "next-intl/server";
import { ReversePaymentButton } from "@/components/finance/reverse-payment-button";
import { getPaymentDetails } from "@/app/actions/payments";
import { formatFinanceMoney } from "@/lib/finance/format-finance-value";
import { can } from "@/lib/permissions/can";
import { resolveLocale } from "@/i18n/resolve-locale";
import { getIdentityState } from "@/lib/auth/get-identity-state";
import { formatDateTime } from "@/lib/formatting";

export const dynamic = "force-dynamic";

type Props = { params: Promise<{ id: string }> };

export default async function PaymentDetailPage({ params }: Props) {
  const t = await getTranslations("finance.payments");
  const tMethod = await getTranslations("paymentMethod");
  const { id } = await params;
  const identity = await getIdentityState();
  const locale = await resolveLocale(identity.kind === "active" ? identity.appUser : null);

  if (!(await can("payment.read"))) {
    return (
      <section className="rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-600">
        <p>{t("denied")}</p>
      </section>
    );
  }

  const { payment, error } = await getPaymentDetails(id);
  if (error === "not_found" || !payment) notFound();
  const p = payment as Record<string, unknown>;
  const allocations = (p.allocations as Array<Record<string, unknown>>) ?? [];
  const canReverse = await can("payment.reverse");

  return (
    <div className="space-y-6">
      <Link href="/finance/payments" className="text-sm text-slate-600 underline">
        ← {t("backToList")}
      </Link>
      <h2 className="text-lg font-semibold">{t("detailTitle")}</h2>

      <section className="grid gap-4 rounded-lg border border-slate-200 bg-white p-4 sm:grid-cols-2 lg:grid-cols-3 text-sm">
        <div>
          <p className="text-slate-600">{t("paymentDate")}</p>
          <p className="font-medium">{formatDateTime(String(p.paid_at), locale)}</p>
        </div>
        <div>
          <p className="text-slate-600">{t("method")}</p>
          <p className="font-medium">{tMethod(String(p.method_code) as "cash")}</p>
        </div>
        <div>
          <p className="text-slate-600">{t("amount")}</p>
          <p className="font-medium">{formatFinanceMoney(Number(p.amount), locale)}</p>
        </div>
        <div>
          <p className="text-slate-600">{t("allocated")}</p>
          <p className="font-medium">{formatFinanceMoney(Number(p.allocated_amount), locale)}</p>
        </div>
        <div>
          <p className="text-slate-600">{t("unallocated")}</p>
          <p className="font-medium">{formatFinanceMoney(Number(p.unallocated_amount), locale)}</p>
        </div>
        <div>
          <p className="text-slate-600">{t("reference")}</p>
          <p className="font-medium">{String(p.reference_number ?? "—")}</p>
        </div>
        <div>
          <p className="text-slate-600">{t("status")}</p>
          <p className="font-medium">{String(p.status)}</p>
        </div>
        {p.reversed_at ? (
          <div>
            <p className="text-slate-600">{t("reversedAt")}</p>
            <p className="font-medium">{formatDateTime(String(p.reversed_at), locale)}</p>
          </div>
        ) : null}
      </section>

      <section className="space-y-3">
        <h3 className="font-medium">{t("allocations")}</h3>
        {allocations.length === 0 ? (
          <p className="text-sm text-slate-600">{t("noAllocations")}</p>
        ) : (
          <div className="overflow-x-auto rounded-lg border border-slate-200 bg-white">
            <table className="min-w-full text-sm">
              <thead className="bg-slate-50">
                <tr>
                  <th className="px-4 py-2 text-left">{t("charge")}</th>
                  <th className="px-4 py-2 text-right">{t("allocationAmount")}</th>
                  <th className="px-4 py-2 text-left">{t("status")}</th>
                </tr>
              </thead>
              <tbody>
                {allocations.map((a) => (
                  <tr key={String(a.allocation_id)} className="border-t border-slate-100">
                    <td className="px-4 py-2 font-mono text-xs">{String(a.charge_id)}</td>
                    <td className="px-4 py-2 text-right">
                      {formatFinanceMoney(Number(a.amount), locale)}
                    </td>
                    <td className="px-4 py-2">{String(a.status)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      {canReverse && !p.reversed_at && p.status === "posted" ? (
        <ReversePaymentButton paymentId={id} />
      ) : null}
    </div>
  );
}
