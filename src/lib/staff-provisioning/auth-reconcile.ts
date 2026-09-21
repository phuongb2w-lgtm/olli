import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "@/types/database";
import {
  AUTH_RECONCILIATION_PER_PAGE,
  MAX_AUTH_RECONCILIATION_PAGES,
  PROVISIONING_METADATA_KEY,
} from "@/lib/staff-provisioning/constants";

export type CorrelatedAuthUser = {
  id: string;
  email: string | undefined;
};

function normalizeEmail(email: string | undefined): string | null {
  if (!email) return null;
  return email.trim().toLowerCase();
}

function metadataMatchesRequest(
  metadata: Record<string, unknown> | undefined,
  requestId: string,
): boolean {
  const value = metadata?.[PROVISIONING_METADATA_KEY];
  return typeof value === "string" && value === requestId;
}

/** Bounded listUsers scan for Auth user correlated to provisioning request. */
export async function findAuthUserByProvisioningRequest(
  admin: SupabaseClient<Database>,
  requestId: string,
  normalizedEmail: string,
): Promise<{ user: CorrelatedAuthUser | null; exhausted: boolean }> {
  for (let page = 1; page <= MAX_AUTH_RECONCILIATION_PAGES; page += 1) {
    const { data, error } = await admin.auth.admin.listUsers({
      page,
      perPage: AUTH_RECONCILIATION_PER_PAGE,
    });

    if (error) {
      throw new Error(`auth_provisioning_failed:${error.message}`);
    }

    const users = data.users ?? [];
    for (const user of users) {
      if (!metadataMatchesRequest(user.user_metadata as Record<string, unknown>, requestId)) {
        continue;
      }
      const emailNorm = normalizeEmail(user.email);
      if (emailNorm !== normalizedEmail) {
        continue;
      }
      return { user: { id: user.id, email: user.email }, exhausted: false };
    }

    if (users.length < AUTH_RECONCILIATION_PER_PAGE) {
      return { user: null, exhausted: true };
    }
  }

  return { user: null, exhausted: false };
}

export async function verifyAuthUserCorrelation(
  admin: SupabaseClient<Database>,
  authUserId: string,
  requestId: string,
  normalizedEmail: string,
): Promise<boolean> {
  const { data, error } = await admin.auth.admin.getUserById(authUserId);
  if (error || !data.user) {
    return false;
  }
  const user = data.user;
  if (!metadataMatchesRequest(user.user_metadata as Record<string, unknown>, requestId)) {
    return false;
  }
  return normalizeEmail(user.email) === normalizedEmail;
}
