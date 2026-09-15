import Link from "next/link";
import { notFound } from "next/navigation";
import { getTranslations } from "next-intl/server";
import { AssessmentEditForm } from "@/components/assessments/assessment-edit-form";
import { AssessmentResultsTable } from "@/components/assessments/assessment-results-table";
import {
  countResultProgress,
  fetchAssessmentDetail,
  fetchAssessmentResults,
} from "@/lib/assessments/query-class-assessments";
import { can } from "@/lib/permissions/can";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

type Props = {
  params: Promise<{ id: string; assessmentId: string }>;
  searchParams: Promise<Record<string, string | string[] | undefined>>;
};

export default async function AssessmentResultsPage({ params, searchParams }: Props) {
  const t = await getTranslations("assessments");
  const tStatus = await getTranslations("status.assessment");
  const { id: classId, assessmentId } = await params;
  const rawParams = await searchParams;

  const hasRead = await can("assessment.read");
  if (!hasRead) {
    return (
      <div className="space-y-4">
        <h1 className="text-xl font-semibold">{t("results")}</h1>
        <section className="rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-600">
          <p>{t("denied")}</p>
        </section>
      </div>
    );
  }

  const canCreate = await can("assessment.create");
  const canRecord = await can("assessment_result.record");
  const supabase = await createClient();
  const assessment = await fetchAssessmentDetail(supabase, classId, assessmentId);
  if (!assessment) notFound();

  const rows = await fetchAssessmentResults(supabase, assessment);
  const progress = countResultProgress(rows);

  const success = rawParams.success;
  const successKey = typeof success === "string" ? success : undefined;

  return (
    <div className="space-y-8">
      <header className="space-y-3">
        <Link
          href={`/classes/${classId}/assessments`}
          className="text-sm text-slate-600 underline"
        >
          {t("backToAssessments")}
        </Link>
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div>
            <h1 className="text-xl font-semibold text-slate-900">{assessment.title}</h1>
            <p className="text-sm text-slate-600">
              {assessment.className}
              {assessment.courseCode ? ` · ${assessment.courseCode}` : ""}
            </p>
          </div>
          <span className="inline-flex rounded-full bg-slate-100 px-3 py-1 text-sm font-medium text-slate-800">
            {tStatus(assessment.status)}
          </span>
        </div>
        <dl className="grid gap-2 text-sm sm:grid-cols-2 lg:grid-cols-3">
          <div>
            <dt className="text-slate-500">{t("assessmentDate")}</dt>
            <dd className="font-medium text-slate-900">{assessment.assessedOn}</dd>
          </div>
          <div>
            <dt className="text-slate-500">{t("maximumScore")}</dt>
            <dd className="font-medium text-slate-900">{assessment.maxScore}</dd>
          </div>
          <div>
            <dt className="text-slate-500">{t("results")}</dt>
            <dd className="font-medium text-slate-900">
              {t("learnersScored", { scored: progress.scored, total: progress.total })}
            </dd>
          </div>
        </dl>
        {successKey ? (
          <p className="rounded-md bg-green-50 px-3 py-2 text-sm text-green-800" role="status">
            {t(`success.${successKey}`)}
          </p>
        ) : null}
      </header>

      {canCreate ? (
        <section>
          <AssessmentEditForm assessment={assessment} />
        </section>
      ) : null}

      <section className="space-y-4">
        <h2 className="text-lg font-semibold text-slate-900">{t("recordScores")}</h2>
        <AssessmentResultsTable
          classId={classId}
          assessmentId={assessmentId}
          maxScore={assessment.maxScore}
          rows={rows}
          canRecord={canRecord}
        />
      </section>
    </div>
  );
}
