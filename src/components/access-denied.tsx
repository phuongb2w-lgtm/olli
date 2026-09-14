import { useTranslations } from "next-intl";
import { LanguageSwitch } from "@/components/language-switch";
import { SignOutButton } from "@/components/sign-out-button";
import type { IdentityState } from "@/types/app-user";

type Props = {
  reason: Exclude<IdentityState["kind"], "none" | "active">;
};

export function AccessDenied({ reason }: Props) {
  const t = useTranslations();

  const message =
    reason === "unmapped"
      ? t("access.noMapping")
      : reason === "inactive"
        ? t("access.inactive")
        : t("access.noOrganization");

  return (
    <div className="mx-auto flex min-h-screen max-w-lg flex-col justify-center gap-6 px-4">
      <div className="flex items-center justify-between">
        <h1 className="text-xl font-semibold">{t("access.denied")}</h1>
        <LanguageSwitch />
      </div>
      <div className="rounded-lg border border-amber-200 bg-amber-50 p-6 text-sm text-amber-950">
        <p>{message}</p>
        <p className="mt-2 text-amber-800">{t("access.contactAdmin")}</p>
      </div>
      <SignOutButton />
    </div>
  );
}
