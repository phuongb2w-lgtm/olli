"use client";

import { useTransition } from "react";
import { useLocale, useTranslations } from "next-intl";
import { setLocale } from "@/app/actions/locale";
import type { Locale } from "@/i18n/config";

export function LanguageSwitch() {
  const t = useTranslations("common");
  const locale = useLocale();
  const [pending, startTransition] = useTransition();

  function onChange(nextLocale: Locale) {
    if (nextLocale === locale) return;
    startTransition(async () => {
      await setLocale(nextLocale);
    });
  }

  return (
    <label className="flex items-center gap-2 text-sm text-slate-600">
      <span>{t("language")}</span>
      <select
        className="rounded border border-slate-300 bg-white px-2 py-1 text-sm disabled:opacity-50"
        value={locale}
        disabled={pending}
        onChange={(event) => onChange(event.target.value as Locale)}
        aria-label={t("language")}
      >
        <option value="vi">{t("vietnamese")}</option>
        <option value="en">{t("english")}</option>
      </select>
    </label>
  );
}
