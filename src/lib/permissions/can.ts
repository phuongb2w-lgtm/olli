import { createClient } from "@/lib/supabase/server";
import type { PermissionCode } from "@/lib/permissions/codes";

export type { PermissionCode };

/** UX-only permission check; RLS remains authoritative. */
export async function can(permissionCode: PermissionCode): Promise<boolean> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("has_permission", {
    p_code: permissionCode,
  });

  if (error) {
    return false;
  }

  return Boolean(data);
}
