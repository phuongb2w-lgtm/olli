import Link from "next/link";
import { notFound } from "next/navigation";
import { getTranslations } from "next-intl/server";
import { GuardianCreateForm } from "@/components/guardians/guardian-create-form";
import { GuardianLinkSearch } from "@/components/guardians/guardian-link-search";
import { GuardianRelationshipList } from "@/components/guardians/guardian-relationship-list";
import { queryStudentGuardians } from "@/lib/guardians/query-student-guardians";
import { formatPersonName } from "@/lib/students/format-person-name";
import { can } from "@/lib/permissions/can";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

type Props = {
  params: Promise<{ id: string }>;
  searchParams: Promise<Record<string, string | string[] | undefined>>;
};

export default async function StudentGuardiansPage({ params, searchParams }: Props) {
  const t = await getTranslations("guardians");
  const { id: studentId } = await params;
  const rawParams = await searchParams;
  const success = rawParams.success === "linked" || rawParams.success === "updated" ? rawParams.success : null;

  const hasStudentRead = await can("student.read");
  const hasGuardianRead = await can("guardian.read");
  const hasCreate = await can("guardian.create");
  const hasUpdate = await can("guardian.update");

  if (!hasStudentRead || !hasGuardianRead) {
    return (
      <div className="space-y-4">
        <h1 className="text-xl font-semibold">{t("title")}</h1>
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
  const { data: student, error: studentError } = await supabase
    .from("student")
    .select("id, family_name, given_name, student_code")
    .eq("id", studentId)
    .maybeSingle();

  if (studentError || !student) {
    notFound();
  }

  let guardians;
  try {
    guardians = await queryStudentGuardians(supabase, studentId);
  } catch {
    return (
      <div className="space-y-4">
        <h1 className="text-xl font-semibold">{t("title")}</h1>
        <section className="rounded-lg border border-red-200 bg-red-50 p-4 text-sm text-red-800">
          <p>{t("loadError")}</p>
        </section>
      </div>
    );
  }

  const studentName = formatPersonName(student.family_name, student.given_name);

  return (
    <div className="mx-auto max-w-3xl space-y-6">
      <div>
        <Link href="/students" className="text-sm text-slate-600 hover:text-slate-900">
          ← {t("backToList")}
        </Link>
        <h1 className="mt-2 text-xl font-semibold">{t("title")}</h1>
        <p className="mt-1 text-sm text-slate-600">
          {studentName}
          {student.student_code ? ` · ${student.student_code}` : ""}
        </p>
      </div>

      {success === "linked" ? (
        <p className="rounded-lg border border-green-200 bg-green-50 px-4 py-3 text-sm text-green-800" role="status">
          {t("linkedSuccess")}
        </p>
      ) : null}
      {success === "updated" ? (
        <p className="rounded-lg border border-green-200 bg-green-50 px-4 py-3 text-sm text-green-800" role="status">
          {t("updatedSuccess")}
        </p>
      ) : null}

      <GuardianRelationshipList
        studentId={studentId}
        active={guardians.active}
        ended={guardians.ended}
        canUpdate={hasUpdate}
      />

      {hasCreate ? (
        <>
          <GuardianLinkSearch studentId={studentId} canCreate={hasCreate} />
          <GuardianCreateForm studentId={studentId} canCreate={hasCreate} />
        </>
      ) : null}
    </div>
  );
}
