"use client";

import Link from "next/link";
import { useActionState } from "react";
import { useTranslations } from "next-intl";
import { updatePassword, type UpdatePasswordState } from "@/app/actions/auth";
import { LanguageSwitch } from "@/components/language-switch";

const initialState: UpdatePasswordState = {};

export function UpdatePasswordForm() {
  const t = useTranslations();
  const [state, formAction, pending] = useActionState(updatePassword, initialState);

  const errorMessage =
    state.error === "validation"
      ? t("auth.passwordValidationError")
      : state.error === "session"
        ? t("auth.recoverySessionExpired")
        : state.error
          ? t("auth.networkError")
          : null;

  return (
    <div className="mx-auto flex min-h-screen max-w-md flex-col justify-center px-4">
      <div className="mb-6 flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-semibold">{t("auth.updatePasswordTitle")}</h1>
          <p className="text-sm text-slate-600">{t("auth.updatePasswordHint")}</p>
        </div>
        <LanguageSwitch />
      </div>

      <form
        action={formAction}
        className="space-y-4 rounded-lg border border-slate-200 bg-white p-6 shadow-sm"
      >
        <div>
          <label htmlFor="password" className="mb-1 block text-sm font-medium">
            {t("auth.newPassword")}
          </label>
          <input
            id="password"
            name="password"
            type="password"
            autoComplete="new-password"
            required
            minLength={8}
            className="w-full rounded border border-slate-300 px-3 py-2 text-sm"
          />
        </div>
        <div>
          <label htmlFor="confirmPassword" className="mb-1 block text-sm font-medium">
            {t("auth.confirmPassword")}
          </label>
          <input
            id="confirmPassword"
            name="confirmPassword"
            type="password"
            autoComplete="new-password"
            required
            minLength={8}
            className="w-full rounded border border-slate-300 px-3 py-2 text-sm"
          />
        </div>

        {errorMessage ? (
          <p className="text-sm text-red-600" role="alert">
            {errorMessage}
          </p>
        ) : null}

        <button
          type="submit"
          disabled={pending}
          className="w-full rounded bg-slate-900 px-4 py-2 text-sm font-medium text-white hover:bg-slate-800 disabled:opacity-50"
        >
          {pending ? t("auth.updatingPassword") : t("auth.savePassword")}
        </button>

        <Link href="/login" className="block text-center text-sm text-slate-600 underline">
          {t("auth.backToSignIn")}
        </Link>
      </form>
    </div>
  );
}
