"use client";

import { useTransition } from "react";
import { useTranslations } from "next-intl";
import { signOut } from "@/app/actions/auth";

export function SignOutButton() {
  const t = useTranslations("auth");
  const [pending, startTransition] = useTransition();

  return (
    <button
      type="button"
      className="rounded border border-slate-300 px-3 py-1.5 text-sm hover:bg-slate-100 disabled:opacity-50"
      disabled={pending}
      onClick={() => startTransition(() => signOut())}
    >
      {t("signOut")}
    </button>
  );
}
