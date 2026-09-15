import type { SupabaseClient } from "@supabase/supabase-js";
import type { AssessmentStatus, AssessmentTypeCode } from "./constants";
import { derivePercentage, isEnrollmentVisibleForAssessmentResult } from "./eligibility";

export type ClassAssessmentContext = {
  id: string;
  name: string;
  status: string;
  courseCode: string | null;
  courseName: string | null;
};

export type AssessmentListItem = {
  id: string;
  title: string;
  assessedOn: string;
  maxScore: number;
  status: AssessmentStatus;
  assessmentTypeCode: AssessmentTypeCode;
  scoredCount: number;
  eligibleCount: number;
};

export type AssessmentDetail = {
  id: string;
  classId: string;
  title: string;
  assessedOn: string;
  maxScore: number;
  status: AssessmentStatus;
  assessmentTypeCode: AssessmentTypeCode;
  className: string;
  courseCode: string | null;
};

export type AssessmentResultRow = {
  enrollmentId: string;
  studentId: string;
  studentName: string;
  studentCode: string | null;
  enrollmentStatus: string;
  enrollmentStartDate: string;
  enrollmentEndDate: string | null;
  resultId: string | null;
  rawScore: number | null;
  maxScore: number | null;
  percentage: number | null;
  resultStatus: string | null;
};

function formatStudentName(row: { given_name: string; family_name: string }) {
  return `${row.family_name} ${row.given_name}`.trim();
}

export async function fetchClassAssessmentContext(
  supabase: SupabaseClient,
  classId: string,
): Promise<ClassAssessmentContext | null> {
  const { data, error } = await supabase
    .from("class")
    .select("id, name, status, course:course(code, name)")
    .eq("id", classId)
    .maybeSingle();
  if (error || !data) return null;
  const course = Array.isArray(data.course) ? data.course[0] : data.course;
  return {
    id: data.id,
    name: data.name,
    status: data.status,
    courseCode: course?.code ?? null,
    courseName: course?.name ?? null,
  };
}

export async function fetchClassAssessments(
  supabase: SupabaseClient,
  classId: string,
): Promise<AssessmentListItem[]> {
  const { data: assessments, error } = await supabase
    .from("assessment")
    .select("id, title, assessed_on, max_score, status, assessment_type_code")
    .eq("class_id", classId)
    .order("assessed_on", { ascending: false })
    .order("title");
  if (error || !assessments) return [];

  const { data: enrollments } = await supabase
    .from("enrollment")
    .select("id, start_date, end_date, status")
    .eq("class_id", classId);

  const assessmentIds = assessments.map((row) => row.id);
  const scoredCountByAssessment = new Map<string, number>();
  if (assessmentIds.length > 0) {
    const { data: resultRows } = await supabase
      .from("assessment_result")
      .select("assessment_id")
      .in("assessment_id", assessmentIds);
    for (const result of resultRows ?? []) {
      scoredCountByAssessment.set(
        result.assessment_id,
        (scoredCountByAssessment.get(result.assessment_id) ?? 0) + 1,
      );
    }
  }

  const items: AssessmentListItem[] = [];
  for (const row of assessments) {
    const scoredCount = scoredCountByAssessment.get(row.id) ?? 0;

    const eligibleCount = (enrollments ?? []).filter((enr) => {
      if (enr.start_date > row.assessed_on) return false;
      if (enr.end_date && enr.end_date < row.assessed_on) return false;
      if (enr.status === "pending") return false;
      return true;
    }).length;

    items.push({
      id: row.id,
      title: row.title,
      assessedOn: row.assessed_on,
      maxScore: Number(row.max_score),
      status: row.status as AssessmentStatus,
      assessmentTypeCode: row.assessment_type_code as AssessmentTypeCode,
      scoredCount,
      eligibleCount,
    });
  }
  return items;
}

export async function fetchAssessmentDetail(
  supabase: SupabaseClient,
  classId: string,
  assessmentId: string,
): Promise<AssessmentDetail | null> {
  const { data, error } = await supabase
    .from("assessment")
    .select(
      "id, class_id, title, assessed_on, max_score, status, assessment_type_code, class:class(name, course:course(code))",
    )
    .eq("id", assessmentId)
    .eq("class_id", classId)
    .maybeSingle();
  if (error || !data) return null;
  const classRow = Array.isArray(data.class) ? data.class[0] : data.class;
  const course = classRow?.course
    ? Array.isArray(classRow.course)
      ? classRow.course[0]
      : classRow.course
    : null;
  return {
    id: data.id,
    classId: data.class_id,
    title: data.title,
    assessedOn: data.assessed_on,
    maxScore: Number(data.max_score),
    status: data.status as AssessmentStatus,
    assessmentTypeCode: data.assessment_type_code as AssessmentTypeCode,
    className: classRow?.name ?? "—",
    courseCode: course?.code ?? null,
  };
}

export async function fetchAssessmentResults(
  supabase: SupabaseClient,
  assessment: AssessmentDetail,
): Promise<AssessmentResultRow[]> {
  const [{ data: enrollments }, { data: results }] = await Promise.all([
    supabase
      .from("enrollment")
      .select(
        "id, student_id, start_date, end_date, status, student:student(given_name, family_name, student_code)",
      )
      .eq("class_id", assessment.classId)
      .order("start_date"),
    supabase
      .from("assessment_result")
      .select("id, enrollment_id, raw_score, max_score, status")
      .eq("assessment_id", assessment.id),
  ]);

  const resultByEnrollment = new Map((results ?? []).map((r) => [r.enrollment_id, r]));
  const rows: AssessmentResultRow[] = [];

  for (const enr of enrollments ?? []) {
    const student = Array.isArray(enr.student) ? enr.student[0] : enr.student;
    const eligibility = {
      startDate: enr.start_date,
      endDate: enr.end_date,
      status: enr.status,
    };
    if (!isEnrollmentVisibleForAssessmentResult(eligibility, assessment.assessedOn)) continue;

    const result = resultByEnrollment.get(enr.id);
    const rawScore = result ? Number(result.raw_score) : null;
    const maxScore = result ? Number(result.max_score) : null;

    rows.push({
      enrollmentId: enr.id,
      studentId: enr.student_id,
      studentName: student ? formatStudentName(student) : "—",
      studentCode: student?.student_code ?? null,
      enrollmentStatus: enr.status,
      enrollmentStartDate: enr.start_date,
      enrollmentEndDate: enr.end_date,
      resultId: result?.id ?? null,
      rawScore,
      maxScore,
      percentage: rawScore !== null && maxScore !== null ? derivePercentage(rawScore, maxScore) : null,
      resultStatus: result?.status ?? null,
    });
  }

  rows.sort((a, b) => a.studentName.localeCompare(b.studentName));
  return rows;
}

export function countResultProgress(rows: AssessmentResultRow[]) {
  const total = rows.length;
  const scored = rows.filter((r) => r.resultId !== null).length;
  return { total, scored, notScored: total - scored };
}
