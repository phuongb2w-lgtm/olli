import { cookies } from "next/headers";
import { defaultLocale, isValidLocale, LOCALE_COOKIE, type Locale } from "./config";
import type { AppUserContext } from "@/types/app-user";

/**
 * Locale fallback chain for authenticated sessions:
 * app_user.preferred_locale → organization.default_locale → cookie → vi
 */
export async function resolveLocale(appUser?: AppUserContext | null): Promise<Locale> {
  if (appUser?.preferredLocale && isValidLocale(appUser.preferredLocale)) {
    return appUser.preferredLocale;
  }

  if (appUser?.organizationDefaultLocale && isValidLocale(appUser.organizationDefaultLocale)) {
    return appUser.organizationDefaultLocale;
  }

  const cookieStore = await cookies();
  const cookieLocale = cookieStore.get(LOCALE_COOKIE)?.value;
  if (isValidLocale(cookieLocale)) {
    return cookieLocale;
  }

  return defaultLocale;
}
