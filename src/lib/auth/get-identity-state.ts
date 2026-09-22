import { createClient } from "@/lib/supabase/server";
import type { AppUserContext, IdentityState } from "@/types/app-user";

export async function getIdentityState(): Promise<IdentityState> {
  const supabase = await createClient();
  const { data: claimsData, error: claimsError } = await supabase.auth.getClaims();

  if (claimsError || !claimsData?.claims?.sub) {
    return { kind: "none" };
  }

  const { data: appUserRow, error: appUserError } = await supabase
    .from("app_user")
    .select(
      "id, organization_id, display_name, preferred_locale, status, membership_status, organization:organization_id(name, default_locale, status)",
    )
    .eq("auth_user_id", claimsData.claims.sub)
    .maybeSingle();

  if (appUserError) {
    throw appUserError;
  }

  if (!appUserRow) {
    return { kind: "unmapped" };
  }

  const organizationRaw = appUserRow.organization;
  const organization = Array.isArray(organizationRaw) ? organizationRaw[0] : organizationRaw;
  const organizationStatus = organization?.status;
  const usableIdentity =
    appUserRow.status === "active" &&
    appUserRow.membership_status === "member" &&
    organizationStatus === "active";

  if (!usableIdentity) {
    return { kind: "inactive" };
  }

  if (!organization || !appUserRow.organization_id) {
    return { kind: "no_organization" };
  }

  const appUser: AppUserContext = {
    appUserId: appUserRow.id,
    organizationId: appUserRow.organization_id,
    organizationName: organization.name,
    organizationDefaultLocale: organization.default_locale,
    displayName: appUserRow.display_name,
    preferredLocale: appUserRow.preferred_locale,
    status: appUserRow.status as AppUserContext["status"],
  };

  return { kind: "active", appUser };
}

export async function getCurrentAppUser(): Promise<AppUserContext | null> {
  const state = await getIdentityState();
  return state.kind === "active" ? state.appUser : null;
}
