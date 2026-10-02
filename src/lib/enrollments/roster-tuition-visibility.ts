import type { SupabaseClient } from "@supabase/supabase-js";

/** Mirrors get_enrollment_operational_tuition_status teacher-only gate for roster UX. */
export async function canViewRosterOperationalTuition(
  supabase: SupabaseClient,
): Promise<boolean> {
  const { data, error } = await supabase.rpc("can_view_roster_operational_tuition");
  if (error) return false;
  return Boolean(data);
}
