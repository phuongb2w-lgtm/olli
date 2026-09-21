import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "@/types/database";

export type AppUserIdentityLabel = {
  userId: string;
  displayName: string;
  membershipStatus: string;
};

/** Resolves same-org display names without exposing full app_user rows (email, etc.). */
export async function fetchAppUserIdentityLabels(
  supabase: SupabaseClient<Database>,
  userIds: string[],
): Promise<Map<string, AppUserIdentityLabel>> {
  const unique = [...new Set(userIds.filter(Boolean))];
  const result = new Map<string, AppUserIdentityLabel>();
  if (unique.length === 0) {
    return result;
  }

  const { data, error } = await supabase.rpc("fetch_app_user_identity_labels", {
    p_user_ids: unique,
  });

  if (error) {
    throw error;
  }

  for (const row of data ?? []) {
    result.set(row.user_id, {
      userId: row.user_id,
      displayName: row.display_name,
      membershipStatus: row.membership_status,
    });
  }

  return result;
}
