"use server";

import { revalidatePath } from "next/cache";
import { requireCenterAccountAdmin } from "@/lib/auth/require-center-account-admin";
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
  const denial = await requireCenterAccountAdmin();
  if (denial) {
    return { ok: false, error: denial };
  }

  if (!isStaffRole(input.canonicalRole)) {
    return { ok: false, error: "invalid_role" };
  }

  const supabase = await createClient();
  const result = await orchestrateStaffProvisioning(supabase, {
    email: input.email,
    displayName: input.displayName,
    canonicalRole: input.canonicalRole,
    idempotencyKey: input.idempotencyKey,
    preferredLocale: input.preferredLocale,
  });

  if (result.ok) {
    revalidatePath("/users");
  }

  return result;
}
