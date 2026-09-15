import type { Locale } from "@/i18n/config";
import type { ClassAttendanceReport } from "@/lib/reports/types";
import { formatReportPercentage } from "@/lib/reports/format-report-value";
import { ReportHeader } from "./report-header";

type Props = {
  report: ClassAttendanceReport;
  locale: Locale;
  labels: Record<string, string>;
};

export function ClassAttendanceReportView({ report, locale, labels }: Props) {
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

      <section aria-labelledby="session-totals-heading">
        <h2 id="session-totals-heading" className="mb-2 text-lg font-semibold text-slate-900">
          {labels.teachingSessions}
        </h2>
        <dl className="grid gap-2 text-sm sm:grid-cols-3">
          <div>
            <dt className="text-slate-500">{labels.materializedSessions}</dt>
            <dd className="font-medium">{report.sessionTotals.materialized}</dd>
          </div>
          <div>
            <dt className="text-slate-500">{labels.completedSessions}</dt>
            <dd className="font-medium">{report.sessionTotals.completed}</dd>
          </div>
          <div>
            <dt className="text-slate-500">{labels.cancelledSessions}</dt>
            <dd className="font-medium">{report.sessionTotals.cancelled}</dd>
          </div>
        </dl>
      </section>

      <section aria-labelledby="attendance-table-heading">
        <h2 id="attendance-table-heading" className="mb-2 text-lg font-semibold text-slate-900">
          {labels.attendanceByLearner}
        </h2>
        {report.learners.length === 0 ? (
          <p className="text-sm text-slate-600">{labels.noLearners}</p>
        ) : (
          <div className="overflow-x-auto">
            <table className="min-w-full divide-y divide-slate-200 text-sm">
              <thead className="bg-slate-50">
                <tr>
                  <th scope="col" className="px-3 py-2 text-left font-medium">{labels.student}</th>
                  <th scope="col" className="px-3 py-2 text-left font-medium">{labels.studentCode}</th>
                  <th scope="col" className="px-3 py-2 text-right font-medium">{labels.eligibleSessions}</th>
                  <th scope="col" className="px-3 py-2 text-right font-medium">{labels.present}</th>
                  <th scope="col" className="px-3 py-2 text-right font-medium">{labels.absent}</th>
                  <th scope="col" className="px-3 py-2 text-right font-medium">{labels.late}</th>
                  <th scope="col" className="px-3 py-2 text-right font-medium">{labels.excused}</th>
                  <th scope="col" className="px-3 py-2 text-right font-medium">{labels.notRecorded}</th>
                  <th scope="col" className="px-3 py-2 text-right font-medium">{labels.attendanceRate}</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-200 bg-white">
                {report.learners.map((row) => (
                  <tr key={row.enrollmentId}>
                    <td className="px-3 py-2">{row.studentName}</td>
                    <td className="px-3 py-2">{row.studentCode ?? "—"}</td>
                    <td className="px-3 py-2 text-right">{row.eligibleSessions}</td>
                    <td className="px-3 py-2 text-right">{row.presentCount}</td>
                    <td className="px-3 py-2 text-right">{row.absentCount}</td>
                    <td className="px-3 py-2 text-right">{row.lateCount}</td>
                    <td className="px-3 py-2 text-right">{row.excusedCount}</td>
                    <td className="px-3 py-2 text-right">{row.notRecordedCount}</td>
                    <td className="px-3 py-2 text-right">
                      {formatReportPercentage(row.attendanceRate, locale)}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>
    </article>
  );
}
