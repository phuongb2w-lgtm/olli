import { redirect } from "next/navigation";
import { cookies } from "next/headers";
import { AccessDenied } from "@/components/access-denied";
import { AppShell } from "@/components/app-shell";
import { getIdentityState } from "@/lib/auth/get-identity-state";
import {
  APP_NAV_ITEMS,
  filterNavItemsByPermissions,
} from "@/lib/navigation/app-navigation";
import { loadUserPermissions } from "@/lib/navigation/load-user-permissions";
import { isValidLocale, LOCALE_COOKIE } from "@/i18n/config";
import { resolveLocale } from "@/i18n/resolve-locale";

export const dynamic = "force-dynamic";

export default async function ProtectedLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  const identity = await getIdentityState();

  if (identity.kind === "none") {
    redirect("/login");
  }

  if (identity.kind !== "active") {
    return <AccessDenied reason={identity.kind} />;
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

  const permissions = await loadUserPermissions();
  const navItems = filterNavItemsByPermissions(APP_NAV_ITEMS, permissions).map(
    (item) => ({ key: item.key, href: item.href }),
  );

  return (
    <AppShell appUser={identity.appUser} navItems={navItems}>
      {children}
    </AppShell>
  );
}
