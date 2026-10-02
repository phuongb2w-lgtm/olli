"use client";

import { useCallback, useEffect, useState } from "react";
import { useTranslations } from "next-intl";
import { ConsultantRevenueReviewDrawer } from "@/components/finance/consultant-revenue-review-drawer";
import { formatFinanceMoney } from "@/lib/finance/format-finance-value";
import {
  fetchConsultantDeclarations,
  type ConsultantDeclarationRow,
} from "@/lib/reporting/finance-read-model";
import { createClient } from "@/lib/supabase/client";
import type { Locale } from "@/i18n/config";

type Props = {
  startDate: string;
  endDate: string;
  locale: Locale;
  canConfirm: boolean;
};

export function ConsultantRevenueDeclarationsPanel({
  startDate,
  endDate,
  locale,
  canConfirm,
}: Props) {
  const t = useTranslations("finance.intelligence");
  const tReview = useTranslations("finance.consultantRevenueReview");
  const [rows, setRows] = useState<ConsultantDeclarationRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState(false);
  const [activeDeclarationId, setActiveDeclarationId] = useState<string | null>(null);

  const loadRows = useCallback(async () => {
    setLoading(true);
    setLoadError(false);
    const supabase = createClient();
    const { rows: nextRows, error } = await fetchConsultantDeclarations(supabase, {
      startDate,
      endDate,
    });
    if (error) {
      setLoadError(true);
      setRows([]);
    } else {
      setRows(nextRows);
    }
    setLoading(false);
  }, [startDate, endDate]);

  useEffect(() => {
    // Client-side fetch when reporting period changes (no server component boundary).
    // eslint-disable-next-line react-hooks/set-state-in-effect -- loadRows updates loading state after async RPC
    void loadRows();
  }, [loadRows]);

  if (loading) {
    return <p className="text-sm text-slate-600">{tReview("loading")}</p>;
  }

  if (loadError) {
    return <p className="text-sm text-red-700">{tReview("loadError")}</p>;
  }

  if (rows.length === 0) {
    return <p className="text-sm text-slate-600">{t("noDeclarations")}</p>;
  }

  return (
    <>
      <div className="overflow-x-auto rounded border border-slate-200">
        <table className="min-w-full text-sm" data-testid="finance-consultant-declarations-table">
          <thead className="bg-slate-50 text-left">
            <tr>
              <th className="px-3 py-2">{t("declarationDate")}</th>
              <th className="px-3 py-2">{t("consultant")}</th>
              <th className="px-3 py-2">{t("amount")}</th>
              <th className="px-3 py-2">{t("status")}</th>
              <th className="px-3 py-2">{t("paymentLink")}</th>
              <th className="px-3 py-2">
                <span className="sr-only">{tReview("actionsColumn")}</span>
              </th>
            </tr>
          </thead>
          <tbody>
            {rows.map((row) => {
              const reviewable =
                row.workflowKind === "cw2_payment" &&
                (row.status === "pending" || row.status === "returned");
              return (
                <tr key={row.declarationId} className="border-t border-slate-100">
                  <td className="px-3 py-2">{row.declarationDate}</td>
                  <td className="px-3 py-2">{row.consultantName}</td>
                  <td className="px-3 py-2">
                    {formatFinanceMoney(row.declaredAmount, locale)}
                  </td>
                  <td className="px-3 py-2">
                    {tReview(`declarationStatus.${row.status}` as "declarationStatus.pending")}
                  </td>
                  <td className="px-3 py-2">
                    {row.hasCanonicalPayment
                      ? t("linkedPayment")
                      : row.status === "approved"
                        ? t("unlinkedApproved")
                        : "—"}
                  </td>
                  <td className="px-3 py-2">
                    {reviewable ? (
                      <button
                        type="button"
                        className="text-sm font-medium text-slate-900 underline"
                        data-testid="finance-review-action"
                        onClick={() => setActiveDeclarationId(row.declarationId)}
                      >
                        {tReview("reviewAction")}
                      </button>
                    ) : (
                      "—"
                    )}
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>

      {activeDeclarationId ? (
        <ConsultantRevenueReviewDrawer
          declarationId={activeDeclarationId}
          canConfirm={canConfirm}
          onClose={() => {
            setActiveDeclarationId(null);
            void loadRows();
          }}
        />
      ) : null}
    </>
  );
}
