import { getTranslations } from "next-intl/server";
import { OwnerCommercialStatusView } from "@/components/commercial/owner-commercial-status-view";
import { fetchOwnerCommercialStatus } from "@/lib/commercial/fetch-owner-commercial-status";
import { can } from "@/lib/permissions/can";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

export default async function OwnerSubscriptionPage() {
  const t = await getTranslations("commercial");

  if (!(await can("center_account.manage"))) {
    return (
      <div className="space-y-4">
        <h1 className="text-xl font-semibold">{t("pageTitle")}</h1>
        <section className="rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-700">
          <p>{t("notPrimaryOwner")}</p>
        </section>
      </div>
    );
  }

  const supabase = await createClient();
  const result = await fetchOwnerCommercialStatus(supabase);

  if (!result.ok) {
    const message =
      result.code === "not_primary_owner"
        ? t("notPrimaryOwner")
        : result.code === "subscription_missing"
          ? t("statusMissing")
          : t("loadError");
    return (
      <div className="space-y-4">
        <h1 className="text-xl font-semibold">{t("pageTitle")}</h1>
        <section className="rounded-lg border border-amber-200 bg-amber-50 p-4 text-sm text-amber-950">
          <p>{message}</p>
        </section>
      </div>
    );
  }

  return <OwnerCommercialStatusView status={result.status} titleAs="h1" />;
}
