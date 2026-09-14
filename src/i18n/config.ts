export const locales = ["vi", "en"] as const;
export type Locale = (typeof locales)[number];

export const defaultLocale: Locale = "vi";

export const LOCALE_COOKIE = "olli_locale";

export function isValidLocale(value: string | undefined | null): value is Locale {
  return locales.includes(value as Locale);
}
