import type { SupabaseClient } from "@supabase/supabase-js";
import { derivePercentage } from "./eligibility";

export type StudentProgressItem = {
  resultId: string;
  assessmentId: string;
  assessmentTitle: string;
  assessedOn: string;
  classId: string;
  className: string;
  courseCode: string | null;
  courseName: string | null;
  enrollmentId: string;
  enrollmentStartDate: string;
  enrollmentEndDate: string | null;
  rawScore: number;
  maxScore: number;
  percentage: number | null;
};

export async function fetchStudentProgress(
  supabase: SupabaseClient,
  studentId: string,
): Promise<StudentProgressItem[]> {
  const { data: enrollments, error: enrollError } = await supabase
    .from("enrollment")
    .select("id, class_id, start_date, end_date, class:class(name, course:course(code, name))")
    .eq("student_id", studentId)
    .order("start_date", { ascending: false });

  if (enrollError || !enrollments?.length) return [];

  const enrollmentIds = enrollments.map((e) => e.id);
  const { data: results, error: resultError } = await supabase
    .from("assessment_result")
    .select(
      "id, enrollment_id, raw_score, max_score, assessment:assessment(id, title, assessed_on, class_id)",
    )
    .in("enrollment_id", enrollmentIds)
    .order("created_at", { ascending: false });

  if (resultError || !results) return [];

  const enrollmentById = new Map(
    enrollments.map((e) => {
      const classRow = Array.isArray(e.class) ? e.class[0] : e.class;
      const course = classRow?.course
        ? Array.isArray(classRow.course)
          ? classRow.course[0]
          : classRow.course
        : null;
      return [
        e.id,
        {
          classId: e.class_id,
          className: classRow?.name ?? "—",
          courseCode: course?.code ?? null,
          courseName: course?.name ?? null,
          startDate: e.start_date,
          endDate: e.end_date,
        },
      ];
    }),
  );

  const items: StudentProgressItem[] = [];
  for (const row of results) {
    const assessment = Array.isArray(row.assessment) ? row.assessment[0] : row.assessment;
    const enr = enrollmentById.get(row.enrollment_id);
    if (!assessment || !enr) continue;

    const rawScore = Number(row.raw_score);
    const maxScore = Number(row.max_score);
    items.push({
      resultId: row.id,
      assessmentId: assessment.id,
      assessmentTitle: assessment.title,
      assessedOn: assessment.assessed_on,
      classId: enr.classId,
      className: enr.className,
      courseCode: enr.courseCode,
      courseName: enr.courseName,
      enrollmentId: row.enrollment_id,
      enrollmentStartDate: enr.startDate,
      enrollmentEndDate: enr.endDate,
      rawScore,
      maxScore,
      percentage: derivePercentage(rawScore, maxScore),
    });
  }

  items.sort((a, b) => {
    const dateCmp = b.assessedOn.localeCompare(a.assessedOn);
    if (dateCmp !== 0) return dateCmp;
    return a.assessmentTitle.localeCompare(b.assessmentTitle);
  });

  return items;
}

export function computeSimpleAveragePercentage(items: StudentProgressItem[]): number | null {
  if (items.length === 0) return null;
  const values = items
    .map((i) => i.percentage)
    .filter((p): p is number => p !== null);
  if (values.length === 0) return null;
  const sum = values.reduce((a, b) => a + b, 0);
  return Math.round((sum / values.length) * 10) / 10;
}
