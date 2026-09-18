import type { SupabaseClient } from "@supabase/supabase-js";

export type OperationalCalendarEntryType = "session" | "projected";

export type TeacherResolutionStatus =
  | "resolved"
  | "teacher_not_resolved"
  | "multiple_primary_teachers";

export type OperationalCalendarEntry = {
  entryType: OperationalCalendarEntryType;
  occurrenceDate: string;
  startsAt: string;
  endsAt: string;
  classId: string;
  className: string;
  classScheduleId: string | null;
  teachingSessionId: string | null;
  sessionStatus: string | null;
  teacherId: string | null;
  teacherResolutionStatus: TeacherResolutionStatus;
  teacherDisplayName: string | null;
  roomId: string | null;
  roomName: string | null;
  roomCode: string | null;
};

export type OperationalCalendarFilters = {
  dateFrom: string;
  dateTo: string;
  classId?: string | null;
  teacherId?: string | null;
  roomId?: string | null;
};

function mapEntry(row: Record<string, unknown>): OperationalCalendarEntry {
  return {
    entryType: row.entry_type as OperationalCalendarEntryType,
    occurrenceDate: String(row.occurrence_date),
    startsAt: String(row.starts_at),
    endsAt: String(row.ends_at),
    classId: String(row.class_id),
    className: String(row.class_name ?? ""),
    classScheduleId: (row.class_schedule_id as string | null) ?? null,
    teachingSessionId: (row.teaching_session_id as string | null) ?? null,
    sessionStatus: (row.session_status as string | null) ?? null,
    teacherId: (row.teacher_id as string | null) ?? null,
    teacherResolutionStatus: (row.teacher_resolution_status as TeacherResolutionStatus) ?? "resolved",
    teacherDisplayName: (row.teacher_display_name as string | null) ?? null,
    roomId: (row.room_id as string | null) ?? null,
    roomName: (row.room_name as string | null) ?? null,
    roomCode: (row.room_code as string | null) ?? null,
  };
}

export async function fetchOperationalCalendar(
  supabase: SupabaseClient,
  filters: OperationalCalendarFilters,
): Promise<{ entries: OperationalCalendarEntry[]; error: string | null }> {
  const { data, error } = await supabase.rpc("list_operational_calendar", {
    p_date_from: filters.dateFrom,
    p_date_to: filters.dateTo,
    p_class_id: filters.classId || undefined,
    p_teacher_id: filters.teacherId || undefined,
    p_room_id: filters.roomId || undefined,
  });

  if (error) {
    const msg = error.message ?? "";
    if (msg.includes("calendar_range_too_large")) return { entries: [], error: "range_too_large" };
    if (msg.includes("invalid_calendar_range")) return { entries: [], error: "invalid_range" };
    if (msg.includes("permission_denied")) return { entries: [], error: "permission_denied" };
    if (msg.includes("invalid_class")) return { entries: [], error: "invalid_class" };
    if (msg.includes("invalid_teacher")) return { entries: [], error: "invalid_teacher" };
    if (msg.includes("invalid_room")) return { entries: [], error: "invalid_room" };
    return { entries: [], error: "load_error" };
  }

  const rows = (data ?? []) as Record<string, unknown>[];
  return { entries: rows.map(mapEntry), error: null };
}
