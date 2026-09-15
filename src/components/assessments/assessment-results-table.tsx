import { getTranslations } from "next-intl/server";
import { ScoreEntryRow } from "@/components/assessments/score-entry-row";
import type { AssessmentResultRow } from "@/lib/assessments/query-class-assessments";

type Props = {
  classId: string;
  assessmentId: string;
  maxScore: number;
  rows: AssessmentResultRow[];
  canRecord: boolean;
};

export async function AssessmentResultsTable({
  classId,
  assessmentId,
  maxScore,
  rows,
  canRecord,
}: Props) {
  const t = await getTranslations("assessments");

  if (rows.length === 0) {
    return <p className="text-sm text-slate-600">{t("emptyRoster")}</p>;
  }

  return (
    <>
      <div className="hidden overflow-x-auto lg:block">
        <table className="min-w-full divide-y divide-slate-200 text-sm">
          <thead className="bg-slate-50">
            <tr>
              <th className="px-4 py-3 text-left font-medium text-slate-700">{t("student")}</th>
              <th className="px-4 py-3 text-left font-medium text-slate-700">{t("studentCode")}</th>
              <th className="px-4 py-3 text-left font-medium text-slate-700">{t("testScore")}</th>
              <th className="px-4 py-3 text-left font-medium text-slate-700">{t("percentage")}</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-slate-200 bg-white">
            {rows.map((row) => (
              <tr key={row.enrollmentId}>
                <td className="px-4 py-3 font-medium text-slate-900">{row.studentName}</td>
                <td className="px-4 py-3 text-slate-700">{row.studentCode ?? "—"}</td>
                <td className="px-4 py-3">
                  <ScoreEntryRow
                    classId={classId}
                    assessmentId={assessmentId}
                    maxScore={maxScore}
                    row={row}
                    canRecord={canRecord}
                  />
                </td>
                <td className="px-4 py-3 text-slate-700">
                  {row.percentage !== null ? `${row.percentage}%` : t("noScoreRecorded")}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <ul className="space-y-3 lg:hidden">
        {rows.map((row) => (
          <li key={row.enrollmentId} className="rounded-lg border border-slate-200 bg-white p-4 text-sm">
            <p className="font-medium text-slate-900">{row.studentName}</p>
            <p className="text-slate-600">{row.studentCode ?? "—"}</p>
            <div className="mt-2">
              <ScoreEntryRow
                classId={classId}
                assessmentId={assessmentId}
                maxScore={maxScore}
                row={row}
                canRecord={canRecord}
              />
            </div>
            <p className="mt-1 text-slate-600">
              {t("percentage")}:{" "}
              {row.percentage !== null ? `${row.percentage}%` : t("noScoreRecorded")}
            </p>
          </li>
        ))}
      </ul>
    </>
  );
}
