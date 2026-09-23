import { LanguageSwitch } from "@/components/language-switch";
import { SignOutButton } from "@/components/sign-out-button";
import type { AppUserContext } from "@/types/app-user";
import { getTranslations } from "next-intl/server";

type Props = {
  appUser: AppUserContext;
  children: React.ReactNode;
};

export async function RestrictedShell({ appUser, children }: Props) {
  const t = await getTranslations();

  return (
    <div className="mx-auto flex min-h-screen max-w-2xl flex-col gap-6 px-4 py-8">
      <header className="flex flex-wrap items-center justify-between gap-4 border-b border-slate-200 pb-4">
        <div>
          <p className="text-xs font-medium uppercase tracking-wide text-slate-500">
            {t("commercial.restrictedLabel")}
          </p>
          <h1 className="text-lg font-semibold text-slate-900">{appUser.organizationName}</h1>
          <p className="text-sm text-slate-600">{appUser.displayName}</p>
        </div>
        <div className="flex items-center gap-3">
          <LanguageSwitch />
          <SignOutButton />
        </div>
      </header>
      <main className="flex-1">{children}</main>
    </div>
  );
}
