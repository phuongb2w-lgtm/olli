import { redirect } from "next/navigation";
import { cookies } from "next/headers";
import { AccessDenied } from "@/components/access-denied";
import { RestrictedShell } from "@/components/restricted-shell";
import { AppShell } from "@/components/app-shell";
import { resolveAuthenticatedLandingPath } from "@/lib/auth/resolve-authenticated-landing";
import { getIdentityState } from "@/lib/auth/get-identity-state";
import { parseSessionCommercialAccess } from "@/lib/auth/session-commercial-access";
import { createClient } from "@/lib/supabase/server";
import { isValidLocale, LOCALE_COOKIE } from "@/i18n/config";
import { resolveLocale } from "@/i18n/resolve-locale";

export const dynamic = "force-dynamic";

export default async function OnboardingLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  const identity = await getIdentityState();

  if (identity.kind === "none") {
    redirect("/login");
  }

  if (identity.kind !== "active" && identity.kind !== "commercially_restricted") {
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

  if (sessionAccess.requires_center_setup !== true) {
    redirect(resolveAuthenticatedLandingPath(sessionAccess));
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

  if (identity.kind === "active") {
    return (
      <AppShell appUser={identity.appUser} navItems={[]}>
        {children}
      </AppShell>
    );
  }

  return <RestrictedShell appUser={identity.appUser}>{children}</RestrictedShell>;
}
