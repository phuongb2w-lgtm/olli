import type { Locale } from "@/i18n/config";
import type { ClassAssessmentReport } from "@/lib/reports/types";
import {
  formatReportDate,
  formatReportPercentage,
  formatReportScore,
} from "@/lib/reports/format-report-value";
import { ReportHeader } from "./report-header";

type Props = {
  report: ClassAssessmentReport;
  locale: Locale;
  labels: Record<string, string>;
};

export function ClassAssessmentReportView({ report, locale, labels }: Props) {
  return (
    <article className="report-content space-y-6">
      <ReportHeader
        branding={report.branding}
        title={labels.title}
        context={report.context}
        period={report.period}
        generatedAt={report.generatedAt}
        locale={locale}
        labels={{
          course: labels.course,
          class: labels.class,
          student: labels.student,
          studentCode: labels.studentCode,
          period: labels.period,
          generatedOn: labels.generatedOn,
          from: labels.from,
          to: labels.to,
        }}
      />

      {report.assessments.length === 0 ? (
        <p className="text-sm text-slate-600">{labels.noAssessments}</p>
      ) : (
        <>
          <section aria-labelledby="assessment-aggregate-heading">
            <h2 id="assessment-aggregate-heading" className="mb-2 text-lg font-semibold">
              {labels.summary}
            </h2>
            <dl className="grid gap-2 text-sm sm:grid-cols-2 lg:grid-cols-4">
              <div>
                <dt className="text-slate-500">{labels.learnersScored}</dt>
                <dd>{report.aggregates.scoredCount}</dd>
              </div>
              <div>
                <dt className="text-slate-500">{labels.noScoreRecorded}</dt>
                <dd>{report.aggregates.withoutScoreCount}</dd>
              </div>
              <div>
                <dt className="text-slate-500">{labels.averagePercentage}</dt>
                <dd>{formatReportPercentage(report.aggregates.meanPercentage, locale)}</dd>
              </div>
              <div>
                <dt className="text-slate-500">{labels.highestLowest}</dt>
                <dd>
                  {formatReportPercentage(report.aggregates.maxPercentage, locale)} /{" "}
                  {formatReportPercentage(report.aggregates.minPercentage, locale)}
                </dd>
              </div>
            </dl>
          </section>

          <section aria-labelledby="assessment-table-heading">
            <h2 id="assessment-table-heading" className="mb-2 text-lg font-semibold">
              {labels.resultsByLearner}
            </h2>
            <div className="overflow-x-auto">
              <table className="min-w-full divide-y divide-slate-200 text-sm">
                <thead className="bg-slate-50">
                  <tr>
                    <th scope="col" className="px-3 py-2 text-left font-medium">{labels.student}</th>
                    {report.assessments.map((a) => (
                      <th key={a.id} scope="col" className="px-3 py-2 text-left font-medium">
                        <span className="block">{a.title}</span>
                        <span className="text-xs font-normal text-slate-500">
                          {formatReportDate(a.assessedOn, locale)}
                        </span>
                      </th>
                    ))}
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-200 bg-white">
                  {report.learners.map((learner) => (
                    <tr key={learner.enrollmentId}>
                      <td className="px-3 py-2">{learner.studentName}</td>
                      {learner.cells.map((cell) => (
                        <td key={cell.assessmentId} className="px-3 py-2">
                          {cell.hasScore ? (
                            <>
                              <span className="block">
                                {formatReportScore(cell.rawScore, cell.maxScore, locale)}
                              </span>
                              <span className="text-xs text-slate-500">
                                {formatReportPercentage(cell.percentage, locale)}
                              </span>
                            </>
                          ) : (
                            <span className="text-slate-500">{labels.noScoreRecorded}</span>
                          )}
                        </td>
                      ))}
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </section>
        </>
      )}
    </article>
  );
}
