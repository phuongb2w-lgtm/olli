"use server";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import {
  COMMERCIAL_ACCESS_PATH,
  SUBSCRIPTION_STATUS_PATH,
} from "@/lib/auth/commercial-access-paths";
import { parseSessionCommercialAccess } from "@/lib/auth/session-commercial-access";
import { isValidLocale, LOCALE_COOKIE } from "@/i18n/config";
import { cookies } from "next/headers";

export type SignInState = {
  error?: "invalid_credentials" | "network" | "unknown";
};

export async function signIn(
  _prevState: SignInState,
  formData: FormData,
): Promise<SignInState> {
  const email = String(formData.get("email") ?? "").trim();
  const password = String(formData.get("password") ?? "");

  if (!email || !password) {
    return { error: "invalid_credentials" };
  }

  const supabase = await createClient();
  const { error } = await supabase.auth.signInWithPassword({ email, password });

  if (error) {
    if (error.message.toLowerCase().includes("invalid")) {
      return { error: "invalid_credentials" };
    }
    return { error: "network" };
  }

  const { data: appUser } = await supabase
    .from("app_user")
    .select("preferred_locale")
    .eq("email", email)
    .maybeSingle();

  if (appUser?.preferred_locale && isValidLocale(appUser.preferred_locale)) {
    const cookieStore = await cookies();
    cookieStore.set(LOCALE_COOKIE, appUser.preferred_locale, {
      path: "/",
      sameSite: "lax",
      maxAge: 60 * 60 * 24 * 365,
    });
  }

  const { data: commercialAccess, error: commercialError } = await supabase.rpc(
    "fetch_session_commercial_access",
  );
  if (!commercialError) {
    const sessionAccess = parseSessionCommercialAccess(commercialAccess);
    if (sessionAccess.allows_normal_use === false) {
      redirect(
        sessionAccess.is_primary_owner === true
          ? SUBSCRIPTION_STATUS_PATH
          : COMMERCIAL_ACCESS_PATH,
      );
    }
  }

  redirect("/");
}

export async function signOut() {
  const supabase = await createClient();
  await supabase.auth.signOut();
  redirect("/login");
}
