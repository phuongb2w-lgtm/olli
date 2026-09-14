"use server";

import { revalidatePath } from "next/cache";
import { cookies } from "next/headers";
import { isValidLocale, LOCALE_COOKIE, type Locale } from "@/i18n/config";
import { createClient } from "@/lib/supabase/server";

export async function setLocale(locale: Locale) {
  if (!isValidLocale(locale)) {
    return { ok: false as const, error: "invalid_locale" as const };
  }

  const cookieStore = await cookies();
  cookieStore.set(LOCALE_COOKIE, locale, {
    path: "/",
    sameSite: "lax",
    maxAge: 60 * 60 * 24 * 365,
  });

  const supabase = await createClient();
  const { data: claimsData } = await supabase.auth.getClaims();
  if (claimsData?.claims?.sub) {
    const { error } = await supabase.rpc("set_own_preferred_locale", {
      p_locale: locale,
    });
    if (error) {
      return { ok: false as const, error: "persist_failed" as const };
    }
  }

  revalidatePath("/", "layout");
  return { ok: true as const };
}
