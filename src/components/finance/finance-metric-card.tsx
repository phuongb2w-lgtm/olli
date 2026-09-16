type Props = {
  label: string;
  value: string;
  hint?: string;
  variant?: "revenue" | "cash" | "receivable" | "obligation" | "cost" | "default";
};

const variantStyles: Record<NonNullable<Props["variant"]>, string> = {
  revenue: "border-blue-200 bg-blue-50",
  cash: "border-emerald-200 bg-emerald-50",
  receivable: "border-amber-200 bg-amber-50",
  obligation: "border-violet-200 bg-violet-50",
  cost: "border-rose-200 bg-rose-50",
  default: "border-slate-200 bg-white",
};

export function FinanceMetricCard({ label, value, hint, variant = "default" }: Props) {
  return (
    <section className={`rounded-lg border p-4 ${variantStyles[variant]}`}>
      <p className="text-xs font-medium uppercase tracking-wide text-slate-600">{label}</p>
      <p className="mt-1 text-lg font-semibold text-slate-900">{value}</p>
      {hint ? <p className="mt-1 text-xs text-slate-600">{hint}</p> : null}
    </section>
  );
}
