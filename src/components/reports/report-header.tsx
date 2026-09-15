import type { Locale } from "@/i18n/config";
import { formatDate } from "@/lib/formatting";
import type { ClassReportContext, OrganizationBranding, ReportPeriod } from "@/lib/reports/types";
import { formatReportDate } from "@/lib/reports/format-report-value";

type Props = {
  branding: OrganizationBranding;
  title: string;
  context?: ClassReportContext;
  studentName?: string;
  studentCode?: string | null;
  period: ReportPeriod;
  generatedAt: string;
  locale: Locale;
  labels: {
    course: string;
    class: string;
    student: string;
    studentCode: string;
    period: string;
    generatedOn: string;
    from: string;
    to: string;
  };
};

export function ReportHeader({
  branding,
  title,
  context,
  studentName,
  studentCode,
  period,
  generatedAt,
  locale,
  labels,
}: Props) {
  return (
    <header className="report-header space-y-3 border-b border-slate-200 pb-4">
      <p className="text-sm font-semibold uppercase tracking-wide text-slate-600">
        {branding.name}
      </p>
      <h1 className="text-2xl font-semibold text-slate-900">{title}</h1>
      <dl className="grid gap-2 text-sm text-slate-700 sm:grid-cols-2">
        {context ? (
          <>
            <div>
              <dt className="font-medium text-slate-500">{labels.class}</dt>
              <dd>{context.className}</dd>
            </div>
            <div>
              <dt className="font-medium text-slate-500">{labels.course}</dt>
              <dd>
                {context.courseCode ?? "—"}
                {context.courseName ? ` — ${context.courseName}` : ""}
              </dd>
            </div>
          </>
        ) : null}
        {studentName ? (
          <>
            <div>
              <dt className="font-medium text-slate-500">{labels.student}</dt>
              <dd>{studentName}</dd>
            </div>
            {studentCode ? (
              <div>
                <dt className="font-medium text-slate-500">{labels.studentCode}</dt>
                <dd>{studentCode}</dd>
              </div>
            ) : null}
          </>
        ) : null}
        <div>
          <dt className="font-medium text-slate-500">{labels.period}</dt>
          <dd>
            {labels.from} {formatReportDate(period.startDate, locale)} — {labels.to}{" "}
            {formatReportDate(period.endDate, locale)}
          </dd>
        </div>
        <div>
          <dt className="font-medium text-slate-500">{labels.generatedOn}</dt>
          <dd>{formatDate(generatedAt, locale)}</dd>
        </div>
      </dl>
    </header>
  );
}
