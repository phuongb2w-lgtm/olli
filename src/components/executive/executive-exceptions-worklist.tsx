import Link from "next/link";
import type { Locale } from "@/i18n/config";
import { formatFinanceMoney } from "@/lib/finance/format-finance-value";
import type { ExecutiveExceptionRow } from "@/lib/reporting/executive-read-model";
import { ExecutiveExceptionFollowUpForm } from "@/components/executive/executive-exception-follow-up-form";

type Props = {
  rows: ExecutiveExceptionRow[];
  locale: Locale;
  canManageFollowUp: boolean;
  labels: {
    empty: string;
    viewDrillDown: string;
    viewDomain: string;
    domainFinance: string;
    domainAdmissions: string;
    domainQuality: string;
    domainOperations: string;
    followUpTitle: string;
    statusLabel: string;
    noteLabel: string;
    notePlaceholder: string;
    save: string;
    saving: string;
    permissionDenied: string;
    saveError: string;
    statusOpen: string;
    statusAcknowledged: string;
    statusResolved: string;
    statusDismissed: string;
    sourceActive: string;
    sourceInactive: string;
    followUpNone: string;
    noReasonHistorical: string;
  };
};

const domainLabelKey: Record<
  ExecutiveExceptionRow["domain"],
  keyof Props["labels"]
> = {
  finance: "domainFinance",
  admissions: "domainAdmissions",
  quality: "domainQuality",
  operations: "domainOperations",
};

export function ExecutiveExceptionsWorklist({
  rows,
  locale,
  canManageFollowUp,
  labels,
}: Props) {
  if (rows.length === 0) {
    return (
      <section className="rounded-lg border border-slate-200 bg-white p-4">
        <p className="text-sm text-slate-600">{labels.empty}</p>
      </section>
    );
  }

  return (
    <ul className="space-y-4">
      {rows.map((row) => {
        const domainLabel = labels[domainLabelKey[row.domain]];
        const reason =
          row.reason ??
          (row.sourceCurrentlyDetected ? row.exceptionCode : labels.noReasonHistorical);

        return (
          <li
            key={row.exceptionKey}
            className="space-y-3 rounded-lg border border-slate-200 bg-white p-4"
          >
            <div className="flex flex-wrap items-start justify-between gap-3">
              <div className="min-w-0 flex-1 space-y-1">
                <p className="text-xs font-medium uppercase tracking-wide text-slate-500">
                  {domainLabel} · {row.exceptionCode}
                </p>
                <p className="font-medium text-slate-900">{reason}</p>
                <p className="text-xs text-slate-600">
                  {row.entityType} · {row.entityId}
                </p>
                {row.metricValue != null ? (
                  <p className="text-xs text-slate-600">
                    {formatFinanceMoney(row.metricValue, locale)}
                  </p>
                ) : null}
              </div>
              <div className="flex shrink-0 flex-col items-end gap-1">
                {row.drillDownPath ? (
                  <Link href={row.drillDownPath} className="text-xs font-medium underline">
                    {labels.viewDrillDown}
                  </Link>
                ) : null}
                <Link
                  href={row.domainDrillDownPath}
                  className="text-xs text-slate-600 underline"
                >
                  {labels.viewDomain}
                </Link>
              </div>
            </div>

            <ExecutiveExceptionFollowUpForm
              row={row}
              canManage={canManageFollowUp}
              labels={{
                followUpTitle: labels.followUpTitle,
                statusLabel: labels.statusLabel,
                noteLabel: labels.noteLabel,
                notePlaceholder: labels.notePlaceholder,
                save: labels.save,
                saving: labels.saving,
                permissionDenied: labels.permissionDenied,
                saveError: labels.saveError,
                statusOpen: labels.statusOpen,
                statusAcknowledged: labels.statusAcknowledged,
                statusResolved: labels.statusResolved,
                statusDismissed: labels.statusDismissed,
                sourceActive: labels.sourceActive,
                sourceInactive: labels.sourceInactive,
                followUpNone: labels.followUpNone,
              }}
            />
          </li>
        );
      })}
    </ul>
  );
}
