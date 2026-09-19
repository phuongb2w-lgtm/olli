import Link from "next/link";
import type { AcademicReviewQueueItem } from "@/lib/reporting/academic-read-model";

type Props = {
  title: string;
  items: AcademicReviewQueueItem[];
  emptyLabel: string;
  viewLabel: string;
};

export function AcademicReviewQueuePanel({ title, items, emptyLabel, viewLabel }: Props) {
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
            key={item.recordId}
            className="flex flex-wrap items-center justify-between gap-2 rounded border border-slate-100 bg-slate-50 px-3 py-2 text-sm"
          >
            <span className="text-slate-700">
              {String(item.comment_preview ?? item.status ?? item.entityType)}
            </span>
            <Link href={item.drillDownPath} className="text-xs font-medium underline">
              {viewLabel}
            </Link>
          </li>
        ))}
      </ul>
    </section>
  );
}
