import type { SupabaseClient } from "@supabase/supabase-js";

const DEFAULT_TIMEZONE = "Asia/Ho_Chi_Minh";

export async function fetchOrganizationTimezone(
  supabase: SupabaseClient,
): Promise<string> {
  const { data, error } = await supabase
    .from("organization")
    .select("timezone")
    .maybeSingle();

  if (error || !data?.timezone) {
    return DEFAULT_TIMEZONE;
  }

  return data.timezone;
}
