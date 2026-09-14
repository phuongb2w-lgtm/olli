import { useTranslations } from "next-intl";
import { AppNav } from "@/components/app-nav";
import { LanguageSwitch } from "@/components/language-switch";
import { SignOutButton } from "@/components/sign-out-button";
import type { AppUserContext } from "@/types/app-user";

type Props = {
  appUser: AppUserContext;
  children: React.ReactNode;
};

export function AppShell({ appUser, children }: Props) {
  const t = useTranslations();

  return (
    <div className="min-h-screen">
      <header className="border-b border-slate-200 bg-white">
        <div className="mx-auto flex max-w-6xl items-center justify-between gap-4 px-4 py-4">
          <div>
            <p className="text-lg font-semibold">{t("app.name")}</p>
            <p className="text-sm text-slate-600">
              {t("shell.organization")}: {appUser.organizationName}
            </p>
          </div>
          <div className="flex items-center gap-4">
            <p className="text-sm text-slate-600">
              {t("shell.account")}: {appUser.displayName}
            </p>
            <LanguageSwitch />
            <SignOutButton />
          </div>
        </div>
      </header>

      <div className="mx-auto grid max-w-6xl gap-6 px-4 py-6 md:grid-cols-[220px_1fr]">
        <AppNav />

        <main className="space-y-6">{children}</main>
      </div>
    </div>
  );
}
