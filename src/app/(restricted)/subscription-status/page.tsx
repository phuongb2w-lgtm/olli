import { redirect } from "next/navigation";
import { getTranslations } from "next-intl/server";
import { OwnerCommercialStatusView } from "@/components/commercial/owner-commercial-status-view";
import { fetchOwnerCommercialStatus } from "@/lib/commercial/fetch-owner-commercial-status";
import { COMMERCIAL_ACCESS_PATH } from "@/lib/auth/commercial-access-paths";
import { getIdentityState } from "@/lib/auth/get-identity-state";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

export default async function SubscriptionStatusPage() {
  const identity = await getIdentityState();

  if (identity.kind === "commercially_restricted" && !identity.isPrimaryOwner) {
    redirect(COMMERCIAL_ACCESS_PATH);
  }

  const t = await getTranslations("commercial");
  const supabase = await createClient();
  const result = await fetchOwnerCommercialStatus(supabase);

  if (!result.ok) {
    const message =
      result.code === "subscription_missing"
        ? t("statusMissing")
        : result.code === "not_primary_owner"
          ? t("notPrimaryOwner")
          : t("loadError");
    return (
      <div className="space-y-4">
        <h2 className="text-xl font-semibold">{t("pageTitle")}</h2>
        <section className="rounded-lg border border-amber-200 bg-amber-50 p-4 text-sm text-amber-950">
          <p>{message}</p>
        </section>
      </div>
    );
  }

  return <OwnerCommercialStatusView status={result.status} titleAs="h2" />;
}
