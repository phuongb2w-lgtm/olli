import Link from "next/link";
import type { TeachingOpsOperationalChange } from "@/lib/reporting/teaching-ops-read-model";

type Props = {
  changes: TeachingOpsOperationalChange[];
  title: string;
  emptyLabel: string;
  viewLabel: string;
  changeTypeLabels: Record<string, string>;
};

export function TeachingOpsChangesPanel({
  changes,
  title,
  emptyLabel,
  viewLabel,
  changeTypeLabels,
}: Props) {
  if (changes.length === 0) {
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
        {changes.map((change) => (
          <li
            key={change.change_id}
            className="flex flex-wrap items-start justify-between gap-2 rounded border border-slate-100 bg-slate-50 px-3 py-2 text-sm"
          >
            <div>
              <p className="font-medium text-slate-800">
                {changeTypeLabels[change.change_type] ?? change.change_type} — {change.class_name}
              </p>
              <p className="text-xs text-slate-600">
                {change.operational_date} · {new Date(change.occurred_at).toLocaleString()}
              </p>
              {change.reason ? (
                <p className="mt-1 text-xs text-slate-600">{change.reason}</p>
              ) : null}
            </div>
            <Link href={change.drill_down_path} className="text-xs font-medium underline">
              {viewLabel}
            </Link>
          </li>
        ))}
      </ul>
    </section>
  );
}
