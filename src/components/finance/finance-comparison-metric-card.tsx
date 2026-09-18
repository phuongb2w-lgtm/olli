import { formatFinanceMoney } from "@/lib/finance/format-finance-value";
import type { Locale } from "@/i18n/config";

type Props = {
  label: string;
  value: number;
  change: number | null;
  locale: Locale;
  variant?: "revenue" | "cash" | "receivable" | "cost" | "obligation" | "neutral";
  hint?: string;
  sublabel?: string;
};

const variantClasses: Record<NonNullable<Props["variant"]>, string> = {
  revenue: "border-emerald-200 bg-emerald-50",
  cash: "border-sky-200 bg-sky-50",
  receivable: "border-amber-200 bg-amber-50",
  cost: "border-rose-200 bg-rose-50",
  obligation: "border-violet-200 bg-violet-50",
  neutral: "border-slate-200 bg-white",
};

export function FinanceComparisonMetricCard({
  label,
  value,
  change,
  locale,
  variant = "neutral",
  hint,
  sublabel,
}: Props) {
  const changeLabel =
    change == null
      ? null
      : change === 0
        ? "0"
        : `${change > 0 ? "+" : ""}${formatFinanceMoney(change, locale)}`;

  return (
    <article className={`rounded-lg border p-4 ${variantClasses[variant]}`}>
      <p className="text-sm font-medium text-slate-700">{label}</p>
      <p className="mt-1 text-2xl font-semibold text-slate-900">
        {formatFinanceMoney(value, locale)}
      </p>
      {sublabel ? <p className="mt-1 text-xs text-slate-600">{sublabel}</p> : null}
      {changeLabel != null ? (
        <p className="mt-2 text-xs text-slate-600">
          <span className="font-medium">{changeLabel}</span>
        </p>
      ) : null}
      {hint ? <p className="mt-2 text-xs text-slate-500">{hint}</p> : null}
    </article>
  );
}
