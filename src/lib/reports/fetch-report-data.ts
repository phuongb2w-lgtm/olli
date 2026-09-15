import type { SupabaseClient } from "@supabase/supabase-js";
import type { EnrollmentStatus } from "@/lib/enrollments/constants";
import type { AttendanceStatus } from "@/lib/session-execution/constants";
import { resolveSessionOccurrenceDate } from "@/lib/session-execution/roster-eligibility";
import { enrollmentOverlapsPeriod, sessionDateInPeriod } from "./period";
import type {
  AttendanceRow,
  ClassReportContext,
  EnrollmentRow,
  OrganizationBranding,
  ReportPeriod,
  SessionRow,
} from "./types";

function formatStudentName(row: { given_name: string; family_name: string }) {
  return `${row.family_name} ${row.given_name}`.trim();
}

export async function fetchOrganizationBranding(
  supabase: SupabaseClient,
): Promise<OrganizationBranding | null> {
  const { data, error } = await supabase
    .from("organization")
    .select("name")
    .maybeSingle();
  if (error || !data) return null;
  return { name: data.name, hasLogo: false };
}

export async function fetchClassReportContext(
  supabase: SupabaseClient,
  classId: string,
): Promise<ClassReportContext | null> {
  const { data, error } = await supabase
    .from("class")
    .select("id, name, status, term_start_date, term_end_date, course:course(code, name)")
    .eq("id", classId)
    .maybeSingle();
  if (error || !data) return null;
  const course = Array.isArray(data.course) ? data.course[0] : data.course;
  return {
    classId: data.id,
    className: data.name,
    classStatus: data.status,
    courseCode: course?.code ?? null,
    courseName: course?.name ?? null,
    termStartDate: data.term_start_date,
    termEndDate: data.term_end_date,
  };
}

export async function fetchClassEnrollments(
  supabase: SupabaseClient,
  classId: string,
  period?: ReportPeriod,
): Promise<EnrollmentRow[]> {
  const { data, error } = await supabase
    .from("enrollment")
    .select(
      "id, student_id, start_date, end_date, status, student:student(given_name, family_name, student_code)",
    )
    .eq("class_id", classId)
    .order("start_date");
  if (error || !data) return [];

  return data
    .filter((row) => {
      if (!period) return true;
      return enrollmentOverlapsPeriod(row.start_date, row.end_date, period);
    })
    .map((row) => {
      const student = Array.isArray(row.student) ? row.student[0] : row.student;
      return {
        id: row.id,
        studentId: row.student_id,
        startDate: row.start_date,
        endDate: row.end_date,
        status: row.status as EnrollmentStatus,
        studentName: student ? formatStudentName(student) : "—",
        studentCode: student?.student_code ?? null,
      };
    });
}

export async function fetchSessionsInPeriod(
  supabase: SupabaseClient,
  classId: string,
  period: ReportPeriod,
): Promise<SessionRow[]> {
  const { data, error } = await supabase
    .from("teaching_session")
    .select("id, status, occurrence_date, scheduled_start_at")
    .eq("class_id", classId)
    .order("scheduled_start_at");
  if (error || !data) return [];

  return data
    .map((row) => ({
      id: row.id,
      occurrenceDate: resolveSessionOccurrenceDate({
        occurrenceDate: row.occurrence_date,
        scheduledStartAt: row.scheduled_start_at,
      }),
      status: row.status,
    }))
    .filter((row) => sessionDateInPeriod(row.occurrenceDate, period));
}

export async function fetchAttendanceForSessions(
  supabase: SupabaseClient,
  sessionIds: string[],
): Promise<AttendanceRow[]> {
  if (sessionIds.length === 0) return [];
  const { data, error } = await supabase
    .from("attendance")
    .select("enrollment_id, teaching_session_id, status")
    .in("teaching_session_id", sessionIds);
  if (error || !data) return [];
  return data.map((row) => ({
    enrollmentId: row.enrollment_id,
    teachingSessionId: row.teaching_session_id,
    status: row.status as AttendanceStatus,
  }));
}

export type AssessmentDataRow = {
  id: string;
  title: string;
  assessedOn: string;
  maxScore: number;
};

export type AssessmentResultDataRow = {
  assessmentId: string;
  enrollmentId: string;
  rawScore: number;
  maxScore: number;
};

export async function fetchAssessmentsInPeriod(
  supabase: SupabaseClient,
  classId: string,
  period: ReportPeriod,
  assessmentId?: string,
): Promise<AssessmentDataRow[]> {
  let query = supabase
    .from("assessment")
    .select("id, title, assessed_on, max_score")
    .eq("class_id", classId)
    .gte("assessed_on", period.startDate)
    .lte("assessed_on", period.endDate)
    .order("assessed_on")
    .order("title");
  if (assessmentId) query = query.eq("id", assessmentId);
  const { data, error } = await query;
  if (error || !data) return [];
  return data.map((row) => ({
    id: row.id,
    title: row.title,
    assessedOn: row.assessed_on,
    maxScore: Number(row.max_score),
  }));
}

export async function fetchAssessmentResults(
  supabase: SupabaseClient,
  assessmentIds: string[],
): Promise<AssessmentResultDataRow[]> {
  if (assessmentIds.length === 0) return [];
  const { data, error } = await supabase
    .from("assessment_result")
    .select("assessment_id, enrollment_id, raw_score, max_score")
    .in("assessment_id", assessmentIds);
  if (error || !data) return [];
  return data.map((row) => ({
    assessmentId: row.assessment_id,
    enrollmentId: row.enrollment_id,
    rawScore: Number(row.raw_score),
    maxScore: Number(row.max_score),
  }));
}

export type ObservationDataRow = {
  enrollmentId: string;
  teachingSessionId: string;
  sessionDate: string;
  comment: string | null;
  ratings: Record<string, string>;
};

export async function fetchObservationsForSessions(
  supabase: SupabaseClient,
  sessions: SessionRow[],
): Promise<ObservationDataRow[]> {
  const sessionIds = sessions.map((s) => s.id);
  if (sessionIds.length === 0) return [];

  const sessionDateById = new Map(sessions.map((s) => [s.id, s.occurrenceDate]));
  const { data, error } = await supabase
    .from("teacher_observation")
    .select(
      "enrollment_id, teaching_session_id, comment, observation_rating(indicator_code, rating_code)",
    )
    .in("teaching_session_id", sessionIds)
    .neq("status", "void");
  if (error || !data) return [];

  return data.map((row) => {
    const ratings: Record<string, string> = {};
    const ratingRows = row.observation_rating;
    if (Array.isArray(ratingRows)) {
      for (const rating of ratingRows) {
        ratings[rating.indicator_code] = rating.rating_code;
      }
    }
    return {
      enrollmentId: row.enrollment_id,
      teachingSessionId: row.teaching_session_id,
      sessionDate: sessionDateById.get(row.teaching_session_id) ?? "",
      comment: row.comment,
      ratings,
    };
  });
}

export async function fetchStudentEnrollments(
  supabase: SupabaseClient,
  studentId: string,
): Promise<
  Array<{
    id: string;
    classId: string;
    className: string;
    courseCode: string | null;
    startDate: string;
    endDate: string | null;
    status: EnrollmentStatus;
  }>
> {
  const { data, error } = await supabase
    .from("enrollment")
    .select("id, class_id, start_date, end_date, status, class:class(name, course:course(code))")
    .eq("student_id", studentId)
    .order("start_date", { ascending: false });
  if (error || !data) return [];

  return data.map((row) => {
    const classRow = Array.isArray(row.class) ? row.class[0] : row.class;
    const course = classRow?.course
      ? Array.isArray(classRow.course)
        ? classRow.course[0]
        : classRow.course
      : null;
    return {
      id: row.id,
      classId: row.class_id,
      className: classRow?.name ?? "—",
      courseCode: course?.code ?? null,
      startDate: row.start_date,
      endDate: row.end_date,
      status: row.status as EnrollmentStatus,
    };
  });
}
