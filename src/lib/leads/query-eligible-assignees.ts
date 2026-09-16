import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "@/types/database";

type DbClient = SupabaseClient<Database>;

export type EligibleAssignee = {
  userId: string;
  displayName: string;
};

export async function queryEligibleAssignees(
  supabase: DbClient,
): Promise<{ assignees: EligibleAssignee[]; error: boolean }> {
  const { data, error } = await supabase.rpc("list_eligible_lead_assignees");

  if (error) {
    return { assignees: [], error: true };
  }

  return {
    assignees: (data ?? []).map((row) => ({
      userId: row.user_id,
      displayName: row.display_name,
    })),
    error: false,
  };
}
