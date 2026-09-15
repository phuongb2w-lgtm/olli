import Link from "next/link";
import { notFound } from "next/navigation";
import { getTranslations } from "next-intl/server";
import { ClassForm } from "@/components/classes/class-form";
import type { ClassStatus, CourseStatus } from "@/lib/academic/constants";
import { fetchActiveCourses } from "@/lib/academic/query-course-list";
import { can } from "@/lib/permissions/can";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

type Props = {
  params: Promise<{ id: string }>;
};

export default async function EditClassPage({ params }: Props) {
  const t = await getTranslations("classes");
  const hasUpdate = await can("enrollment.update");

  if (!hasUpdate) {
    return (
      <div className="space-y-4">
        <h1 className="text-xl font-semibold">{t("editClass")}</h1>
        <section className="rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-600">
          <p>{t("permissionDenied")}</p>
          <Link href="/classes" className="mt-3 inline-block text-slate-900 underline">
            {t("backToList")}
          </Link>
        </section>
      </div>
    );
  }

  const { id } = await params;
  const supabase = await createClient();

  const [{ data: classRow, error }, courses] = await Promise.all([
    supabase
      .from("class")
      .select("id, name, course_id, term_start_date, term_end_date, capacity, status")
      .eq("id", id)
      .maybeSingle(),
    fetchActiveCourses(supabase).catch(() => []),
  ]);

  if (error || !classRow) {
    notFound();
  }

  const courseOptions = [...courses];
  if (!courseOptions.some((c) => c.id === classRow.course_id)) {
    const { data: currentCourse } = await supabase
      .from("course")
      .select("id, code, name, level_code, status")
      .eq("id", classRow.course_id)
      .maybeSingle();
    if (currentCourse) {
      courseOptions.unshift({
        id: currentCourse.id,
        code: currentCourse.code,
        name: currentCourse.name,
        levelCode: currentCourse.level_code,
        status: currentCourse.status as CourseStatus,
      });
    }
  }

  return (
    <div className="mx-auto max-w-2xl space-y-6">
      <div>
        <Link href="/classes" className="text-sm text-slate-600 hover:text-slate-900">
          ← {t("backToList")}
        </Link>
        <h1 className="mt-2 text-xl font-semibold">{t("editClass")}</h1>
      </div>

      <ClassForm
        mode="edit"
        classId={classRow.id}
        courses={courseOptions.map((c) => ({ id: c.id, code: c.code, name: c.name }))}
        initialValues={{
          name: classRow.name,
          courseId: classRow.course_id,
          termStartDate: classRow.term_start_date ?? "",
          termEndDate: classRow.term_end_date ?? "",
          capacity: classRow.capacity != null ? String(classRow.capacity) : "",
          status: classRow.status as ClassStatus,
        }}
      />
    </div>
  );
}
