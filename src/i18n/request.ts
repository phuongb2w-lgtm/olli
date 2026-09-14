import { getRequestConfig } from "next-intl/server";
import { getCurrentAppUser } from "@/lib/auth/get-identity-state";
import { resolveLocale } from "./resolve-locale";

export default getRequestConfig(async () => {
  const appUser = await getCurrentAppUser();
  const locale = await resolveLocale(appUser);

  return {
    locale,
    messages: (await import(`../../messages/${locale}.json`)).default,
  };
});
