import Link from "next/link";
import { getTranslations } from "next-intl/server";
import { CourseForm } from "@/components/courses/course-form";
import { DEFAULT_COURSE_STATUS } from "@/lib/academic/constants";
import { can } from "@/lib/permissions/can";

export const dynamic = "force-dynamic";

export default async function NewCoursePage() {
  const t = await getTranslations("courses");
  const hasCreate = await can("enrollment.create");

  if (!hasCreate) {
    return (
      <div className="space-y-4">
        <h1 className="text-xl font-semibold">{t("createCourse")}</h1>
        <section className="rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-600">
          <p>{t("permissionDenied")}</p>
          <Link href="/courses" className="mt-3 inline-block text-slate-900 underline">
            {t("backToList")}
          </Link>
        </section>
      </div>
    );
  }

  return (
    <div className="mx-auto max-w-2xl space-y-6">
      <div>
        <Link href="/courses" className="text-sm text-slate-600 hover:text-slate-900">
          ← {t("backToList")}
        </Link>
        <h1 className="mt-2 text-xl font-semibold">{t("createCourse")}</h1>
      </div>

      <CourseForm
        mode="create"
        initialValues={{
          code: "",
          name: "",
          levelCode: "",
          status: DEFAULT_COURSE_STATUS,
        }}
      />
    </div>
  );
}
