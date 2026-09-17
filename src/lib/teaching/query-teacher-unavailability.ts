import type { SupabaseClient } from "@supabase/supabase-js";
import type { UnavailabilityBlockType, UnavailabilityStatus, WeekdayCode } from "./constants";

export type TeacherUnavailabilityItem = {
  id: string;
  teacherId: string;
  teacherName: string;
  blockType: UnavailabilityBlockType;
  weekdayCode: WeekdayCode | null;
  startTime: string | null;
  endTime: string | null;
  effectiveFrom: string | null;
  effectiveTo: string | null;
  startsAt: string | null;
  endsAt: string | null;
  reason: string | null;
  status: UnavailabilityStatus;
};

function formatTeacherName(row: { given_name: string; family_name: string }) {
  return `${row.given_name} ${row.family_name}`.trim();
}

function unwrapRelation<T>(value: T | T[] | null | undefined): T | null {
  if (value == null) return null;
  return Array.isArray(value) ? (value[0] ?? null) : value;
}

function mapRow(row: {
  id: string;
  teacher_id: string;
  block_type: string;
  weekday_code: string | null;
  start_time: string | null;
  end_time: string | null;
  effective_from: string | null;
  effective_to: string | null;
  starts_at: string | null;
  ends_at: string | null;
  reason: string | null;
  status: string;
  teacher: { given_name: string; family_name: string } | { given_name: string; family_name: string }[] | null;
}): TeacherUnavailabilityItem {
  const teacher = unwrapRelation(row.teacher);
  return {
    id: row.id,
    teacherId: row.teacher_id,
    teacherName: teacher ? formatTeacherName(teacher) : "—",
    blockType: row.block_type as UnavailabilityBlockType,
    weekdayCode: row.weekday_code as WeekdayCode | null,
    startTime: row.start_time ? row.start_time.slice(0, 5) : null,
    endTime: row.end_time ? row.end_time.slice(0, 5) : null,
    effectiveFrom: row.effective_from,
    effectiveTo: row.effective_to,
    startsAt: row.starts_at,
    endsAt: row.ends_at,
    reason: row.reason,
    status: row.status as UnavailabilityStatus,
  };
}

export async function fetchTeacherUnavailabilityList(
  supabase: SupabaseClient,
  teacherId: string,
  options?: { includeEnded?: boolean },
): Promise<TeacherUnavailabilityItem[]> {
  let query = supabase
    .from("teacher_unavailability")
    .select(
      "id, teacher_id, block_type, weekday_code, start_time, end_time, effective_from, effective_to, starts_at, ends_at, reason, status, teacher:teacher(given_name, family_name)",
    )
    .eq("teacher_id", teacherId)
    .order("created_at", { ascending: false });

  if (!options?.includeEnded) {
    query = query.eq("status", "active");
  }

  const { data, error } = await query;
  if (error || !data) return [];
  return data.map((row) => mapRow(row as Parameters<typeof mapRow>[0]));
}

export async function fetchActiveUnavailabilityForRange(
  supabase: SupabaseClient,
  rangeStart: string,
  rangeEnd: string,
  teacherId?: string,
): Promise<TeacherUnavailabilityItem[]> {
  let query = supabase
    .from("teacher_unavailability")
    .select(
      "id, teacher_id, block_type, weekday_code, start_time, end_time, effective_from, effective_to, starts_at, ends_at, reason, status, teacher:teacher(given_name, family_name)",
    )
    .eq("status", "active");

  if (teacherId) {
    query = query.eq("teacher_id", teacherId);
  }

  const { data, error } = await query;
  if (error || !data) return [];

  const startDate = rangeStart.slice(0, 10);
  const endDate = rangeEnd.slice(0, 10);

  return data
    .map((row) => mapRow(row as Parameters<typeof mapRow>[0]))
    .filter((item) => {
      if (item.blockType === "one_off" && item.startsAt && item.endsAt) {
        return item.startsAt.slice(0, 10) <= endDate && item.endsAt.slice(0, 10) >= startDate;
      }
      if (item.blockType === "recurring" && item.effectiveFrom) {
        const effectiveEnd = item.effectiveTo ?? "9999-12-31";
        return item.effectiveFrom <= endDate && effectiveEnd >= startDate;
      }
      return true;
    });
}

export async function checkTeacherHasUnavailability(
  supabase: SupabaseClient,
  teacherId: string,
  rangeStart: string,
  rangeEnd: string,
): Promise<boolean> {
  const { data, error } = await supabase.rpc("teacher_has_unavailability", {
    p_teacher_id: teacherId,
    p_range_start: rangeStart,
    p_range_end: rangeEnd,
  });
  if (error) return false;
  return Boolean(data);
}
