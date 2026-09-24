import { getTranslations } from "next-intl/server";
import { CenterSetupForm } from "@/components/onboarding/center-setup-form";
import { fetchOwnerCenterSetup } from "@/lib/onboarding/fetch-owner-center-setup";
import { createClient } from "@/lib/supabase/server";
import Link from "next/link";
import { SUBSCRIPTION_STATUS_PATH } from "@/lib/auth/commercial-access-paths";

export const dynamic = "force-dynamic";

export default async function OnboardingPage() {
  const t = await getTranslations("onboarding");
  const supabase = await createClient();
  const result = await fetchOwnerCenterSetup(supabase);

  if (!result.ok) {
    const messageKey =
      result.code === "not_primary_owner"
        ? "unauthorized"
        : result.code === "commercial_access_restricted"
          ? "commercialRestricted"
          : result.code === "setup_already_complete"
            ? "alreadyComplete"
            : "loadError";

    return (
      <div className="mx-auto max-w-lg space-y-4 p-4">
        <h1 className="text-xl font-semibold text-slate-900">{t("title")}</h1>
        <p className="text-sm text-amber-800">{t(messageKey)}</p>
        {result.code === "commercial_access_restricted" ? (
          <Link href={SUBSCRIPTION_STATUS_PATH} className="text-sm font-medium text-slate-900 underline">
            {t("viewSubscriptionStatus")}
          </Link>
        ) : null}
      </div>
    );
  }

  const { setup } = result;
  const defaultLocale =
    setup.default_locale === "en" || setup.default_locale === "vi"
      ? setup.default_locale
      : "vi";
  const preferredLocale =
    setup.preferred_locale === "en" || setup.preferred_locale === "vi"
      ? setup.preferred_locale
      : defaultLocale;

  const provisioningNotice =
    setup.subscription_status === "provisioning" ? t("provisioningNotice") : null;

  return (
    <div className="mx-auto max-w-lg space-y-6 p-4">
      <div className="space-y-2">
        <h1 className="text-xl font-semibold text-slate-900">{t("title")}</h1>
        <p className="text-sm text-slate-600">{t("intro")}</p>
        {provisioningNotice ? (
          <p className="rounded-md border border-amber-200 bg-amber-50 p-3 text-sm text-amber-900">
            {provisioningNotice}
          </p>
        ) : null}
      </div>

      <CenterSetupForm
        initialName={setup.name ?? ""}
        initialDefaultLocale={defaultLocale}
        initialTimezone={setup.timezone ?? "Asia/Ho_Chi_Minh"}
        initialPreferredLocale={preferredLocale}
      />
    </div>
  );
}
