import Link from "next/link";
import type { Locale } from "@/i18n/config";
import { formatFinanceMoney } from "@/lib/finance/format-finance-value";
import type { ExecutiveAttentionItem } from "@/lib/reporting/executive-read-model";

type Props = {
  items: ExecutiveAttentionItem[];
  locale: Locale;
  title: string;
  emptyLabel: string;
  viewLabel: string;
  domainLabels: Record<ExecutiveAttentionItem["domain"], string>;
};

export function ExecutiveAttentionPanel({
  items,
  locale,
  title,
  emptyLabel,
  viewLabel,
  domainLabels,
}: Props) {
  if (items.length === 0) {
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
        {items.map((item) => (
          <li
            key={`${item.domain}-${item.exceptionCode}-${item.entityId}`}
            className="flex flex-wrap items-start justify-between gap-2 rounded border border-slate-100 bg-slate-50 px-3 py-2 text-sm"
          >
            <div className="min-w-0 flex-1">
              <p className="text-xs font-medium uppercase tracking-wide text-slate-500">
                {domainLabels[item.domain]}
              </p>
              <p className="font-medium text-slate-800">{item.reason}</p>
              <p className="text-xs text-slate-600">
                {formatFinanceMoney(item.metricValue, locale)}
              </p>
            </div>
            <div className="flex shrink-0 flex-col items-end gap-1">
              <Link href={item.drillDownPath} className="text-xs font-medium underline">
                {viewLabel}
              </Link>
              <Link href={item.domainDrillDownPath} className="text-xs text-slate-600 underline">
                {domainLabels[item.domain]}
              </Link>
            </div>
          </li>
        ))}
      </ul>
    </section>
  );
}
