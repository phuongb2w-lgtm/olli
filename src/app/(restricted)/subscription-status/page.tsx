import { redirect } from "next/navigation";
import { OwnerSubscriptionStatusPanel } from "@/components/commercial/owner-subscription-status-panel";
import { parseOwnerCommercialStatus } from "@/lib/auth/session-commercial-access";
import { COMMERCIAL_ACCESS_PATH } from "@/lib/auth/commercial-access-paths";
import { getIdentityState } from "@/lib/auth/get-identity-state";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

export default async function SubscriptionStatusPage() {
  const identity = await getIdentityState();

  if (identity.kind === "commercially_restricted" && !identity.isPrimaryOwner) {
    redirect(COMMERCIAL_ACCESS_PATH);
  }

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("fetch_owner_commercial_status");

  if (error) {
    throw error;
  }

  return <OwnerSubscriptionStatusPanel status={parseOwnerCommercialStatus(data)} />;
}
