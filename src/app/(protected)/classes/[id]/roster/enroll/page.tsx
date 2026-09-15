import Link from "next/link";
import { notFound } from "next/navigation";
import { getTranslations } from "next-intl/server";
import { EnrollmentForm } from "@/components/enrollments/enrollment-form";
import { canEnrollInClass } from "@/lib/enrollments/class-enrollment-rules";
import type { ClassStatus } from "@/lib/academic/constants";
import { can } from "@/lib/permissions/can";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

type Props = {
  params: Promise<{ id: string }>;
};

export default async function EnrollFromClassPage({ params }: Props) {
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

  const { id: classId } = await params;
  const supabase = await createClient();
  const { data: classRow, error } = await supabase
    .from("class")
    .select("id, name, status")
    .eq("id", classId)
    .maybeSingle();

  if (error || !classRow) notFound();

  if (!canEnrollInClass(classRow.status as ClassStatus)) {
    return (
      <div className="space-y-4">
        <h1 className="text-xl font-semibold">{t("enrollStudent")}</h1>
        <section className="rounded-lg border border-amber-200 bg-amber-50 p-4 text-sm text-amber-900">
          <p>{t("classClosed")}</p>
          <Link href={`/classes/${classId}/roster`} className="mt-3 inline-block underline">
            {t("backToRoster")}
          </Link>
        </section>
      </div>
    );
  }

  return (
    <div className="mx-auto max-w-2xl space-y-6">
      <div>
        <Link
          href={`/classes/${classId}/roster`}
          className="text-sm text-slate-600 hover:text-slate-900"
        >
          ← {t("backToRoster")}
        </Link>
        <h1 className="mt-2 text-xl font-semibold">{t("enrollStudent")}</h1>
      </div>

      <EnrollmentForm
        mode="fromClass"
        classId={classRow.id}
        className={classRow.name}
        returnTo="roster"
        backHref={`/classes/${classId}/roster`}
        initialValues={{
          studentId: "",
          classId: classRow.id,
          startDate: new Date().toISOString().slice(0, 10),
          status: "pending",
        }}
      />
    </div>
  );
}
