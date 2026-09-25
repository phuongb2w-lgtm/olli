"use server";

import { revalidatePath } from "next/cache";
import { getCurrentAppUser } from "@/lib/auth/get-identity-state";
import { requireCenterAccountAdmin } from "@/lib/auth/require-center-account-admin";
import { enforceStaffLifecycleRateLimit } from "@/lib/rate-limit/enforce";
import { mapLifecycleError, type StaffLifecycleErrorCode } from "@/lib/staff-lifecycle/errors";
import { STAFF_CANONICAL_ROLES, type StaffCanonicalRole } from "@/lib/staff-provisioning/constants";
import { createClient } from "@/lib/supabase/server";

export type StaffLifecycleResult =
  | { ok: true }
  | { ok: false; error: StaffLifecycleErrorCode };

function isStaffRole(value: string): value is StaffCanonicalRole {
  return (STAFF_CANONICAL_ROLES as readonly string[]).includes(value);
}

function mapRpcError(message: string | undefined): StaffLifecycleErrorCode {
  return mapLifecycleError(message ?? "");
}

async function requireOwnerSession(): Promise<StaffLifecycleResult | null> {
  const denial = await requireCenterAccountAdmin();
  if (denial) {
    return { ok: false, error: denial };
  }
  return null;
}

async function requireOwnerSessionWithRateLimit(): Promise<StaffLifecycleResult | null> {
  const denied = await requireOwnerSession();
  if (denied) {
    return denied;
  }
  const appUser = await getCurrentAppUser();
  if (!appUser) {
    return { ok: false, error: "not_authenticated" };
  }
  const decision = await enforceStaffLifecycleRateLimit({
    organizationId: appUser.organizationId,
    actorAppUserId: appUser.appUserId,
  });
  if (!decision.allowed) {
    return { ok: false, error: "rate_limited" };
  }
  return null;
}

export async function changeStaffRole(input: {
  appUserId: string;
  canonicalRole: string;
}): Promise<StaffLifecycleResult> {
  const denied = await requireOwnerSessionWithRateLimit();
  if (denied) return denied;
  if (!isStaffRole(input.canonicalRole)) {
    return { ok: false, error: "invalid_role" };
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("assign_canonical_staff_role", {
    p_target_user_id: input.appUserId,
    p_canonical_code: input.canonicalRole,
  });

  if (error) {
    return { ok: false, error: mapRpcError(error.message) };
  }

  revalidatePath("/users");
  return { ok: true };
}

export async function suspendStaff(input: { appUserId: string }): Promise<StaffLifecycleResult> {
  const denied = await requireOwnerSessionWithRateLimit();
  if (denied) return denied;

  const supabase = await createClient();
  const { error } = await supabase.rpc("suspend_staff_member", {
    p_target_user_id: input.appUserId,
  });

  if (error) {
    return { ok: false, error: mapRpcError(error.message) };
  }

  revalidatePath("/users");
  return { ok: true };
}

export async function reactivateStaff(input: { appUserId: string }): Promise<StaffLifecycleResult> {
  const denied = await requireOwnerSessionWithRateLimit();
  if (denied) return denied;

  const supabase = await createClient();
  const { error } = await supabase.rpc("reactivate_staff_member", {
    p_target_user_id: input.appUserId,
  });

  if (error) {
    return { ok: false, error: mapRpcError(error.message) };
  }

  revalidatePath("/users");
  return { ok: true };
}

export async function removeStaff(input: { appUserId: string }): Promise<StaffLifecycleResult> {
  const denied = await requireOwnerSessionWithRateLimit();
  if (denied) return denied;

  const supabase = await createClient();
  const { error } = await supabase.rpc("remove_staff_from_center", {
    p_target_user_id: input.appUserId,
  });

  if (error) {
    return { ok: false, error: mapRpcError(error.message) };
  }

  revalidatePath("/users");
  return { ok: true };
}

export async function restoreRemovedStaff(input: {
  appUserId: string;
  canonicalRole: string;
}): Promise<StaffLifecycleResult> {
  const denied = await requireOwnerSessionWithRateLimit();
  if (denied) return denied;
  if (!isStaffRole(input.canonicalRole)) {
    return { ok: false, error: "invalid_role" };
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("restore_removed_staff", {
    p_target_user_id: input.appUserId,
    p_canonical_role: input.canonicalRole,
  });

  if (error) {
    return { ok: false, error: mapRpcError(error.message) };
  }

  revalidatePath("/users");
  return { ok: true };
}
