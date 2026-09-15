import type { SupabaseClient } from "@supabase/supabase-js";
import type { EnrollmentStatus } from "@/lib/enrollments/constants";

export type StudentEnrollmentItem = {
  enrollmentId: string;
  classId: string;
  className: string;
  courseCode: string;
  courseName: string;
  status: EnrollmentStatus;
  startDate: string;
  endDate: string | null;
};

export async function queryStudentEnrollments(
  supabase: SupabaseClient,
  studentId: string,
): Promise<{ items: StudentEnrollmentItem[]; error: boolean }> {
  try {
    const { data, error } = await supabase
      .from("enrollment")
      .select("id, class_id, status, start_date, end_date")
      .eq("student_id", studentId)
      .order("start_date", { ascending: false })
      .order("id", { ascending: false });

    if (error) return { items: [], error: true };

    const rows = data ?? [];
    const classIds = [...new Set(rows.map((r) => r.class_id))];
    const classById = new Map<
      string,
      { name: string; courseId: string }
    >();
    const courseById = new Map<string, { code: string; name: string }>();

    if (classIds.length > 0) {
      const { data: classes, error: classError } = await supabase
        .from("class")
        .select("id, name, course_id")
        .in("id", classIds);
      if (classError) return { items: [], error: true };

      const courseIds = [...new Set((classes ?? []).map((c) => c.course_id))];
      if (courseIds.length > 0) {
        const { data: courses, error: courseError } = await supabase
          .from("course")
          .select("id, code, name")
          .in("id", courseIds);
        if (courseError) return { items: [], error: true };
        for (const course of courses ?? []) {
          courseById.set(course.id, { code: course.code, name: course.name });
        }
      }

      for (const cls of classes ?? []) {
        classById.set(cls.id, { name: cls.name, courseId: cls.course_id });
      }
    }

    const items: StudentEnrollmentItem[] = rows
      .map((row) => {
        const cls = classById.get(row.class_id);
        if (!cls) return null;
        const course = courseById.get(cls.courseId);
        if (!course) return null;
        return {
          enrollmentId: row.id,
          classId: row.class_id,
          className: cls.name,
          courseCode: course.code,
          courseName: course.name,
          status: row.status as EnrollmentStatus,
          startDate: row.start_date,
          endDate: row.end_date,
        };
      })
      .filter((item): item is StudentEnrollmentItem => item !== null);

    return { items, error: false };
  } catch {
    return { items: [], error: true };
  }
}
