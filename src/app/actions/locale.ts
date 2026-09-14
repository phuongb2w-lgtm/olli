"use server";

import { revalidatePath } from "next/cache";
import { cookies } from "next/headers";
import { isValidLocale, LOCALE_COOKIE, type Locale } from "@/i18n/config";

export async function setLocale(locale: Locale) {
  if (!isValidLocale(locale)) {
    return;
  }

  const cookieStore = await cookies();
  cookieStore.set(LOCALE_COOKIE, locale, {
    path: "/",
    sameSite: "lax",
    maxAge: 60 * 60 * 24 * 365,
  });

  revalidatePath("/", "layout");
}
