import { redirect } from "next/navigation";
import { cookies } from "next/headers";
import { AccessDenied } from "@/components/access-denied";
import { RestrictedShell } from "@/components/restricted-shell";
import { ONBOARDING_PATH } from "@/lib/auth/commercial-access-paths";
import { getIdentityState } from "@/lib/auth/get-identity-state";
import { sessionRequiresOnboardingRedirect } from "@/lib/auth/resolve-authenticated-landing";
import { parseSessionCommercialAccess } from "@/lib/auth/session-commercial-access";
import { createClient } from "@/lib/supabase/server";
import { isValidLocale, LOCALE_COOKIE } from "@/i18n/config";
import { resolveLocale } from "@/i18n/resolve-locale";

export const dynamic = "force-dynamic";

export default async function RestrictedLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  const identity = await getIdentityState();

  if (identity.kind === "none") {
    redirect("/login");
  }

  if (identity.kind === "active") {
    redirect("/");
  }

  if (identity.kind !== "commercially_restricted") {
    return <AccessDenied reason={identity.kind} />;
  }

  const supabase = await createClient();
  const { data: commercialAccess, error: commercialError } = await supabase.rpc(
    "fetch_session_commercial_access",
  );
  if (commercialError) {
    throw commercialError;
  }
  const sessionAccess = parseSessionCommercialAccess(commercialAccess);
  if (sessionRequiresOnboardingRedirect(sessionAccess)) {
    redirect(ONBOARDING_PATH);
  }

  const resolvedLocale = await resolveLocale(identity.appUser);
  const cookieStore = await cookies();
  const cookieLocale = cookieStore.get(LOCALE_COOKIE)?.value;
  if (cookieLocale !== resolvedLocale && isValidLocale(resolvedLocale)) {
    cookieStore.set(LOCALE_COOKIE, resolvedLocale, {
      path: "/",
      sameSite: "lax",
      maxAge: 60 * 60 * 24 * 365,
    });
  }

  return <RestrictedShell appUser={identity.appUser}>{children}</RestrictedShell>;
}
