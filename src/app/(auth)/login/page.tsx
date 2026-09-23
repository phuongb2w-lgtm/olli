import { redirect } from "next/navigation";
import { LoginForm } from "@/components/login-form";
import { commercialRestrictedPath } from "@/lib/auth/commercial-access-paths";
import { getIdentityState } from "@/lib/auth/get-identity-state";

export default async function LoginPage() {
  const identity = await getIdentityState();
  if (identity.kind === "active") {
    redirect("/");
  }
  if (identity.kind === "commercially_restricted") {
    redirect(commercialRestrictedPath(identity));
  }

  return <LoginForm />;
}
