import type { SupabaseClient } from "@supabase/supabase-js";
import { escapeIlike } from "@/lib/students/escape-ilike";
import { buildSearchPatterns } from "@/lib/students/search-patterns";
import { formatPersonName } from "@/lib/students/format-person-name";
import { normalizePhoneDigits } from "@/lib/students/normalize-phone";
import {
  clampPage,
  isSearchActive,
  parseStudentListParams,
} from "@/lib/students/parse-list-params";
import type {
  StudentListItem,
  StudentListParams,
  StudentListResult,
  StudentStatus,
} from "@/lib/students/types";
import type { Database } from "@/types/database";

type DbClient = SupabaseClient<Database>;

type StudentRow = {
  id: string;
  given_name: string;
  family_name: string;
  student_code: string | null;
  status: string;
};

type PrimaryLinkRow = {
  student_id: string;
  created_at: string;
  guardian: {
    id: string;
    given_name: string;
    family_name: string;
    phone: string | null;
  } | null;
};

export type QueryStudentListOptions = {
  hasGuardianRead: boolean;
};

export async function queryStudentList(
  supabase: DbClient,
  rawParams: Record<string, string | string[] | undefined>,
  options: QueryStudentListOptions,
): Promise<{ result: StudentListResult | null; error: boolean }> {
  const params = parseStudentListParams(rawParams);

  try {
    const matchingIds = await resolveMatchingStudentIds(
      supabase,
      params,
      options.hasGuardianRead,
    );

    if (matchingIds !== null && matchingIds.size === 0) {
      return {
        result: {
          items: [],
          totalCount: 0,
          params: { ...params, page: 1 },
        },
        error: false,
      };
    }

    const { count, error: countError } = await applyStudentListFilters(
      supabase.from("student").select("*", { count: "exact", head: true }),
      params,
      matchingIds,
    );

    if (countError) {
      return { result: null, error: true };
    }

    const totalCount = count ?? 0;
    const safePage = clampPage(params.page, totalCount, params.pageSize);
    const from = (safePage - 1) * params.pageSize;
    const to = from + params.pageSize - 1;

    const { data, error } = await applyStudentListFilters(
      supabase.from("student").select("id, given_name, family_name, student_code, status"),
      params,
      matchingIds,
    )
      .order("family_name", { ascending: true })
      .order("given_name", { ascending: true })
      .order("id", { ascending: true })
      .range(from, to);

    if (error) {
      return { result: null, error: true };
    }

    const rows = (data ?? []) as StudentRow[];
    const primaryByStudent = options.hasGuardianRead
      ? await fetchPrimaryContacts(supabase, rows.map((row) => row.id))
      : new Map<string, PrimaryLinkRow["guardian"]>();

    const items: StudentListItem[] = rows.map((row) => {
      const guardian = primaryByStudent.get(row.id) ?? null;
      return {
        id: row.id,
        name: formatPersonName(row.family_name, row.given_name),
        studentCode: row.student_code,
        status: row.status as StudentStatus,
        primaryContact: guardian
          ? {
              id: guardian.id,
              name: formatPersonName(guardian.family_name, guardian.given_name),
              phone: guardian.phone,
            }
          : null,
      };
    });

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

function applyStudentListFilters<
  Q extends {
    eq: (column: string, value: string) => Q;
    in: (column: string, values: string[]) => Q;
  },
>(query: Q, params: StudentListParams, matchingIds: Set<string> | null): Q {
  let next = query;
  if (params.status !== "all") {
    next = next.eq("status", params.status);
  }
  if (matchingIds !== null) {
    next = next.in("id", [...matchingIds]);
  }
  return next;
}

async function resolveMatchingStudentIds(
  supabase: DbClient,
  params: StudentListParams,
  hasGuardianRead: boolean,
): Promise<Set<string> | null> {
  if (!isSearchActive(params.q)) {
    return null;
  }

  const ids = new Set<string>();
  const patterns = buildSearchPatterns(params.q);
  const studentMatches = await collectStudentIdsByPattern(
    supabase,
    patterns,
    params.status,
  );

  for (const id of studentMatches) {
    ids.add(id);
  }

  if (hasGuardianRead) {
    const guardianIds = await findMatchingGuardianIds(supabase, params.q.trim(), patterns);
    if (guardianIds.length > 0) {
      const { data: links, error: linkError } = await supabase
        .from("student_guardian")
        .select("student_id")
        .eq("status", "active")
        .in("guardian_id", guardianIds);

      if (linkError) {
        throw linkError;
      }

      for (const link of links ?? []) {
        ids.add(link.student_id);
      }
    }
  }

  return ids;
}

async function collectStudentIdsByPattern(
  supabase: DbClient,
  patterns: string[],
  status: StudentListParams["status"],
): Promise<string[]> {
  const ids = new Set<string>();

  for (const column of ["given_name", "family_name", "student_code"] as const) {
    for (const pattern of patterns) {
      let query = supabase.from("student").select("id").ilike(column, pattern);
      if (status !== "all") {
        query = query.eq("status", status);
      }
      const { data, error } = await query;
      if (error) {
        throw error;
      }
      for (const row of data ?? []) {
        ids.add(row.id);
      }
    }
  }

  return [...ids];
}

async function findMatchingGuardianIds(
  supabase: DbClient,
  rawQuery: string,
  patterns: string[],
): Promise<string[]> {
  const ids = new Set<string>();
  const phoneDigits = normalizePhoneDigits(rawQuery);

  for (const column of ["given_name", "family_name"] as const) {
    for (const pattern of patterns) {
      const { data, error } = await supabase
        .from("guardian")
        .select("id")
        .ilike(column, pattern);
      if (error) {
        throw error;
      }
      for (const row of data ?? []) {
        ids.add(row.id);
      }
    }
  }

  if (phoneDigits.length >= 2) {
    const phonePattern = `*${escapeIlike(phoneDigits)}*`;
    const { data, error } = await supabase
      .from("guardian")
      .select("id")
      .ilike("phone", phonePattern);
    if (error) {
      throw error;
    }
    for (const row of data ?? []) {
      ids.add(row.id);
    }
  }

  return [...ids];
}

/**
 * Resolves at most one primary contact per student.
 * When multiple active primary links exist, picks the earliest created_at (deterministic).
 */
async function fetchPrimaryContacts(
  supabase: DbClient,
  studentIds: string[],
): Promise<Map<string, PrimaryLinkRow["guardian"]>> {
  const map = new Map<string, PrimaryLinkRow["guardian"]>();
  if (studentIds.length === 0) {
    return map;
  }

  const { data: links, error: linkError } = await supabase
    .from("student_guardian")
    .select("student_id, guardian_id, created_at")
    .in("student_id", studentIds)
    .eq("status", "active")
    .eq("is_primary_contact", true)
    .order("created_at", { ascending: true });

  if (linkError) {
    throw linkError;
  }

  const chosenGuardianIds = new Map<string, string>();
  for (const link of links ?? []) {
    if (!chosenGuardianIds.has(link.student_id)) {
      chosenGuardianIds.set(link.student_id, link.guardian_id);
    }
  }

  const guardianIds = [...new Set(chosenGuardianIds.values())];
  if (guardianIds.length === 0) {
    return map;
  }

  const { data: guardians, error: guardianError } = await supabase
    .from("guardian")
    .select("id, given_name, family_name, phone")
    .in("id", guardianIds);

  if (guardianError) {
    throw guardianError;
  }

  const guardianById = new Map(
    (guardians ?? []).map((guardian) => [guardian.id, guardian]),
  );

  for (const [studentId, guardianId] of chosenGuardianIds) {
    const guardian = guardianById.get(guardianId) ?? null;
    if (guardian) {
      map.set(studentId, guardian);
    }
  }

  return map;
}
