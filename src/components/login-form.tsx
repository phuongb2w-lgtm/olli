"use client";

import Link from "next/link";
import { useActionState } from "react";
import { useTranslations } from "next-intl";
import { signIn, type SignInState } from "@/app/actions/auth";
import { LanguageSwitch } from "@/components/language-switch";

const initialState: SignInState = {};

type LoginFormProps = {
  callbackError?: boolean;
};

export function LoginForm({ callbackError = false }: LoginFormProps) {
  const t = useTranslations();
  const [state, formAction, pending] = useActionState(signIn, initialState);

  const errorMessage = callbackError
    ? t("auth.authCallbackError")
    : state.error === "invalid_credentials"
      ? t("auth.invalidCredentials")
      : state.error === "network"
        ? t("auth.networkError")
        : state.error
          ? t("common.error")
          : null;

  return (
    <div className="mx-auto flex min-h-screen max-w-md flex-col justify-center px-4">
      <div className="mb-6 flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-semibold">{t("app.name")}</h1>
          <p className="text-sm text-slate-600">{t("app.tagline")}</p>
        </div>
        <LanguageSwitch />
      </div>

      <form action={formAction} className="space-y-4 rounded-lg border border-slate-200 bg-white p-6 shadow-sm">
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
        <div>
          <div className="mb-1 flex items-center justify-between">
            <label htmlFor="password" className="text-sm font-medium">
              {t("auth.password")}
            </label>
            <Link href="/forgot-password" className="text-xs text-slate-600 underline">
              {t("auth.forgotPasswordLink")}
            </Link>
          </div>
          <input
            id="password"
            name="password"
            type="password"
            autoComplete="current-password"
            required
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
          {pending ? t("auth.signingIn") : t("auth.signIn")}
        </button>
      </form>
    </div>
  );
}
