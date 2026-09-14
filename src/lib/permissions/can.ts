import { createClient } from "@/lib/supabase/server";

export type PermissionCode =
  | "student.read"
  | "student.create"
  | "student.update"
  | "organization.read"
  | string;

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
