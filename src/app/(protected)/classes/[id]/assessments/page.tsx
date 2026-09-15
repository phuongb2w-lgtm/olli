import Link from "next/link";
import { notFound } from "next/navigation";
import { getTranslations } from "next-intl/server";
import { AssessmentForm } from "@/components/assessments/assessment-form";
import { AssessmentList } from "@/components/assessments/assessment-list";
import {
  fetchClassAssessmentContext,
  fetchClassAssessments,
} from "@/lib/assessments/query-class-assessments";
import { can } from "@/lib/permissions/can";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

type Props = {
  params: Promise<{ id: string }>;
  searchParams: Promise<Record<string, string | string[] | undefined>>;
};

export default async function ClassAssessmentsPage({ params, searchParams }: Props) {
  const t = await getTranslations("assessments");
  const { id: classId } = await params;
  const rawParams = await searchParams;

  const hasRead = await can("assessment.read");
  if (!hasRead) {
    return (
      <div className="space-y-4">
        <h1 className="text-xl font-semibold">{t("title")}</h1>
        <section className="rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-600">
          <p>{t("denied")}</p>
        </section>
      </div>
    );
  }

  const canCreate = await can("assessment.create");
  const canRecord = await can("assessment_result.record");
  const supabase = await createClient();
  const classContext = await fetchClassAssessmentContext(supabase, classId);
  if (!classContext) notFound();

  const assessments = await fetchClassAssessments(supabase, classId);
  const success = rawParams.success;
  const successKey = typeof success === "string" ? success : undefined;
  const today = new Date().toISOString().slice(0, 10);

  return (
    <div className="space-y-8">
      <header className="space-y-2">
        <Link href="/classes" className="text-sm text-slate-600 underline">
          {t("backToClasses")}
        </Link>
        <h1 className="text-xl font-semibold text-slate-900">
          {t("title")} — {classContext.name}
        </h1>
        <p className="text-sm text-slate-600">{t("subtitle")}</p>
        {successKey ? (
          <p className="rounded-md bg-green-50 px-3 py-2 text-sm text-green-800" role="status">
            {t(`success.${successKey}`)}
          </p>
        ) : null}
      </header>

      <section className="space-y-4">
        <h2 className="text-lg font-semibold text-slate-900">{t("assessmentsList")}</h2>
        <AssessmentList classId={classId} items={assessments} canRecord={canRecord} />
      </section>

      {canCreate && classContext.status !== "closed" ? (
        <section>
          <AssessmentForm classId={classId} defaultAssessedOn={today} />
        </section>
      ) : null}
    </div>
  );
}
