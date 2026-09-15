import type { SupabaseClient } from "@supabase/supabase-js";
import { MIN_GUARDIAN_SEARCH_LENGTH } from "@/lib/guardians/constants";
import { formatPersonName } from "@/lib/students/format-person-name";
import { escapeIlike } from "@/lib/students/escape-ilike";
import { buildSearchPatterns } from "@/lib/students/search-patterns";
import { normalizePhoneDigits } from "@/lib/students/normalize-phone";

export type GuardianSearchItem = {
  id: string;
  name: string;
  phone: string | null;
  email: string | null;
  status: string;
};

export async function searchGuardians(
  supabase: SupabaseClient,
  rawQuery: string,
  limit = 20,
): Promise<GuardianSearchItem[]> {
  const query = rawQuery.trim();
  if (query.length < MIN_GUARDIAN_SEARCH_LENGTH) {
    return [];
  }

  const ids = new Set<string>();
  const patterns = buildSearchPatterns(query);

  for (const column of ["given_name", "family_name"] as const) {
    for (const pattern of patterns) {
      const { data, error } = await supabase.from("guardian").select("id").ilike(column, pattern);
      if (error) throw error;
      for (const row of data ?? []) ids.add(row.id);
    }
  }

  const emailPattern = `*${escapeIlike(query.toLowerCase())}*`;
  const { data: emailMatches, error: emailError } = await supabase
    .from("guardian")
    .select("id")
    .ilike("email", emailPattern);
  if (emailError) throw emailError;
  for (const row of emailMatches ?? []) ids.add(row.id);

  const phoneDigits = normalizePhoneDigits(query);
  if (phoneDigits.length >= MIN_GUARDIAN_SEARCH_LENGTH) {
    const phonePattern = `*${escapeIlike(phoneDigits)}*`;
    const { data: phoneMatches, error: phoneError } = await supabase
      .from("guardian")
      .select("id")
      .ilike("phone", phonePattern);
    if (phoneError) throw phoneError;
    for (const row of phoneMatches ?? []) ids.add(row.id);
  }

  if (ids.size === 0) return [];

  const { data: guardians, error: loadError } = await supabase
    .from("guardian")
    .select("id, given_name, family_name, phone, email, status")
    .in("id", [...ids])
    .order("family_name", { ascending: true })
    .order("given_name", { ascending: true })
    .limit(limit);

  if (loadError) throw loadError;

  return (guardians ?? []).map((g) => ({
    id: g.id,
    name: formatPersonName(g.family_name, g.given_name),
    phone: g.phone,
    email: g.email,
    status: g.status,
  }));
}
