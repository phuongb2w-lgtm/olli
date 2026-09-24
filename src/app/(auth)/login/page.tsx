import { redirect } from "next/navigation";
import { LoginForm } from "@/components/login-form";
import { resolveAuthenticatedLandingPath } from "@/lib/auth/resolve-authenticated-landing";
import { getIdentityState } from "@/lib/auth/get-identity-state";
import { parseSessionCommercialAccess } from "@/lib/auth/session-commercial-access";
import { createClient } from "@/lib/supabase/server";

export default async function LoginPage() {
  const identity = await getIdentityState();
  if (identity.kind === "active" || identity.kind === "commercially_restricted") {
    const supabase = await createClient();
    const { data: commercialAccess } = await supabase.rpc("fetch_session_commercial_access");
    redirect(resolveAuthenticatedLandingPath(parseSessionCommercialAccess(commercialAccess)));
  }

  return <LoginForm />;
}
