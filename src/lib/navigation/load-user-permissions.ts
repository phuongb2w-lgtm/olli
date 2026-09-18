import { createClient } from "@/lib/supabase/server";

/** Loads effective permission codes for the authenticated user. Backend-authoritative. */
export async function loadUserPermissions(): Promise<Set<string>> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("list_my_permissions");

  if (error || !Array.isArray(data)) {
    return new Set();
  }

  return new Set(
    data.filter((code): code is string => typeof code === "string"),
  );
}
