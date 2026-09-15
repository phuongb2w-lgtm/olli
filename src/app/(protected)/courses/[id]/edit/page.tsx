import Link from "next/link";
import { notFound } from "next/navigation";
import { getTranslations } from "next-intl/server";
import { CourseForm } from "@/components/courses/course-form";
import type { CourseStatus } from "@/lib/academic/constants";
import { can } from "@/lib/permissions/can";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

type Props = {
  params: Promise<{ id: string }>;
};

export default async function EditCoursePage({ params }: Props) {
  const t = await getTranslations("courses");
  const hasUpdate = await can("enrollment.update");

  if (!hasUpdate) {
    return (
      <div className="space-y-4">
        <h1 className="text-xl font-semibold">{t("editCourse")}</h1>
        <section className="rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-600">
          <p>{t("permissionDenied")}</p>
          <Link href="/courses" className="mt-3 inline-block text-slate-900 underline">
            {t("backToList")}
          </Link>
        </section>
      </div>
    );
  }

  const { id } = await params;
  const supabase = await createClient();
  const { data: course, error } = await supabase
    .from("course")
    .select("id, code, name, level_code, status")
    .eq("id", id)
    .maybeSingle();

  if (error || !course) {
    notFound();
  }

  return (
    <div className="mx-auto max-w-2xl space-y-6">
      <div>
        <Link href="/courses" className="text-sm text-slate-600 hover:text-slate-900">
          ← {t("backToList")}
        </Link>
        <h1 className="mt-2 text-xl font-semibold">{t("editCourse")}</h1>
      </div>

      <CourseForm
        mode="edit"
        courseId={course.id}
        initialValues={{
          code: course.code,
          name: course.name,
          levelCode: course.level_code ?? "",
          status: course.status as CourseStatus,
        }}
      />
    </div>
  );
}
