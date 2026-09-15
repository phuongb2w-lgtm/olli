import { getTranslations } from "next-intl/server";
import type { StudentProgressItem } from "@/lib/assessments/query-student-progress";

type Props = {
  items: StudentProgressItem[];
  averagePercentage: number | null;
};

export async function StudentProgressList({ items, averagePercentage }: Props) {
  const t = await getTranslations("assessments");

  if (items.length === 0) {
    return (
      <section className="rounded-lg border border-slate-200 bg-white p-6 text-sm text-slate-600">
        <p>{t("noProgress")}</p>
      </section>
    );
  }

  return (
    <div className="space-y-4">
      {averagePercentage !== null ? (
        <p className="text-sm text-slate-600">
          {t("simpleAveragePercentage", { value: averagePercentage })}
        </p>
      ) : null}
      <div className="hidden overflow-x-auto lg:block">
        <table className="min-w-full divide-y divide-slate-200 text-sm">
          <thead className="bg-slate-50">
            <tr>
              <th className="px-4 py-3 text-left font-medium text-slate-700">{t("class")}</th>
              <th className="px-4 py-3 text-left font-medium text-slate-700">{t("assessment")}</th>
              <th className="px-4 py-3 text-left font-medium text-slate-700">{t("assessmentDate")}</th>
              <th className="px-4 py-3 text-left font-medium text-slate-700">{t("testScore")}</th>
              <th className="px-4 py-3 text-left font-medium text-slate-700">{t("percentage")}</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-slate-200 bg-white">
            {items.map((item) => (
              <tr key={item.resultId}>
                <td className="px-4 py-3">
                  <span className="block font-medium text-slate-900">{item.className}</span>
                  {item.courseCode ? (
                    <span className="text-xs text-slate-500">{item.courseCode}</span>
                  ) : null}
                </td>
                <td className="px-4 py-3 text-slate-900">{item.assessmentTitle}</td>
                <td className="px-4 py-3 text-slate-700">{item.assessedOn}</td>
                <td className="px-4 py-3 text-slate-700">
                  {item.rawScore} / {item.maxScore}
                </td>
                <td className="px-4 py-3 text-slate-700">
                  {item.percentage !== null ? `${item.percentage}%` : "—"}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <ul className="space-y-3 lg:hidden">
        {items.map((item) => (
          <li key={item.resultId} className="rounded-lg border border-slate-200 bg-white p-4 text-sm">
            <p className="font-medium text-slate-900">{item.assessmentTitle}</p>
            <p className="text-slate-600">{item.className}</p>
            <p className="text-slate-600">{item.assessedOn}</p>
            <p className="mt-1 font-medium text-slate-900">
              {item.rawScore} / {item.maxScore}
              {item.percentage !== null ? ` (${item.percentage}%)` : ""}
            </p>
          </li>
        ))}
      </ul>
    </div>
  );
}
