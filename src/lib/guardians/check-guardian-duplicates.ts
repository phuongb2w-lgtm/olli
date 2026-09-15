import type { SupabaseClient } from "@supabase/supabase-js";
import { normalizedEmailKey } from "@/lib/guardians/normalize-guardian-fields";
import { normalizePhoneDigits } from "@/lib/students/normalize-phone";

export function isPrimaryContactUniqueViolation(error: { code?: string } | null): boolean {
  return error?.code === "23505";
}

export async function hasGuardianEmailDuplicate(
  supabase: SupabaseClient,
  email: string,
  excludeGuardianId?: string,
): Promise<boolean> {
  const key = normalizedEmailKey(email);
  const { data, error } = await supabase.from("guardian").select("id, email").not("email", "is", null);
  if (error) throw error;

  return (data ?? []).some((row) => {
    if (excludeGuardianId && row.id === excludeGuardianId) return false;
    if (!row.email) return false;
    return normalizedEmailKey(row.email) === key;
  });
}

export async function hasGuardianPhoneDuplicate(
  supabase: SupabaseClient,
  phone: string,
  excludeGuardianId?: string,
): Promise<boolean> {
  const digits = normalizePhoneDigits(phone);
  if (digits.length < 4) return false;

  const { data, error } = await supabase.from("guardian").select("id, phone").not("phone", "is", null);
  if (error) throw error;

  return (data ?? []).some((row) => {
    if (excludeGuardianId && row.id === excludeGuardianId) return false;
    if (!row.phone) return false;
    return normalizePhoneDigits(row.phone) === digits;
  });
}
