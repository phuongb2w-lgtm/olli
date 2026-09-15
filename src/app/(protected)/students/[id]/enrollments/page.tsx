import Link from "next/link";
import { notFound } from "next/navigation";
import { getTranslations } from "next-intl/server";
import { StudentEnrollmentList } from "@/components/enrollments/student-enrollment-list";
import { queryStudentEnrollments } from "@/lib/enrollments/query-student-enrollments";
import { formatPersonName } from "@/lib/students/format-person-name";
import { can } from "@/lib/permissions/can";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

type Props = {
  params: Promise<{ id: string }>;
  searchParams: Promise<Record<string, string | string[] | undefined>>;
};

export default async function StudentEnrollmentsPage({ params, searchParams }: Props) {
  const t = await getTranslations("enrollments");
  const tReports = await getTranslations("reports");
  const { id: studentId } = await params;
  const rawParams = await searchParams;
  const hasRead = await can("enrollment.read");

  if (!hasRead) {
    return (
      <div className="space-y-4">
        <h1 className="text-xl font-semibold">{t("enrollmentHistory")}</h1>
        <section className="rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-600">
          <p>{t("denied")}</p>
        </section>
      </div>
    );
  }

  const hasCreate = await can("enrollment.create");
  const [canViewProgressAssessment, canViewProgressAttendance] = await Promise.all([
    can("assessment.read"),
    can("attendance.read"),
  ]);
  const canViewProgress = canViewProgressAssessment || canViewProgressAttendance;
  const success = rawParams.success === "created" ? "created" : null;

  const supabase = await createClient();
  const { data: student, error: studentError } = await supabase
    .from("student")
    .select("id, given_name, family_name")
    .eq("id", studentId)
    .maybeSingle();

  if (studentError || !student) notFound();

  const { items, error } = await queryStudentEnrollments(supabase, studentId);

  if (error) {
    return (
      <div className="space-y-4">
        <h1 className="text-xl font-semibold">{t("enrollmentHistory")}</h1>
        <section className="rounded-lg border border-red-200 bg-red-50 p-4 text-sm text-red-800">
          <p>{t("loadError")}</p>
        </section>
      </div>
    );
  }

  const studentName = formatPersonName(student.family_name, student.given_name);

  return (
    <div className="space-y-6">
      <div>
        <Link href="/students" className="text-sm text-slate-600 hover:text-slate-900">
          ← {t("backToStudents")}
        </Link>
        <h1 className="mt-2 text-xl font-semibold">{t("enrollmentHistory")}</h1>
        <p className="mt-1 text-sm text-slate-600">{studentName}</p>
      </div>

      <div className="flex flex-wrap gap-3">
        {hasCreate ? (
          <Link
            href={`/students/${studentId}/enrollments/enroll`}
            className="inline-block rounded bg-slate-900 px-4 py-2 text-sm font-medium text-white hover:bg-slate-800"
          >
            {t("enrollStudent")}
          </Link>
        ) : null}
        {canViewProgress ? (
          <Link
            href={`/students/${studentId}/reports/progress`}
            className="inline-block rounded border border-slate-300 px-4 py-2 text-sm font-medium text-slate-800 hover:bg-slate-50"
          >
            {tReports("learnerProgressReport")}
          </Link>
        ) : null}
      </div>

      {success === "created" ? (
        <p className="rounded-lg border border-green-200 bg-green-50 px-4 py-3 text-sm text-green-800" role="status">
          {t("createdSuccess")}
        </p>
      ) : null}

      <StudentEnrollmentList items={items} />
    </div>
  );
}
