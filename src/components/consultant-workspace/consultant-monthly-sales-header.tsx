"use client";

import { useEffect, useState, useTransition } from "react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { useLocale, useTranslations } from "next-intl";
import { fetchConsultantMonthlySales } from "@/lib/consultant-workspace/fetch-monthly-sales";
import { normalizePeriodMonth } from "@/lib/finance/format-finance-value";
import {
  formatConsultantMonthLabel,
  parseConsultantWorkspaceMonthParam,
  shiftConsultantWorkspaceMonth,
} from "@/lib/consultant-workspace/month-period";
import type { ConsultantMonthlySalesSnapshot } from "@/lib/consultant-workspace/monthly-sales-read-model";
import { createClient } from "@/lib/supabase/client";
import { formatMoneyVnd, formatPercentage } from "@/lib/formatting";
import type { Locale } from "@/i18n/config";

type LoadState = "idle" | "loading" | "error";

function ConsultantMonthlySalesPanel({ periodMonth }: { periodMonth: string }) {
  const t = useTranslations("consultantWorkspace.monthlySales");
  const locale = useLocale() as Locale;
  const [loadState, setLoadState] = useState<LoadState>("loading");
  const [snapshot, setSnapshot] = useState<ConsultantMonthlySalesSnapshot | null>(null);

  useEffect(() => {
    let active = true;
    void (async () => {
      const supabase = createClient();
      const { data, error } = await fetchConsultantMonthlySales(supabase, periodMonth);
      if (!active) return;
      if (error || !data) {
        setSnapshot(null);
        setLoadState("error");
        return;
      }
      setSnapshot(data);
      setLoadState("idle");
    })();
    return () => {
      active = false;
    };
  }, [periodMonth]);

  const retry = () => {
    setLoadState("loading");
    void (async () => {
      const supabase = createClient();
      const { data, error } = await fetchConsultantMonthlySales(supabase, periodMonth);
      if (error || !data) {
        setSnapshot(null);
        setLoadState("error");
        return;
      }
      setSnapshot(data);
      setLoadState("idle");
    })();
  };

  const monthLabel = formatConsultantMonthLabel(periodMonth, locale);

  const comparisonLine = (() => {
    if (!snapshot || loadState === "loading") return null;
    if (snapshot.comparisonKind === "new") {
      return t("comparisonNew");
    }
    if (snapshot.comparisonPercent == null || snapshot.comparisonKind === "neutral") {
      if (snapshot.salesAmount === 0 && snapshot.previousSalesAmount === 0) {
        return null;
      }
      if (snapshot.comparisonDelta === 0) {
        return t("comparisonFlat");
      }
      return null;
    }
    const pct = formatPercentage(Math.abs(snapshot.comparisonPercent) / 100, locale, 1);
    if (snapshot.comparisonKind === "increase") {
      return t("comparisonUp", { percent: pct });
    }
    if (snapshot.comparisonKind === "decrease") {
      return t("comparisonDown", { percent: pct });
    }
    return null;
  })();

  return (
    <>
      <h2 className="text-sm font-medium text-slate-600">{t("title")}</h2>

      {loadState === "error" ? (
        <div role="alert" className="space-y-2">
          <p className="text-sm text-red-700" data-testid="month-sales-error">
            {t("error")}
          </p>
          <button
            type="button"
            className="rounded border border-slate-300 px-2 py-1 text-sm"
            onClick={retry}
            data-testid="month-sales-retry"
          >
            {t("retry")}
          </button>
        </div>
      ) : (
        <>
          <p
            className="text-2xl font-semibold tabular-nums text-slate-900 sm:text-3xl"
            data-testid="month-sales-amount"
            aria-live="polite"
          >
            {loadState === "loading"
              ? t("loadingAmount")
              : formatMoneyVnd(snapshot?.salesAmount ?? 0, locale)}
          </p>
          {loadState !== "loading" && snapshot ? (
            <div className="space-y-1 text-sm text-slate-600">
              {snapshot.paymentCount > 0 ? (
                <p data-testid="month-sales-payment-count">
                  {t("paymentCount", { count: snapshot.paymentCount })}
                </p>
              ) : snapshot.salesAmount === 0 ? (
                <p data-testid="month-sales-empty">{t("emptyMonth")}</p>
              ) : null}
              {comparisonLine ? (
                <p data-testid="month-sales-comparison">{comparisonLine}</p>
              ) : null}
            </div>
          ) : null}
        </>
      )}
      <span className="sr-only">{monthLabel}</span>
    </>
  );
}

export function ConsultantMonthlySalesHeader() {
  const t = useTranslations("consultantWorkspace.monthlySales");
  const locale = useLocale() as Locale;
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const [, startTransition] = useTransition();

  const monthParam = searchParams.get("month");
  const { periodMonth, queryMonth, usedFallback } = parseConsultantWorkspaceMonthParam(monthParam);

  useEffect(() => {
    if (usedFallback && monthParam) {
      const params = new URLSearchParams(searchParams.toString());
      params.delete("month");
      router.replace(`${pathname}?${params.toString()}`.replace(/\?$/, ""));
    }
  }, [usedFallback, monthParam, pathname, router, searchParams]);

  const navigateMonth = (nextPeriodMonth: string) => {
    const params = new URLSearchParams(searchParams.toString());
    params.set("month", nextPeriodMonth.slice(0, 7));
    startTransition(() => {
      router.push(`${pathname}?${params.toString()}`);
    });
  };

  const monthLabel = formatConsultantMonthLabel(periodMonth, locale);
  const currentMonth = normalizePeriodMonth();
  const canGoNext = periodMonth < currentMonth;
  const showCurrentMonthLink = periodMonth !== currentMonth;

  const onCurrentMonth = () => {
    const params = new URLSearchParams(searchParams.toString());
    params.delete("month");
    startTransition(() => {
      router.push(params.toString() ? `${pathname}?${params.toString()}` : pathname);
    });
  };

  return (
    <section
      className="rounded-lg border border-slate-200 bg-white p-4"
      data-testid="consultant-monthly-sales-header"
    >
      <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
        <div className="flex flex-col gap-2">
          <div className="flex flex-wrap items-center gap-2">
            <button
              type="button"
              className="rounded border border-slate-300 px-2 py-1 text-sm hover:bg-slate-50 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-slate-600"
              onClick={() => navigateMonth(shiftConsultantWorkspaceMonth(periodMonth, -1))}
              aria-label={t("previousMonth")}
              data-testid="month-sales-prev"
            >
              ←
            </button>
            <p
              className="min-w-[8rem] text-center text-sm font-medium text-slate-800"
              data-testid="month-sales-period"
            >
              {t("monthLabel", { month: monthLabel })}
            </p>
            <button
              type="button"
              className="rounded border border-slate-300 px-2 py-1 text-sm hover:bg-slate-50 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-slate-600 disabled:cursor-not-allowed disabled:opacity-40"
              onClick={() => navigateMonth(shiftConsultantWorkspaceMonth(periodMonth, 1))}
              disabled={!canGoNext}
              aria-label={t("nextMonth")}
              aria-disabled={!canGoNext}
              data-testid="month-sales-next"
            >
              →
            </button>
            {showCurrentMonthLink ? (
              <button
                type="button"
                className="text-xs text-slate-600 underline underline-offset-2 hover:text-slate-900"
                onClick={onCurrentMonth}
                data-testid="month-sales-current"
              >
                {t("currentMonth")}
              </button>
            ) : null}
          </div>

          <ConsultantMonthlySalesPanel key={periodMonth} periodMonth={periodMonth} />
        </div>
      </div>
      <span className="sr-only" data-testid="month-sales-query">
        {queryMonth}
      </span>
    </section>
  );
}
