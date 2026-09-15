import type { SupabaseClient } from "@supabase/supabase-js";
import type { EnrollmentStatus } from "@/lib/enrollments/constants";
import type { AttendanceStatus, SessionExecutionStatus } from "./constants";
import {
  isEnrollmentVisibleOnSessionRoster,
  resolveSessionOccurrenceDate,
} from "./roster-eligibility";

export type SessionExecutionContext = {
  id: string;
  classId: string;
  className: string;
  courseCode: string | null;
  courseName: string | null;
  status: SessionExecutionStatus;
  scheduledStartAt: string;
  scheduledEndAt: string;
  occurrenceDate: string;
  teacherId: string;
  teacherName: string;
  roomId: string | null;
  roomName: string | null;
  locationFallback: string | null;
};

export type SessionRosterItem = {
  enrollmentId: string;
  studentId: string;
  studentName: string;
  studentCode: string | null;
  enrollmentStatus: EnrollmentStatus;
  enrollmentStartDate: string;
  enrollmentEndDate: string | null;
  attendanceStatus: AttendanceStatus | null;
  attendanceId: string | null;
  observationId: string | null;
  observationComment: string | null;
  ratings: Record<string, string>;
};

export type ObservationIndicator = {
  code: string;
};

function formatTeacherName(row: { given_name: string; family_name: string }) {
  return `${row.given_name} ${row.family_name}`.trim();
}

function formatStudentName(row: { given_name: string; family_name: string }) {
  return `${row.family_name} ${row.given_name}`.trim();
}

export async function fetchSessionExecutionContext(
  supabase: SupabaseClient,
  classId: string,
  sessionId: string,
): Promise<SessionExecutionContext | null> {
  const { data, error } = await supabase
    .from("teaching_session")
    .select(
      `
      id, class_id, status, scheduled_start_at, scheduled_end_at, occurrence_date,
      teacher_id, room_id,
      teacher:teacher(given_name, family_name),
      room:room(name),
      class_schedule_id,
      class:class(name, course:course(code, name))
    `,
    )
    .eq("id", sessionId)
    .eq("class_id", classId)
    .maybeSingle();

  if (error || !data) return null;

  const teacher = Array.isArray(data.teacher) ? data.teacher[0] : data.teacher;
  const room = Array.isArray(data.room) ? data.room[0] : data.room;
  const classRow = Array.isArray(data.class) ? data.class[0] : data.class;
  const course = classRow?.course
    ? Array.isArray(classRow.course)
      ? classRow.course[0]
      : classRow.course
    : null;

  let locationFallback: string | null = null;
  if (!data.room_id && data.class_schedule_id) {
    const { data: scheduleRow } = await supabase
      .from("class_schedule")
      .select("location")
      .eq("id", data.class_schedule_id)
      .maybeSingle();
    locationFallback = scheduleRow?.location ?? null;
  }

  return {
    id: data.id,
    classId: data.class_id,
    className: classRow?.name ?? "—",
    courseCode: course?.code ?? null,
    courseName: course?.name ?? null,
    status: data.status as SessionExecutionStatus,
    scheduledStartAt: data.scheduled_start_at,
    scheduledEndAt: data.scheduled_end_at,
    occurrenceDate: resolveSessionOccurrenceDate({
      occurrenceDate: data.occurrence_date,
      scheduledStartAt: data.scheduled_start_at,
    }),
    teacherId: data.teacher_id,
    teacherName: teacher ? formatTeacherName(teacher) : "—",
    roomId: data.room_id,
    roomName: room?.name ?? null,
    locationFallback,
  };
}

export async function fetchObservationIndicators(
  supabase: SupabaseClient,
): Promise<ObservationIndicator[]> {
  const { data, error } = await supabase
    .from("observation_indicator")
    .select("code")
    .order("code");
  if (error || !data) return [];
  return data.map((row) => ({ code: row.code }));
}

export async function fetchSessionRoster(
  supabase: SupabaseClient,
  session: SessionExecutionContext,
): Promise<SessionRosterItem[]> {
  const sessionDate = session.occurrenceDate;

  const [{ data: enrollments }, { data: attendances }, { data: observations }] =
    await Promise.all([
      supabase
        .from("enrollment")
        .select(
          "id, student_id, start_date, end_date, status, student:student(given_name, family_name, student_code)",
        )
        .eq("class_id", session.classId)
        .order("start_date"),
      supabase
        .from("attendance")
        .select("id, enrollment_id, status")
        .eq("teaching_session_id", session.id),
      supabase
        .from("teacher_observation")
        .select(
          "id, enrollment_id, comment, observation_rating(indicator_code, rating_code)",
        )
        .eq("teaching_session_id", session.id)
        .neq("status", "void"),
    ]);

  const attendanceByEnrollment = new Map(
    (attendances ?? []).map((a) => [a.enrollment_id, a]),
  );
  const observationByEnrollment = new Map(
    (observations ?? []).map((o) => [o.enrollment_id, o]),
  );

  const items: SessionRosterItem[] = [];

  for (const row of enrollments ?? []) {
    const student = Array.isArray(row.student) ? row.student[0] : row.student;
    const enrollmentRow = {
      id: row.id,
      studentId: row.student_id,
      startDate: row.start_date,
      endDate: row.end_date,
      status: row.status as EnrollmentStatus,
    };

    if (!isEnrollmentVisibleOnSessionRoster(enrollmentRow, sessionDate)) continue;

    const attendance = attendanceByEnrollment.get(row.id);
    const observation = observationByEnrollment.get(row.id);
    const ratings: Record<string, string> = {};
    const ratingRows = observation?.observation_rating;
    if (Array.isArray(ratingRows)) {
      for (const rating of ratingRows) {
        ratings[rating.indicator_code] = rating.rating_code;
      }
    }

    items.push({
      enrollmentId: row.id,
      studentId: row.student_id,
      studentName: student ? formatStudentName(student) : "—",
      studentCode: student?.student_code ?? null,
      enrollmentStatus: enrollmentRow.status,
      enrollmentStartDate: enrollmentRow.startDate,
      enrollmentEndDate: enrollmentRow.endDate,
      attendanceStatus: (attendance?.status as AttendanceStatus | undefined) ?? null,
      attendanceId: attendance?.id ?? null,
      observationId: observation?.id ?? null,
      observationComment: observation?.comment ?? null,
      ratings,
    });
  }

  items.sort((a, b) => a.studentName.localeCompare(b.studentName));
  return items;
}

export function countAttendanceProgress(roster: SessionRosterItem[]) {
  const total = roster.length;
  const recorded = roster.filter((r) => r.attendanceStatus !== null).length;
  return { total, recorded, notRecorded: total - recorded };
}
