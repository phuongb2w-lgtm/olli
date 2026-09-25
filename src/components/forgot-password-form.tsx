"use client";

import Link from "next/link";
import { useActionState } from "react";
import { useTranslations } from "next-intl";
import { requestPasswordReset, type ForgotPasswordState } from "@/app/actions/auth";
import { LanguageSwitch } from "@/components/language-switch";

const initialState: ForgotPasswordState = {};

export function ForgotPasswordForm() {
  const t = useTranslations();
  const [state, formAction, pending] = useActionState(requestPasswordReset, initialState);

  return (
    <div className="mx-auto flex min-h-screen max-w-md flex-col justify-center px-4">
      <div className="mb-6 flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-semibold">{t("auth.forgotPasswordTitle")}</h1>
          <p className="text-sm text-slate-600">{t("auth.forgotPasswordHint")}</p>
        </div>
        <LanguageSwitch />
      </div>

      {state.submitted ? (
        <div
          className="space-y-4 rounded-lg border border-slate-200 bg-white p-6 shadow-sm"
          role="status"
        >
          <p className="text-sm text-slate-700">{t("auth.forgotPasswordConfirmation")}</p>
          <Link href="/login" className="text-sm font-medium text-slate-900 underline">
            {t("auth.backToSignIn")}
          </Link>
        </div>
      ) : (
        <form
          action={formAction}
          className="space-y-4 rounded-lg border border-slate-200 bg-white p-6 shadow-sm"
        >
          <div>
            <label htmlFor="email" className="mb-1 block text-sm font-medium">
              {t("auth.email")}
            </label>
            <input
              id="email"
              name="email"
              type="email"
              autoComplete="username"
              required
              className="w-full rounded border border-slate-300 px-3 py-2 text-sm"
            />
          </div>

          <button
            type="submit"
            disabled={pending}
            className="w-full rounded bg-slate-900 px-4 py-2 text-sm font-medium text-white hover:bg-slate-800 disabled:opacity-50"
          >
            {pending ? t("auth.sendingResetLink") : t("auth.sendResetLink")}
          </button>

          <Link href="/login" className="block text-center text-sm text-slate-600 underline">
            {t("auth.backToSignIn")}
          </Link>
        </form>
      )}
    </div>
  );
}
