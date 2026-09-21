"use server";

import { getCurrentAppUser } from "@/lib/auth/get-identity-state";
import { STAFF_CANONICAL_ROLES, type StaffCanonicalRole } from "@/lib/staff-provisioning/constants";
import {
  orchestrateStaffProvisioning,
  type ProvisionStaffResult,
} from "@/lib/staff-provisioning/orchestrate";
import { createClient } from "@/lib/supabase/server";

export type ProvisionStaffAccountState = ProvisionStaffResult;

function isStaffRole(value: string): value is StaffCanonicalRole {
  return (STAFF_CANONICAL_ROLES as readonly string[]).includes(value);
}

export async function provisionStaffAccount(input: {
  email: string;
  displayName: string;
  canonicalRole: string;
  idempotencyKey: string;
  preferredLocale?: "vi" | "en";
}): Promise<ProvisionStaffAccountState> {
  const appUser = await getCurrentAppUser();
  if (!appUser) {
    return { ok: false, error: "not_authenticated" };
  }

  if (!isStaffRole(input.canonicalRole)) {
    return { ok: false, error: "invalid_role" };
  }

  const supabase = await createClient();
  return orchestrateStaffProvisioning(supabase, {
    email: input.email,
    displayName: input.displayName,
    canonicalRole: input.canonicalRole,
    idempotencyKey: input.idempotencyKey,
    preferredLocale: input.preferredLocale,
  });
}
