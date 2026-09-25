import { redirect } from "next/navigation";
import { LoginForm } from "@/components/login-form";
import { resolveAuthenticatedLandingPath } from "@/lib/auth/resolve-authenticated-landing";
import { getIdentityState } from "@/lib/auth/get-identity-state";
import { parseSessionCommercialAccess } from "@/lib/auth/session-commercial-access";
import { createClient } from "@/lib/supabase/server";

type Props = {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
};

export default async function LoginPage({ searchParams }: Props) {
  const rawParams = await searchParams;
  const errorParam = rawParams.error;
  const callbackError =
    errorParam === "auth_callback" ||
    (Array.isArray(errorParam) && errorParam.includes("auth_callback"));
  const identity = await getIdentityState();
  if (identity.kind === "active" || identity.kind === "commercially_restricted") {
    const supabase = await createClient();
    const { data: commercialAccess } = await supabase.rpc("fetch_session_commercial_access");
    redirect(resolveAuthenticatedLandingPath(parseSessionCommercialAccess(commercialAccess)));
  }

  return <LoginForm callbackError={callbackError} />;
}
