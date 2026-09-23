import { redirect } from "next/navigation";
import { StaffCommercialAccessPanel } from "@/components/commercial/staff-commercial-access-panel";
import { SUBSCRIPTION_STATUS_PATH } from "@/lib/auth/commercial-access-paths";
import { getIdentityState } from "@/lib/auth/get-identity-state";

export const dynamic = "force-dynamic";

export default async function CommercialAccessPage() {
  const identity = await getIdentityState();

  if (identity.kind === "commercially_restricted" && identity.isPrimaryOwner) {
    redirect(SUBSCRIPTION_STATUS_PATH);
  }

  const subscriptionStatus =
    identity.kind === "commercially_restricted" ? identity.subscriptionStatus : "missing";

  return <StaffCommercialAccessPanel subscriptionStatus={subscriptionStatus} />;
}
