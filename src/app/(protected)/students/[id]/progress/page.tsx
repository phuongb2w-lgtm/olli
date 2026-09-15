import Link from "next/link";
import { notFound } from "next/navigation";
import { getTranslations } from "next-intl/server";
import { StudentProgressList } from "@/components/assessments/student-progress-list";
import {
  computeSimpleAveragePercentage,
  fetchStudentProgress,
} from "@/lib/assessments/query-student-progress";
import { formatPersonName } from "@/lib/students/format-person-name";
import { can } from "@/lib/permissions/can";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

type Props = {
  params: Promise<{ id: string }>;
};

export default async function StudentProgressPage({ params }: Props) {
  const t = await getTranslations("assessments");
  const { id: studentId } = await params;

  const hasRead = await can("assessment.read");
  if (!hasRead) {
    return (
      <div className="space-y-4">
        <h1 className="text-xl font-semibold">{t("academicProgress")}</h1>
        <section className="rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-600">
          <p>{t("denied")}</p>
        </section>
      </div>
    );
  }

  const supabase = await createClient();
  const { data: student, error: studentError } = await supabase
    .from("student")
    .select("id, given_name, family_name")
    .eq("id", studentId)
    .maybeSingle();

  if (studentError || !student) notFound();

  const items = await fetchStudentProgress(supabase, studentId);
  const averagePercentage = computeSimpleAveragePercentage(items);
  const studentName = formatPersonName(student.family_name, student.given_name);

  return (
    <div className="space-y-6">
      <header className="space-y-2">
        <Link href={`/students/${studentId}/enrollments`} className="text-sm text-slate-600 underline">
          {t("backToEnrollments")}
        </Link>
        <h1 className="text-xl font-semibold text-slate-900">{t("academicProgress")}</h1>
        <p className="text-sm text-slate-600">{studentName}</p>
      </header>
      <StudentProgressList items={items} averagePercentage={averagePercentage} />
    </div>
  );
}
