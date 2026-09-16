import { getTranslations } from "next-intl/server";
import { FinanceNav } from "@/components/finance/finance-nav";
import { can } from "@/lib/permissions/can";

export const dynamic = "force-dynamic";

export default async function FinanceLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  const t = await getTranslations("finance");
  const hasAnyFinance =
    (await can("charge.read")) ||
    (await can("payment.read")) ||
    (await can("expense.read")) ||
    (await can("class_economics.read")) ||
    (await can("class_simulation.read"));

  if (!hasAnyFinance) {
    return (
      <div className="space-y-4">
        <h1 className="text-xl font-semibold">{t("title")}</h1>
        <section className="rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-600">
          <p>{t("denied")}</p>
        </section>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <h1 className="text-xl font-semibold">{t("title")}</h1>
      <FinanceNav />
      {children}
    </div>
  );
}
