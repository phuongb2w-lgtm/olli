import type { SupabaseClient } from "@supabase/supabase-js";
import { MIN_STUDENT_SEARCH_LENGTH } from "@/lib/enrollments/constants";
import { formatPersonName } from "@/lib/students/format-person-name";
import { buildSearchPatterns } from "@/lib/students/search-patterns";

export type StudentSearchItem = {
  id: string;
  name: string;
  studentCode: string | null;
  status: string;
};

export async function searchStudentsForEnrollment(
  supabase: SupabaseClient,
  rawQuery: string,
  limit = 20,
): Promise<StudentSearchItem[]> {
  const query = rawQuery.trim();
  if (query.length < MIN_STUDENT_SEARCH_LENGTH) return [];

  const ids = new Set<string>();
  const patterns = buildSearchPatterns(query);

  for (const column of ["given_name", "family_name"] as const) {
    for (const pattern of patterns) {
      const { data, error } = await supabase.from("student").select("id").ilike(column, pattern);
      if (error) throw error;
      for (const row of data ?? []) ids.add(row.id);
    }
  }

  for (const pattern of patterns) {
    const { data, error } = await supabase
      .from("student")
      .select("id")
      .ilike("student_code", pattern);
    if (error) throw error;
    for (const row of data ?? []) ids.add(row.id);
  }

  if (ids.size === 0) return [];

  const { data, error } = await supabase
    .from("student")
    .select("id, given_name, family_name, student_code, status")
    .in("id", [...ids])
    .order("family_name", { ascending: true })
    .order("given_name", { ascending: true })
    .limit(limit);

  if (error) throw error;

  return (data ?? []).map((row) => ({
    id: row.id,
    name: formatPersonName(row.family_name, row.given_name),
    studentCode: row.student_code,
    status: row.status,
  }));
}
