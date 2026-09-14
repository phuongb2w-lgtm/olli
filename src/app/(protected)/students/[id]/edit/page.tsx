import Link from "next/link";
import { notFound } from "next/navigation";
import { getTranslations } from "next-intl/server";
import { StudentForm } from "@/components/students/student-form";
import { can } from "@/lib/permissions/can";
import type { StudentStatus } from "@/lib/students/constants";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

type Props = {
  params: Promise<{ id: string }>;
};

export default async function EditStudentPage({ params }: Props) {
  const t = await getTranslations("students");
  const { id } = await params;
  const hasUpdate = await can("student.update");

  if (!hasUpdate) {
    return (
      <div className="space-y-4">
        <h1 className="text-xl font-semibold">{t("editStudent")}</h1>
        <section className="rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-600">
          <p>{t("permissionDenied")}</p>
          <Link href="/students" className="mt-3 inline-block text-slate-900 underline">
            {t("backToList")}
          </Link>
        </section>
      </div>
    );
  }

  const supabase = await createClient();
  const { data: student, error } = await supabase
    .from("student")
    .select("id, family_name, given_name, student_code, date_of_birth, status")
    .eq("id", id)
    .maybeSingle();

  if (error || !student) {
    notFound();
  }

  return (
    <div className="mx-auto max-w-2xl space-y-6">
      <div>
        <Link href="/students" className="text-sm text-slate-600 hover:text-slate-900">
          ← {t("backToList")}
        </Link>
        <h1 className="mt-2 text-xl font-semibold">{t("editStudent")}</h1>
      </div>

      <StudentForm
        mode="edit"
        studentId={student.id}
        initialValues={{
          familyName: student.family_name,
          givenName: student.given_name,
          studentCode: student.student_code ?? "",
          dateOfBirth: student.date_of_birth ?? "",
          status: student.status as StudentStatus,
        }}
      />
    </div>
  );
}
