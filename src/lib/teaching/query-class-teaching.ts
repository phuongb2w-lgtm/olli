import type { SupabaseClient } from "@supabase/supabase-js";
import type { ClassStatus } from "@/lib/academic/constants";
import type { ScheduleStatus, SessionStatus, TeacherAssignmentStatus } from "./constants";

export type ClassTeachingContext = {
  id: string;
  name: string;
  status: ClassStatus;
  termStartDate: string | null;
  termEndDate: string | null;
  capacity: number | null;
};

export type TeacherAssignmentItem = {
  id: string;
  teacherId: string;
  teacherName: string;
  roleCode: string;
  effectiveFrom: string;
  effectiveTo: string | null;
  status: TeacherAssignmentStatus;
};

export type ScheduleItem = {
  id: string;
  weekdayCode: string;
  startTime: string;
  endTime: string;
  effectiveFrom: string;
  effectiveTo: string | null;
  location: string | null;
  roomId: string | null;
  roomName: string | null;
  teacherId: string | null;
  teacherName: string | null;
  status: ScheduleStatus;
};

export type SessionItem = {
  id: string;
  occurrenceDate: string | null;
  scheduledStartAt: string;
  scheduledEndAt: string;
  status: SessionStatus;
  classScheduleId: string | null;
  teacherId: string;
  teacherName: string;
  roomId: string | null;
  roomName: string | null;
};

export type TeacherOption = {
  id: string;
  label: string;
  status: string;
};

export type RoomOption = {
  id: string;
  label: string;
  capacity: number | null;
  status: string;
};

function formatTeacherName(row: { given_name: string; family_name: string }) {
  return `${row.given_name} ${row.family_name}`.trim();
}

function unwrapRelation<T>(value: T | T[] | null | undefined): T | null {
  if (value == null) return null;
  return Array.isArray(value) ? (value[0] ?? null) : value;
}

export async function fetchClassTeachingContext(
  supabase: SupabaseClient,
  classId: string,
): Promise<ClassTeachingContext | null> {
  const { data, error } = await supabase
    .from("class")
    .select("id, name, status, term_start_date, term_end_date, capacity")
    .eq("id", classId)
    .maybeSingle();
  if (error || !data) return null;
  return {
    id: data.id,
    name: data.name,
    status: data.status as ClassStatus,
    termStartDate: data.term_start_date,
    termEndDate: data.term_end_date,
    capacity: data.capacity,
  };
}

export async function fetchTeacherAssignments(
  supabase: SupabaseClient,
  classId: string,
): Promise<TeacherAssignmentItem[]> {
  const { data, error } = await supabase
    .from("class_teacher_assignment")
    .select(
      "id, teacher_id, role_code, effective_from, effective_to, status, teacher:teacher(given_name, family_name)",
    )
    .eq("class_id", classId)
    .order("effective_from", { ascending: false });
  if (error || !data) return [];
  return data.map((row) => {
    const teacher = unwrapRelation(
      row.teacher as unknown as { given_name: string; family_name: string } | null,
    );
    return {
      id: row.id,
      teacherId: row.teacher_id,
      teacherName: teacher ? formatTeacherName(teacher) : "—",
      roleCode: row.role_code,
      effectiveFrom: row.effective_from,
      effectiveTo: row.effective_to,
      status: row.status as TeacherAssignmentStatus,
    };
  });
}

export async function fetchClassSchedules(
  supabase: SupabaseClient,
  classId: string,
): Promise<ScheduleItem[]> {
  const { data, error } = await supabase
    .from("class_schedule")
    .select(
      "id, weekday_code, start_time, end_time, effective_from, effective_to, location, room_id, teacher_id, status, room:room(name), teacher:teacher(given_name, family_name)",
    )
    .eq("class_id", classId)
    .order("weekday_code")
    .order("start_time");
  if (error || !data) return [];
  return data.map((row) => {
    const room = unwrapRelation(row.room as unknown as { name: string } | null);
    const teacher = unwrapRelation(
      row.teacher as unknown as { given_name: string; family_name: string } | null,
    );
    return {
      id: row.id,
      weekdayCode: row.weekday_code,
      startTime: row.start_time.slice(0, 5),
      endTime: row.end_time.slice(0, 5),
      effectiveFrom: row.effective_from,
      effectiveTo: row.effective_to,
      location: row.location,
      roomId: row.room_id,
      roomName: room?.name ?? null,
      teacherId: row.teacher_id,
      teacherName: teacher ? formatTeacherName(teacher) : null,
      status: row.status as ScheduleStatus,
    };
  });
}

export async function fetchClassSessions(
  supabase: SupabaseClient,
  classId: string,
): Promise<SessionItem[]> {
  const { data, error } = await supabase
    .from("teaching_session")
    .select(
      "id, occurrence_date, scheduled_start_at, scheduled_end_at, status, class_schedule_id, teacher_id, room_id, teacher:teacher(given_name, family_name), room:room(name)",
    )
    .eq("class_id", classId)
    .order("scheduled_start_at", { ascending: true });
  if (error || !data) return [];
  return data.map((row) => {
    const teacher = unwrapRelation(
      row.teacher as unknown as { given_name: string; family_name: string } | null,
    );
    const room = unwrapRelation(row.room as unknown as { name: string } | null);
    return {
      id: row.id,
      occurrenceDate: row.occurrence_date,
      scheduledStartAt: row.scheduled_start_at,
      scheduledEndAt: row.scheduled_end_at,
      status: row.status as SessionStatus,
      classScheduleId: row.class_schedule_id,
      teacherId: row.teacher_id,
      teacherName: teacher ? formatTeacherName(teacher) : "—",
      roomId: row.room_id,
      roomName: room?.name ?? null,
    };
  });
}

export async function fetchEligibleTeachers(supabase: SupabaseClient): Promise<TeacherOption[]> {
  const { data, error } = await supabase
    .from("teacher")
    .select("id, given_name, family_name, status")
    .eq("status", "active")
    .order("family_name")
    .order("given_name");
  if (error || !data) return [];
  return data.map((row) => ({
    id: row.id,
    label: formatTeacherName(row),
    status: row.status,
  }));
}

export async function fetchActiveRooms(supabase: SupabaseClient): Promise<RoomOption[]> {
  const { data, error } = await supabase
    .from("room")
    .select("id, name, code, capacity, status")
    .eq("status", "active")
    .order("name");
  if (error || !data) return [];
  return data.map((row) => ({
    id: row.id,
    label: row.code ? `${row.name} (${row.code})` : row.name,
    capacity: row.capacity,
    status: row.status,
  }));
}
