import Link from "next/link";
import { getTranslations } from "next-intl/server";
import { StudentForm } from "@/components/students/student-form";
import { DEFAULT_STUDENT_STATUS } from "@/lib/students/constants";
import { can } from "@/lib/permissions/can";

export const dynamic = "force-dynamic";

export default async function NewStudentPage() {
  const t = await getTranslations("students");
  const hasCreate = await can("student.create");

  if (!hasCreate) {
    return (
      <div className="space-y-4">
        <h1 className="text-xl font-semibold">{t("createStudent")}</h1>
        <section className="rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-600">
          <p>{t("permissionDenied")}</p>
          <Link href="/students" className="mt-3 inline-block text-slate-900 underline">
            {t("backToList")}
          </Link>
        </section>
      </div>
    );
  }

  return (
    <div className="mx-auto max-w-2xl space-y-6">
      <div>
        <Link href="/students" className="text-sm text-slate-600 hover:text-slate-900">
          ← {t("backToList")}
        </Link>
        <h1 className="mt-2 text-xl font-semibold">{t("createStudent")}</h1>
      </div>

      <StudentForm
        mode="create"
        initialValues={{
          familyName: "",
          givenName: "",
          studentCode: "",
          dateOfBirth: "",
          status: DEFAULT_STUDENT_STATUS,
        }}
      />
    </div>
  );
}
