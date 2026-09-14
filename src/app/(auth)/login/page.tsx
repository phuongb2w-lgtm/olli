import { redirect } from "next/navigation";
import { LoginForm } from "@/components/login-form";
import { getIdentityState } from "@/lib/auth/get-identity-state";

export default async function LoginPage() {
  const identity = await getIdentityState();
  if (identity.kind === "active") {
    redirect("/");
  }

  return <LoginForm />;
}
