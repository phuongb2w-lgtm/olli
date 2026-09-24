"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { isValidLocale, LOCALE_COOKIE, type Locale } from "@/i18n/config";
import { resolveAuthenticatedLandingPath } from "@/lib/auth/resolve-authenticated-landing";
import { parseSessionCommercialAccess } from "@/lib/auth/session-commercial-access";
import { mapCompleteCenterSetupError } from "@/lib/onboarding/complete-center-setup-errors";
import { createClient } from "@/lib/supabase/server";
import { cookies } from "next/headers";

export type CompleteCenterSetupState =
  | { ok: true }
  | { ok: false; error: ReturnType<typeof mapCompleteCenterSetupError> };

export async function completeCenterSetup(
  _prev: CompleteCenterSetupState | null,
  formData: FormData,
): Promise<CompleteCenterSetupState> {
  const name = String(formData.get("name") ?? "").trim();
  const defaultLocale = String(formData.get("default_locale") ?? "").trim();
  const timezone = String(formData.get("timezone") ?? "").trim();
  const preferredLocaleRaw = String(formData.get("preferred_locale") ?? "").trim();

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("complete_center_setup", {
    p_name: name,
    p_default_locale: defaultLocale,
    p_timezone: timezone,
    p_preferred_locale: preferredLocaleRaw || undefined,
  });

  if (error) {
    return { ok: false, error: mapCompleteCenterSetupError(error.message) };
  }

  const allowsNormalUse =
    data &&
    typeof data === "object" &&
    !Array.isArray(data) &&
    (data as { allows_normal_use?: boolean }).allows_normal_use === true;

  if (preferredLocaleRaw && isValidLocale(preferredLocaleRaw)) {
    const cookieStore = await cookies();
    cookieStore.set(LOCALE_COOKIE, preferredLocaleRaw as Locale, {
      path: "/",
      sameSite: "lax",
      maxAge: 60 * 60 * 24 * 365,
    });
  }

  revalidatePath("/", "layout");

  const { data: commercialAccess } = await supabase.rpc("fetch_session_commercial_access");
  const sessionAccess = parseSessionCommercialAccess(commercialAccess);
  if (!allowsNormalUse && sessionAccess.allows_normal_use !== true) {
    redirect(resolveAuthenticatedLandingPath(sessionAccess));
  }

  redirect(resolveAuthenticatedLandingPath(sessionAccess));
}
