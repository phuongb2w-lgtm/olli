import Link from "next/link";
import { notFound } from "next/navigation";
import { getTranslations } from "next-intl/server";
import { EnrollmentForm } from "@/components/enrollments/enrollment-form";
import { formatPersonName } from "@/lib/students/format-person-name";
import { can } from "@/lib/permissions/can";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

type Props = {
  params: Promise<{ id: string }>;
};

export default async function EnrollFromStudentPage({ params }: Props) {
  const t = await getTranslations("enrollments");
  const hasCreate = await can("enrollment.create");

  if (!hasCreate) {
    return (
      <div className="space-y-4">
        <h1 className="text-xl font-semibold">{t("enrollStudent")}</h1>
        <section className="rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-600">
          <p>{t("permissionDenied")}</p>
        </section>
      </div>
    );
  }

  const { id: studentId } = await params;
  const supabase = await createClient();

  const { data: student, error: studentError } = await supabase
    .from("student")
    .select("id, given_name, family_name")
    .eq("id", studentId)
    .maybeSingle();

  if (studentError || !student) notFound();

  const { data: classes, error: classError } = await supabase
    .from("class")
    .select("id, name, status, course_id")
    .neq("status", "closed")
    .order("name", { ascending: true });

  if (classError) {
    return (
      <div className="space-y-4">
        <h1 className="text-xl font-semibold">{t("enrollStudent")}</h1>
        <p className="text-sm text-red-600">{t("loadError")}</p>
      </div>
    );
  }

  const studentName = formatPersonName(student.family_name, student.given_name);
  const courseIds = [...new Set((classes ?? []).map((c) => c.course_id))];
  const courseCodeById = new Map<string, string>();
  if (courseIds.length > 0) {
    const { data: courses } = await supabase.from("course").select("id, code").in("id", courseIds);
    for (const c of courses ?? []) courseCodeById.set(c.id, c.code);
  }

  const classOptions = (classes ?? []).map((row) => ({
    id: row.id,
    name: row.name,
    courseCode: courseCodeById.get(row.course_id) ?? "",
    status: row.status,
  }));

  return (
    <div className="mx-auto max-w-2xl space-y-6">
      <div>
        <Link
          href={`/students/${studentId}/enrollments`}
          className="text-sm text-slate-600 hover:text-slate-900"
        >
          ← {t("backToHistory")}
        </Link>
        <h1 className="mt-2 text-xl font-semibold">{t("enrollStudent")}</h1>
      </div>

      {classOptions.length === 0 ? (
        <section className="rounded-lg border border-amber-200 bg-amber-50 p-4 text-sm text-amber-900">
          <p>{t("noOpenClasses")}</p>
        </section>
      ) : (
        <EnrollmentForm
          mode="fromStudent"
          studentId={student.id}
          studentName={studentName}
          classes={classOptions}
          returnTo="student"
          backHref={`/students/${studentId}/enrollments`}
          initialValues={{
            studentId: student.id,
            classId: "",
            startDate: new Date().toISOString().slice(0, 10),
            status: "pending",
          }}
        />
      )}
    </div>
  );
}
