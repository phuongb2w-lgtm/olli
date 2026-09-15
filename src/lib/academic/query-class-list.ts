import type { SupabaseClient } from "@supabase/supabase-js";
import type { ClassStatus } from "@/lib/academic/constants";
import {
  clampPage,
  isSearchActive,
  parseClassListParams,
  type ClassListParams,
} from "@/lib/academic/parse-list-params";
import { buildSearchPatterns } from "@/lib/students/search-patterns";

export type ClassListItem = {
  id: string;
  name: string;
  status: ClassStatus;
  termStartDate: string | null;
  termEndDate: string | null;
  capacity: number | null;
  courseId: string;
  courseCode: string;
  courseName: string;
};

export type ClassListResult = {
  items: ClassListItem[];
  totalCount: number;
  params: ClassListParams;
};

type ClassRow = {
  id: string;
  name: string;
  status: string;
  term_start_date: string | null;
  term_end_date: string | null;
  capacity: number | null;
  course_id: string;
};

type CourseRow = {
  id: string;
  code: string;
  name: string;
};

export async function queryClassList(
  supabase: SupabaseClient,
  rawParams: Record<string, string | string[] | undefined>,
): Promise<{ result: ClassListResult | null; error: boolean }> {
  const params = parseClassListParams(rawParams);

  try {
    const matchingIds = await resolveMatchingClassIds(supabase, params);
    if (matchingIds !== null && matchingIds.size === 0) {
      return {
        result: { items: [], totalCount: 0, params: { ...params, page: 1 } },
        error: false,
      };
    }

    let countQuery = supabase.from("class").select("*", { count: "exact", head: true });
    countQuery = applyFilters(countQuery, params, matchingIds);
    const { count, error: countError } = await countQuery;
    if (countError) return { result: null, error: true };

    const totalCount = count ?? 0;
    const safePage = clampPage(params.page, totalCount, params.pageSize);
    const from = (safePage - 1) * params.pageSize;
    const to = from + params.pageSize - 1;

    let dataQuery = supabase
      .from("class")
      .select("id, name, status, term_start_date, term_end_date, capacity, course_id");
    dataQuery = applyFilters(dataQuery, params, matchingIds);

    const { data, error } = await dataQuery
      .order("name", { ascending: true })
      .order("id", { ascending: true })
      .range(from, to);

    if (error) return { result: null, error: true };

    const rows = (data ?? []) as ClassRow[];
    const courseIds = [...new Set(rows.map((r) => r.course_id))];
    const courseById = new Map<string, CourseRow>();

    if (courseIds.length > 0) {
      const { data: courses, error: courseError } = await supabase
        .from("course")
        .select("id, code, name")
        .in("id", courseIds);
      if (courseError) return { result: null, error: true };
      for (const course of courses ?? []) {
        courseById.set(course.id, course as CourseRow);
      }
    }

    const items: ClassListItem[] = rows
      .map((row) => {
        const course = courseById.get(row.course_id);
        if (!course) return null;
        return {
          id: row.id,
          name: row.name,
          status: row.status as ClassStatus,
          termStartDate: row.term_start_date,
          termEndDate: row.term_end_date,
          capacity: row.capacity,
          courseId: row.course_id,
          courseCode: course.code,
          courseName: course.name,
        };
      })
      .filter((item): item is ClassListItem => item !== null);

    return {
      result: {
        items,
        totalCount,
        params: { ...params, page: safePage },
      },
      error: false,
    };
  } catch {
    return { result: null, error: true };
  }
}

function applyFilters<
  Q extends {
    eq: (column: string, value: string) => Q;
    in: (column: string, values: string[]) => Q;
  },
>(query: Q, params: ClassListParams, matchingIds: Set<string> | null): Q {
  let next = query;
  if (params.status !== "all") {
    next = next.eq("status", params.status);
  }
  if (params.course) {
    next = next.eq("course_id", params.course);
  }
  if (matchingIds !== null) {
    next = next.in("id", [...matchingIds]);
  }
  return next;
}

async function resolveMatchingClassIds(
  supabase: SupabaseClient,
  params: ClassListParams,
): Promise<Set<string> | null> {
  if (!isSearchActive(params.q)) return null;

  const ids = new Set<string>();
  const patterns = buildSearchPatterns(params.q);

  for (const pattern of patterns) {
    let query = supabase.from("class").select("id").ilike("name", pattern);
    if (params.status !== "all") query = query.eq("status", params.status);
    if (params.course) query = query.eq("course_id", params.course);
    const { data, error } = await query;
    if (error) throw error;
    for (const row of data ?? []) ids.add(row.id);
  }

  for (const pattern of patterns) {
    const { data: courses, error: courseError } = await supabase
      .from("course")
      .select("id")
      .or(`code.ilike.${pattern},name.ilike.${pattern}`);
    if (courseError) throw courseError;
    if ((courses ?? []).length === 0) continue;

    const courseIds = courses!.map((c) => c.id);
    let linkQuery = supabase.from("class").select("id").in("course_id", courseIds);
    if (params.status !== "all") linkQuery = linkQuery.eq("status", params.status);
    if (params.course) linkQuery = linkQuery.eq("course_id", params.course);
    const { data: classMatches, error: classError } = await linkQuery;
    if (classError) throw classError;
    for (const row of classMatches ?? []) ids.add(row.id);
  }

  return ids;
}

export async function fetchCoursesForFilter(supabase: SupabaseClient): Promise<CourseRow[]> {
  const { data, error } = await supabase
    .from("course")
    .select("id, code, name")
    .order("code", { ascending: true });
  if (error) throw error;
  return (data ?? []) as CourseRow[];
}
