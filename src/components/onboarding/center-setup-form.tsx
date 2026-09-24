"use client";

import { useActionState } from "react";
import { useTranslations } from "next-intl";
import {
  completeCenterSetup,
  type CompleteCenterSetupState,
} from "@/app/actions/center-setup";

type Props = {
  initialName: string;
  initialDefaultLocale: "vi" | "en";
  initialTimezone: string;
  initialPreferredLocale: "vi" | "en";
};

const initialState: CompleteCenterSetupState | null = null;

function errorMessageKey(error: NonNullable<CompleteCenterSetupState & { ok: false }>["error"]) {
  switch (error) {
    case "invalid_organization_name":
      return "errors.invalidName";
    case "invalid_default_locale":
    case "invalid_preferred_locale":
      return "errors.invalidLocale";
    case "invalid_timezone":
      return "errors.invalidTimezone";
    case "commercial_access_restricted":
      return "errors.commercialRestricted";
    case "not_primary_owner":
      return "errors.unauthorized";
    case "setup_already_complete":
      return "errors.alreadyComplete";
    default:
      return "errors.saveFailed";
  }
}

export function CenterSetupForm({
  initialName,
  initialDefaultLocale,
  initialTimezone,
  initialPreferredLocale,
}: Props) {
  const t = useTranslations("onboarding");
  const [state, formAction, pending] = useActionState(completeCenterSetup, initialState);

  const errorKey =
    state && !state.ok ? errorMessageKey(state.error) : null;

  return (
    <form
      action={formAction}
      className="space-y-4 rounded-lg border border-slate-200 bg-white p-6 shadow-sm"
    >
      <div>
        <label htmlFor="name" className="mb-1 block text-sm font-medium">
          {t("fields.centerName")}
        </label>
        <input
          id="name"
          name="name"
          required
          minLength={2}
          maxLength={200}
          defaultValue={initialName}
          className="w-full rounded-md border border-slate-300 px-3 py-2 text-sm"
        />
      </div>

      <div>
        <label htmlFor="default_locale" className="mb-1 block text-sm font-medium">
          {t("fields.defaultLocale")}
        </label>
        <select
          id="default_locale"
          name="default_locale"
          defaultValue={initialDefaultLocale}
          className="w-full rounded-md border border-slate-300 px-3 py-2 text-sm"
        >
          <option value="vi">{t("locales.vi")}</option>
          <option value="en">{t("locales.en")}</option>
        </select>
      </div>

      <div>
        <label htmlFor="timezone" className="mb-1 block text-sm font-medium">
          {t("fields.timezone")}
        </label>
        <input
          id="timezone"
          name="timezone"
          required
          maxLength={100}
          defaultValue={initialTimezone}
          className="w-full rounded-md border border-slate-300 px-3 py-2 text-sm"
        />
        <p className="mt-1 text-xs text-slate-500">{t("fields.timezoneHint")}</p>
      </div>

      <div>
        <label htmlFor="preferred_locale" className="mb-1 block text-sm font-medium">
          {t("fields.yourLanguage")}
        </label>
        <select
          id="preferred_locale"
          name="preferred_locale"
          defaultValue={initialPreferredLocale}
          className="w-full rounded-md border border-slate-300 px-3 py-2 text-sm"
        >
          <option value="vi">{t("locales.vi")}</option>
          <option value="en">{t("locales.en")}</option>
        </select>
      </div>

      {errorKey ? (
        <p className="text-sm text-red-700" role="alert">
          {t(errorKey)}
        </p>
      ) : null}

      <button
        type="submit"
        disabled={pending}
        className="w-full rounded-md bg-slate-900 px-4 py-2 text-sm font-medium text-white disabled:opacity-60"
      >
        {pending ? t("submitting") : t("submit")}
      </button>
    </form>
  );
}
