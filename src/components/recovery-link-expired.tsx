import Link from "next/link";
import { getTranslations } from "next-intl/server";
import { LanguageSwitch } from "@/components/language-switch";

export async function RecoveryLinkExpired() {
  const t = await getTranslations();

  return (
    <div className="mx-auto flex min-h-screen max-w-md flex-col justify-center px-4">
      <div className="mb-6 flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-semibold">{t("auth.recoveryLinkExpiredTitle")}</h1>
          <p className="text-sm text-slate-600">{t("auth.recoveryLinkExpiredHint")}</p>
        </div>
        <LanguageSwitch />
      </div>

      <div className="space-y-4 rounded-lg border border-slate-200 bg-white p-6 shadow-sm">
        <Link
          href="/forgot-password"
          className="block w-full rounded bg-slate-900 px-4 py-2 text-center text-sm font-medium text-white hover:bg-slate-800"
        >
          {t("auth.requestNewResetLink")}
        </Link>
        <Link href="/login" className="block text-center text-sm text-slate-600 underline">
          {t("auth.backToSignIn")}
        </Link>
      </div>
    </div>
  );
}
