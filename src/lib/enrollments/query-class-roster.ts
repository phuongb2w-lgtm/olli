import type { SupabaseClient } from "@supabase/supabase-js";
import type { EnrollmentStatus } from "@/lib/enrollments/constants";
import {
  clampPage,
  isRosterSearchActive,
  parseRosterListParams,
  statusFilterToDbStatuses,
  type RosterListParams,
} from "@/lib/enrollments/parse-roster-params";
import { formatPersonName } from "@/lib/students/format-person-name";
import { buildSearchPatterns } from "@/lib/students/search-patterns";

export type RosterListItem = {
  enrollmentId: string;
  studentId: string;
  studentName: string;
  studentCode: string | null;
  status: EnrollmentStatus;
  startDate: string;
  endDate: string | null;
};

export type RosterListResult = {
  items: RosterListItem[];
  totalCount: number;
  params: RosterListParams;
};

type EnrollmentRow = {
  id: string;
  student_id: string;
  status: string;
  start_date: string;
  end_date: string | null;
};

type StudentRow = {
  id: string;
  given_name: string;
  family_name: string;
  student_code: string | null;
};

export async function queryClassRoster(
  supabase: SupabaseClient,
  classId: string,
  rawParams: Record<string, string | string[] | undefined>,
): Promise<{ result: RosterListResult | null; error: boolean }> {
  const params = parseRosterListParams(rawParams);

  try {
    const matchingEnrollmentIds = await resolveMatchingEnrollmentIds(
      supabase,
      classId,
      params,
    );

    if (matchingEnrollmentIds !== null && matchingEnrollmentIds.size === 0) {
      return {
        result: { items: [], totalCount: 0, params: { ...params, page: 1 } },
        error: false,
      };
    }

    let countQuery = supabase
      .from("enrollment")
      .select("*", { count: "exact", head: true })
      .eq("class_id", classId);
    countQuery = applyRosterFilters(countQuery, params, matchingEnrollmentIds);
    const { count, error: countError } = await countQuery;
    if (countError) return { result: null, error: true };

    const totalCount = count ?? 0;
    const safePage = clampPage(params.page, totalCount, params.pageSize);
    const from = (safePage - 1) * params.pageSize;
    const to = from + params.pageSize - 1;

    let dataQuery = supabase
      .from("enrollment")
      .select("id, student_id, status, start_date, end_date")
      .eq("class_id", classId);
    dataQuery = applyRosterFilters(dataQuery, params, matchingEnrollmentIds);

    const { data, error } = await dataQuery
      .order("start_date", { ascending: false })
      .order("id", { ascending: false })
      .range(from, to);

    if (error) return { result: null, error: true };

    const rows = (data ?? []) as EnrollmentRow[];
    const studentIds = [...new Set(rows.map((r) => r.student_id))];
    const studentById = new Map<string, StudentRow>();

    if (studentIds.length > 0) {
      const { data: students, error: studentError } = await supabase
        .from("student")
        .select("id, given_name, family_name, student_code")
        .in("id", studentIds);
      if (studentError) return { result: null, error: true };
      for (const student of students ?? []) {
        studentById.set(student.id, student as StudentRow);
      }
    }

    const items: RosterListItem[] = rows
      .map((row) => {
        const student = studentById.get(row.student_id);
        if (!student) return null;
        return {
          enrollmentId: row.id,
          studentId: row.student_id,
          studentName: formatPersonName(student.family_name, student.given_name),
          studentCode: student.student_code,
          status: row.status as EnrollmentStatus,
          startDate: row.start_date,
          endDate: row.end_date,
        };
      })
      .filter((item): item is RosterListItem => item !== null);

    return {
      result: { items, totalCount, params: { ...params, page: safePage } },
      error: false,
    };
  } catch {
    return { result: null, error: true };
  }
}

function applyRosterFilters<
  Q extends {
    eq: (column: string, value: string) => Q;
    in: (column: string, values: string[]) => Q;
  },
>(query: Q, params: RosterListParams, matchingIds: Set<string> | null): Q {
  let next = query;
  const statuses = statusFilterToDbStatuses(params.status);
  if (statuses) next = next.in("status", statuses);
  if (matchingIds !== null) next = next.in("id", [...matchingIds]);
  return next;
}

async function resolveMatchingEnrollmentIds(
  supabase: SupabaseClient,
  classId: string,
  params: RosterListParams,
): Promise<Set<string> | null> {
  if (!isRosterSearchActive(params.q)) return null;

  const enrollmentIds = new Set<string>();
  const patterns = buildSearchPatterns(params.q);
  const statuses = statusFilterToDbStatuses(params.status);

  for (const pattern of patterns) {
    for (const column of ["given_name", "family_name"] as const) {
      const { data: students, error } = await supabase
        .from("student")
        .select("id")
        .ilike(column, pattern);
      if (error) throw error;
      if ((students ?? []).length === 0) continue;

      const studentIds = students!.map((s) => s.id);
      let linkQuery = supabase
        .from("enrollment")
        .select("id")
        .eq("class_id", classId)
        .in("student_id", studentIds);
      if (statuses) linkQuery = linkQuery.in("status", statuses);
      const { data: matches, error: linkError } = await linkQuery;
      if (linkError) throw linkError;
      for (const row of matches ?? []) enrollmentIds.add(row.id);
    }

    const { data: codeMatches, error: codeError } = await supabase
      .from("student")
      .select("id")
      .ilike("student_code", pattern);
    if (codeError) throw codeError;
    if ((codeMatches ?? []).length > 0) {
      const studentIds = codeMatches!.map((s) => s.id);
      let linkQuery = supabase
        .from("enrollment")
        .select("id")
        .eq("class_id", classId)
        .in("student_id", studentIds);
      if (statuses) linkQuery = linkQuery.in("status", statuses);
      const { data: matches, error: linkError } = await linkQuery;
      if (linkError) throw linkError;
      for (const row of matches ?? []) enrollmentIds.add(row.id);
    }
  }

  return enrollmentIds;
}
