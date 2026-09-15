import Link from "next/link";
import { getTranslations } from "next-intl/server";
import { ClassForm } from "@/components/classes/class-form";
import { DEFAULT_CLASS_STATUS } from "@/lib/academic/constants";
import { fetchActiveCourses } from "@/lib/academic/query-course-list";
import { can } from "@/lib/permissions/can";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

export default async function NewClassPage() {
  const t = await getTranslations("classes");
  const hasCreate = await can("enrollment.create");

  if (!hasCreate) {
    return (
      <div className="space-y-4">
        <h1 className="text-xl font-semibold">{t("createClass")}</h1>
        <section className="rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-600">
          <p>{t("permissionDenied")}</p>
          <Link href="/classes" className="mt-3 inline-block text-slate-900 underline">
            {t("backToList")}
          </Link>
        </section>
      </div>
    );
  }

  const supabase = await createClient();
  const courses = await fetchActiveCourses(supabase).catch(() => []);

  return (
    <div className="mx-auto max-w-2xl space-y-6">
      <div>
        <Link href="/classes" className="text-sm text-slate-600 hover:text-slate-900">
          ← {t("backToList")}
        </Link>
        <h1 className="mt-2 text-xl font-semibold">{t("createClass")}</h1>
      </div>

      {courses.length === 0 ? (
        <section className="rounded-lg border border-amber-200 bg-amber-50 p-4 text-sm text-amber-900">
          <p>{t("noCoursesAvailable")}</p>
          <Link href="/courses/new" className="mt-2 inline-block font-medium underline">
            {t("createCourseFirst")}
          </Link>
        </section>
      ) : (
        <ClassForm
          mode="create"
          courses={courses}
          initialValues={{
            name: "",
            courseId: "",
            termStartDate: "",
            termEndDate: "",
            capacity: "",
            status: DEFAULT_CLASS_STATUS,
          }}
        />
      )}
    </div>
  );
}
