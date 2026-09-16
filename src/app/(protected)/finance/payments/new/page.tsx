import { getTranslations } from "next-intl/server";
import { RecordPaymentForm } from "@/components/finance/record-payment-form";
import { can } from "@/lib/permissions/can";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

export default async function RecordPaymentPage() {
  const t = await getTranslations("finance.payments");

  if (!(await can("payment.record"))) {
    return (
      <section className="rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-600">
        <p>{t("denied")}</p>
      </section>
    );
  }

  const supabase = await createClient();
  const { data: guardians } = await supabase
    .from("guardian")
    .select("id, given_name, family_name")
    .order("family_name");

  const guardianOptions = (guardians ?? []).map((g) => ({
    id: g.id,
    name: `${g.family_name ?? ""} ${g.given_name ?? ""}`.trim(),
  }));

  return (
    <div className="space-y-4">
      <h2 className="text-lg font-semibold">{t("recordPayment")}</h2>
      <RecordPaymentForm guardians={guardianOptions} />
    </div>
  );
}
