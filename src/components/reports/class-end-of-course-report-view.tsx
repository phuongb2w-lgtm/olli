import type { Locale } from "@/i18n/config";
import type { ClassEndOfCourseReport } from "@/lib/reports/types";
import { formatReportPercentage } from "@/lib/reports/format-report-value";
import { ClassAssessmentReportView } from "./class-assessment-report-view";
import { ClassAttendanceReportView } from "./class-attendance-report-view";
import { ReportHeader } from "./report-header";

type Props = {
  report: ClassEndOfCourseReport;
  locale: Locale;
  labels: Record<string, string>;
  attendanceLabels: Record<string, string>;
  assessmentLabels: Record<string, string>;
  enrollmentStatusLabels: Record<string, string>;
};

export function ClassEndOfCourseReportView({
  report,
  locale,
  labels,
  attendanceLabels,
  assessmentLabels,
  enrollmentStatusLabels,
}: Props) {
  return (
    <article className="report-content space-y-8">
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

      <section aria-labelledby="eoc-summary-heading">
        <h2 id="eoc-summary-heading" className="mb-3 text-lg font-semibold">
          {labels.summary}
        </h2>
        <dl className="grid gap-4 text-sm sm:grid-cols-2 lg:grid-cols-3">
          <div className="rounded border border-slate-200 p-3">
            <dt className="font-medium text-slate-500">{labels.classStatus}</dt>
            <dd className="mt-1 font-semibold">{report.context.classStatus}</dd>
          </div>
          <div className="rounded border border-slate-200 p-3">
            <dt className="font-medium text-slate-500">{labels.completedSessions}</dt>
            <dd className="mt-1 font-semibold">{report.sessions.completed}</dd>
          </div>
          <div className="rounded border border-slate-200 p-3">
            <dt className="font-medium text-slate-500">{labels.cancelledSessions}</dt>
            <dd className="mt-1 font-semibold">{report.sessions.cancelled}</dd>
          </div>
          <div className="rounded border border-slate-200 p-3">
            <dt className="font-medium text-slate-500">{labels.enrollmentCount}</dt>
            <dd className="mt-1 font-semibold">{report.enrollments.total}</dd>
          </div>
          <div className="rounded border border-slate-200 p-3">
            <dt className="font-medium text-slate-500">{labels.averageAttendanceRate}</dt>
            <dd className="mt-1 font-semibold">
              {formatReportPercentage(report.attendance.averageAttendanceRate, locale)}
            </dd>
          </div>
          <div className="rounded border border-slate-200 p-3">
            <dt className="font-medium text-slate-500">{labels.assessmentMean}</dt>
            <dd className="mt-1 font-semibold">
              {formatReportPercentage(report.assessments.meanPercentage, locale)}
            </dd>
          </div>
        </dl>
      </section>

      <section aria-labelledby="enrollment-breakdown-heading">
        <h2 id="enrollment-breakdown-heading" className="mb-2 text-lg font-semibold">
          {labels.enrollmentStatus}
        </h2>
        {Object.keys(report.enrollments.byStatus).length === 0 ? (
          <p className="text-sm text-slate-600">{labels.noEnrollments}</p>
        ) : (
          <ul className="grid gap-2 text-sm sm:grid-cols-2">
            {Object.entries(report.enrollments.byStatus).map(([status, count]) => (
              <li key={status} className="flex justify-between rounded border border-slate-200 px-3 py-2">
                <span>{enrollmentStatusLabels[status] ?? status}</span>
                <span className="font-medium">{count}</span>
              </li>
            ))}
          </ul>
        )}
      </section>

      {report.includesObservations && report.observations ? (
        <section aria-labelledby="observation-summary-heading">
          <h2 id="observation-summary-heading" className="mb-2 text-lg font-semibold">
            {labels.observations}
          </h2>
          {report.observations.ratingDistribution.length === 0 &&
          report.observations.commentCount === 0 ? (
            <p className="text-sm text-slate-600">{labels.noObservations}</p>
          ) : (
            <>
              <p className="mb-2 text-sm text-slate-600">
                {labels.sessionsWithObservations}: {report.observations.sessionCount}
              </p>
              {report.observations.ratingDistribution.length > 0 ? (
                <table className="min-w-full divide-y divide-slate-200 text-sm">
                  <thead className="bg-slate-50">
                    <tr>
                      <th scope="col" className="px-3 py-2 text-left">{labels.indicator}</th>
                      <th scope="col" className="px-3 py-2 text-left">{labels.rating}</th>
                      <th scope="col" className="px-3 py-2 text-right">{labels.count}</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-slate-200">
                    {report.observations.ratingDistribution.map((row) => (
                      <tr key={`${row.indicatorCode}-${row.ratingCode}`}>
                        <td className="px-3 py-2">{row.indicatorCode}</td>
                        <td className="px-3 py-2">{row.ratingCode}</td>
                        <td className="px-3 py-2 text-right">{row.count}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              ) : null}
              <p className="mt-2 text-sm text-slate-600">
                {labels.teacherComments}: {report.observations.commentCount}
              </p>
            </>
          )}
        </section>
      ) : !report.includesObservations ? (
        <p className="text-sm text-slate-500">{labels.observationsLimited}</p>
      ) : null}

      <section className="break-before-page space-y-4">
        <h2 className="text-lg font-semibold">{labels.attendanceDetail}</h2>
        <ClassAttendanceReportView
          report={report.attendanceReport}
          locale={locale}
          labels={attendanceLabels}
        />
      </section>

      <section className="break-before-page space-y-4">
        <h2 className="text-lg font-semibold">{labels.assessmentDetail}</h2>
        <ClassAssessmentReportView
          report={report.assessmentReport}
          locale={locale}
          labels={assessmentLabels}
        />
      </section>
    </article>
  );
}
