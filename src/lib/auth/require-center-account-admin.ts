import "server-only";

import { getCurrentAppUser } from "@/lib/auth/get-identity-state";
import { can } from "@/lib/permissions/can";

export type CenterAccountAdminDenial = "not_authenticated" | "not_primary_owner";

/** UX gate aligned with `/users`; DB RPC remains authoritative. */
export async function requireCenterAccountAdmin(): Promise<CenterAccountAdminDenial | null> {
  const appUser = await getCurrentAppUser();
  if (!appUser) {
    return "not_authenticated";
  }
  if (!(await can("center_account.manage"))) {
    return "not_primary_owner";
  }
  return null;
}
