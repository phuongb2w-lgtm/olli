import type { SupabaseClient } from "@supabase/supabase-js";
import type { CourseStatus } from "@/lib/academic/constants";
import {
  clampPage,
  parseCourseListParams,
  type CourseListParams,
} from "@/lib/academic/parse-list-params";

export type CourseListItem = {
  id: string;
  code: string;
  name: string;
  levelCode: string | null;
  status: CourseStatus;
};

export type CourseListResult = {
  items: CourseListItem[];
  totalCount: number;
  params: CourseListParams;
};

export async function queryCourseList(
  supabase: SupabaseClient,
  rawParams: Record<string, string | string[] | undefined>,
): Promise<{ result: CourseListResult | null; error: boolean }> {
  const params = parseCourseListParams(rawParams);

  try {
    const { count, error: countError } = await supabase
      .from("course")
      .select("*", { count: "exact", head: true });
    if (countError) return { result: null, error: true };

    const totalCount = count ?? 0;
    const safePage = clampPage(params.page, totalCount, params.pageSize);
    const from = (safePage - 1) * params.pageSize;
    const to = from + params.pageSize - 1;

    const { data, error } = await supabase
      .from("course")
      .select("id, code, name, level_code, status")
      .order("code", { ascending: true })
      .order("id", { ascending: true })
      .range(from, to);

    if (error) return { result: null, error: true };

    const items: CourseListItem[] = (data ?? []).map((row) => ({
      id: row.id,
      code: row.code,
      name: row.name,
      levelCode: row.level_code,
      status: row.status as CourseStatus,
    }));

    return {
      result: { items, totalCount, params: { ...params, page: safePage } },
      error: false,
    };
  } catch {
    return { result: null, error: true };
  }
}

export async function fetchActiveCourses(supabase: SupabaseClient): Promise<CourseListItem[]> {
  const { data, error } = await supabase
    .from("course")
    .select("id, code, name, level_code, status")
    .eq("status", "active")
    .order("code", { ascending: true });
  if (error) throw error;
  return (data ?? []).map((row) => ({
    id: row.id,
    code: row.code,
    name: row.name,
    levelCode: row.level_code,
    status: row.status as CourseStatus,
  }));
}
