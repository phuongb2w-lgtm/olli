import Link from "next/link";
import { getTranslations } from "next-intl/server";
import type { AssessmentListItem } from "@/lib/assessments/query-class-assessments";

type Props = {
  classId: string;
  items: AssessmentListItem[];
  canRecord: boolean;
};

export async function AssessmentList({ classId, items, canRecord }: Props) {
  const t = await getTranslations("assessments");
  const tStatus = await getTranslations("status.assessment");

  if (items.length === 0) {
    return <p className="text-sm text-slate-600">{t("noAssessments")}</p>;
  }

  return (
    <>
      <div className="hidden overflow-x-auto lg:block">
        <table className="min-w-full divide-y divide-slate-200 text-sm">
          <thead className="bg-slate-50">
            <tr>
              <th className="px-4 py-3 text-left font-medium text-slate-700">{t("titleField")}</th>
              <th className="px-4 py-3 text-left font-medium text-slate-700">{t("assessmentDate")}</th>
              <th className="px-4 py-3 text-left font-medium text-slate-700">{t("maximumScore")}</th>
              <th className="px-4 py-3 text-left font-medium text-slate-700">{t("status")}</th>
              <th className="px-4 py-3 text-left font-medium text-slate-700">{t("results")}</th>
              <th className="px-4 py-3 text-left font-medium text-slate-700">
                <span className="sr-only">{t("actions")}</span>
              </th>
            </tr>
          </thead>
          <tbody className="divide-y divide-slate-200 bg-white">
            {items.map((item) => (
              <tr key={item.id}>
                <td className="px-4 py-3 font-medium text-slate-900">{item.title}</td>
                <td className="px-4 py-3 text-slate-700">{item.assessedOn}</td>
                <td className="px-4 py-3 text-slate-700">{item.maxScore}</td>
                <td className="px-4 py-3">
                  <span className="inline-flex rounded-full bg-slate-100 px-2.5 py-0.5 text-xs font-medium text-slate-800">
                    {tStatus(item.status)}
                  </span>
                </td>
                <td className="px-4 py-3 text-slate-700">
                  {t("learnersScored", { scored: item.scoredCount, total: item.eligibleCount })}
                </td>
                <td className="px-4 py-3">
                  <Link
                    href={`/classes/${classId}/assessments/${item.id}`}
                    className="text-sm font-medium text-slate-900 underline"
                  >
                    {canRecord ? t("recordScores") : t("viewResults")}
                  </Link>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <ul className="space-y-3 lg:hidden">
        {items.map((item) => (
          <li key={item.id} className="rounded-lg border border-slate-200 bg-white p-4 text-sm">
            <p className="font-medium text-slate-900">{item.title}</p>
            <p className="text-slate-600">{item.assessedOn}</p>
            <p className="text-slate-600">
              {t("maximumScore")}: {item.maxScore}
            </p>
            <p className="text-slate-600">
              {t("learnersScored", { scored: item.scoredCount, total: item.eligibleCount })}
            </p>
            <Link
              href={`/classes/${classId}/assessments/${item.id}`}
              className="mt-2 inline-block text-sm font-medium text-slate-900 underline"
            >
              {canRecord ? t("recordScores") : t("viewResults")}
            </Link>
          </li>
        ))}
      </ul>
    </>
  );
}
