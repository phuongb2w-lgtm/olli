import Link from "next/link";
import { formatFinanceMoney } from "@/lib/finance/format-finance-value";
import type { Locale } from "@/i18n/config";
import type { FinanceException } from "@/lib/reporting/finance-read-model";

type Props = {
  exceptions: FinanceException[];
  locale: Locale;
  title: string;
  emptyLabel: string;
  viewLabel: string;
};

export function FinanceExceptionsPanel({
  exceptions,
  locale,
  title,
  emptyLabel,
  viewLabel,
}: Props) {
  if (exceptions.length === 0) {
    return (
      <section className="rounded-lg border border-slate-200 bg-white p-4">
        <h2 className="text-sm font-semibold text-slate-800">{title}</h2>
        <p className="mt-2 text-sm text-slate-600">{emptyLabel}</p>
      </section>
    );
  }

  return (
    <section className="rounded-lg border border-slate-200 bg-white p-4">
      <h2 className="text-sm font-semibold text-slate-800">{title}</h2>
      <ul className="mt-3 space-y-2">
        {exceptions.map((ex) => (
          <li
            key={`${ex.exceptionCode}-${ex.entityId}`}
            className="flex flex-wrap items-start justify-between gap-2 rounded border border-slate-100 bg-slate-50 px-3 py-2 text-sm"
          >
            <div>
              <p className="font-medium text-slate-800">{ex.reason}</p>
              <p className="text-xs text-slate-600">
                {formatFinanceMoney(ex.metricValue, locale)}
              </p>
            </div>
            <Link href={ex.drillDownPath} className="text-xs font-medium underline">
              {viewLabel}
            </Link>
          </li>
        ))}
      </ul>
    </section>
  );
}
