import type { Locale } from "@/i18n/config";
import type { StudentProgressReport } from "@/lib/reports/types";
import {
  formatReportDate,
  formatReportPercentage,
  formatReportScore,
} from "@/lib/reports/format-report-value";
import { ReportHeader } from "./report-header";

type Props = {
  report: StudentProgressReport;
  locale: Locale;
  labels: Record<string, string>;
  enrollmentStatusLabels: Record<string, string>;
  observationIndicatorLabels: Record<string, string>;
  observationRatingLabels: Record<string, string>;
};

export function StudentProgressReportView({
  report,
  locale,
  labels,
  enrollmentStatusLabels,
  observationIndicatorLabels,
  observationRatingLabels,
}: Props) {
  return (
    <article className="report-content space-y-6">
      <ReportHeader
        branding={report.branding}
        title={labels.title}
        studentName={report.studentName}
        studentCode={report.studentCode}
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

      {report.enrollmentScope ? (
        <section aria-labelledby="enrollment-scope-heading">
          <h2 id="enrollment-scope-heading" className="mb-2 text-lg font-semibold">
            {labels.enrollmentContext}
          </h2>
          <dl className="grid gap-2 text-sm sm:grid-cols-2">
            <div>
              <dt className="text-slate-500">{labels.class}</dt>
              <dd>{report.enrollmentScope.className}</dd>
            </div>
            <div>
              <dt className="text-slate-500">{labels.course}</dt>
              <dd>{report.enrollmentScope.courseCode ?? "—"}</dd>
            </div>
            <div>
              <dt className="text-slate-500">{labels.enrollmentStatus}</dt>
              <dd>
                {enrollmentStatusLabels[report.enrollmentScope.enrollmentStatus] ??
                  report.enrollmentScope.enrollmentStatus}
              </dd>
            </div>
            <div>
              <dt className="text-slate-500">{labels.enrollmentDates}</dt>
              <dd>
                {formatReportDate(report.enrollmentScope.startDate, locale)}
                {" — "}
                {report.enrollmentScope.endDate
                  ? formatReportDate(report.enrollmentScope.endDate, locale)
                  : labels.ongoing}
              </dd>
            </div>
          </dl>
        </section>
      ) : null}

      <section aria-labelledby="attendance-summary-heading">
        <h2 id="attendance-summary-heading" className="mb-2 text-lg font-semibold">
          {labels.attendance}
        </h2>
        {!report.attendance || report.attendance.eligibleSessions === 0 ? (
          <p className="text-sm text-slate-600">{labels.noAttendance}</p>
        ) : (
          <dl className="grid gap-2 text-sm sm:grid-cols-3 lg:grid-cols-4">
            <div><dt className="text-slate-500">{labels.eligibleSessions}</dt><dd>{report.attendance.eligibleSessions}</dd></div>
            <div><dt className="text-slate-500">{labels.present}</dt><dd>{report.attendance.presentCount}</dd></div>
            <div><dt className="text-slate-500">{labels.absent}</dt><dd>{report.attendance.absentCount}</dd></div>
            <div><dt className="text-slate-500">{labels.late}</dt><dd>{report.attendance.lateCount}</dd></div>
            <div><dt className="text-slate-500">{labels.excused}</dt><dd>{report.attendance.excusedCount}</dd></div>
            <div><dt className="text-slate-500">{labels.notRecorded}</dt><dd>{report.attendance.notRecordedCount}</dd></div>
            <div><dt className="text-slate-500">{labels.attendanceRate}</dt><dd>{formatReportPercentage(report.attendance.attendanceRate, locale)}</dd></div>
          </dl>
        )}
      </section>

      <section aria-labelledby="assessment-history-heading">
        <h2 id="assessment-history-heading" className="mb-2 text-lg font-semibold">
          {labels.assessments}
        </h2>
        {report.assessments.length === 0 ? (
          <p className="text-sm text-slate-600">{labels.noAssessments}</p>
        ) : (
          <>
            {report.averagePercentage !== null ? (
              <p className="mb-2 text-sm text-slate-600">
                {labels.averagePercentage}: {formatReportPercentage(report.averagePercentage, locale)}
              </p>
            ) : null}
            <table className="min-w-full divide-y divide-slate-200 text-sm">
              <thead className="bg-slate-50">
                <tr>
                  <th scope="col" className="px-3 py-2 text-left">{labels.assessmentTitle}</th>
                  <th scope="col" className="px-3 py-2 text-left">{labels.assessmentDate}</th>
                  <th scope="col" className="px-3 py-2 text-left">{labels.score}</th>
                  <th scope="col" className="px-3 py-2 text-left">{labels.percentage}</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-200">
                {report.assessments.map((a) => (
                  <tr key={`${a.assessmentId}-${a.assessedOn}`}>
                    <td className="px-3 py-2">{a.title}</td>
                    <td className="px-3 py-2">{formatReportDate(a.assessedOn, locale)}</td>
                    <td className="px-3 py-2">
                      {a.rawScore !== null
                        ? formatReportScore(a.rawScore, a.maxScore, locale)
                        : labels.noScoreRecorded}
                    </td>
                    <td className="px-3 py-2">
                      {formatReportPercentage(a.percentage, locale)}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </>
        )}
      </section>

      {report.includesObservations ? (
        <section aria-labelledby="observations-heading">
          <h2 id="observations-heading" className="mb-2 text-lg font-semibold">
            {labels.observations}
          </h2>
          {!report.observations || report.observations.length === 0 ? (
            <p className="text-sm text-slate-600">{labels.noObservations}</p>
          ) : (
            <ul className="space-y-4">
              {report.observations.map((obs, index) => (
                <li key={`${obs.sessionDate}-${index}`} className="rounded border border-slate-200 p-3 text-sm">
                  <p className="font-medium">
                    {formatReportDate(obs.sessionDate, locale)} — {obs.className}
                  </p>
                  {Object.keys(obs.ratings).length > 0 ? (
                    <dl className="mt-2 grid gap-1 sm:grid-cols-2">
                      {Object.entries(obs.ratings).map(([code, rating]) => (
                        <div key={code}>
                          <dt className="text-slate-500">
                            {observationIndicatorLabels[code] ?? code}
                          </dt>
                          <dd>{observationRatingLabels[rating] ?? rating}</dd>
                        </div>
                      ))}
                    </dl>
                  ) : null}
                  {obs.comment ? (
                    <p className="mt-2 text-slate-700">
                      <span className="font-medium">{labels.teacherComments}: </span>
                      {obs.comment}
                    </p>
                  ) : null}
                </li>
              ))}
            </ul>
          )}
        </section>
      ) : (
        <p className="text-sm text-slate-500">{labels.observationsLimited}</p>
      )}

      <section aria-labelledby="progress-summary-heading">
        <h2 id="progress-summary-heading" className="mb-2 text-lg font-semibold">
          {labels.progressSummary}
        </h2>
        <p className="text-sm text-slate-600">{labels.progressSummaryNote}</p>
      </section>
    </article>
  );
}
