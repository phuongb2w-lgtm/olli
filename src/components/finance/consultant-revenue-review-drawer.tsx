"use client";

import { useCallback, useEffect, useId, useRef, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { useLocale, useTranslations } from "next-intl";
import {
  confirmConsultantPaymentDeclarationAction,
  rejectConsultantRevenueDeclarationAction,
} from "@/app/actions/consultant-revenue-review";
import { formatMoneyVnd } from "@/lib/formatting";
import { createClient } from "@/lib/supabase/client";
import type { Locale } from "@/i18n/config";

type Props = {
  declarationId: string;
  onClose: () => void;
  canConfirm: boolean;
};

type ReviewDetail = {
  declaration: Record<string, unknown>;
  student_name?: string;
  consultant_name?: string;
  canonical_finance?: Record<string, unknown> | null;
  periodic_effect_preview?: Record<string, unknown> | null;
};

export function ConsultantRevenueReviewDrawer({ declarationId, onClose, canConfirm }: Props) {
  const t = useTranslations("finance.consultantRevenueReview");
  const tPayState = useTranslations("consultantWorkspace.paymentState");
  const locale = useLocale() as Locale;
  const router = useRouter();
  const titleId = useId();
  const panelRef = useRef<HTMLDivElement>(null);
  const [pending, startTransition] = useTransition();
  const [loading, setLoading] = useState(true);
  const [detail, setDetail] = useState<ReviewDetail | null>(null);
  const [errorCode, setErrorCode] = useState<string | null>(null);
  const [reviewNotes, setReviewNotes] = useState("");
  const [paidAt, setPaidAt] = useState(new Date().toISOString().slice(0, 10));
  const [methodCode, setMethodCode] = useState("cash");

  const loadDetail = useCallback(async () => {
    setLoading(true);
    setErrorCode(null);
    const supabase = createClient();
    const { data, error } = await supabase.rpc("get_cw2_finance_declaration_review_detail", {
      p_declaration_id: declarationId,
    });
    if (error || !data) {
      setErrorCode(error?.message.includes("permission_denied") ? "permission_denied" : "unknown");
      setDetail(null);
    } else {
      setDetail(data as unknown as ReviewDetail);
    }
    setLoading(false);
  }, [declarationId]);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect -- loadDetail updates loading state after async RPC
    void loadDetail();
    panelRef.current?.focus();
  }, [loadDetail]);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape" && !pending) {
        e.preventDefault();
        onClose();
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose, pending]);

  const decl = detail?.declaration;
  const status = decl ? String(decl.status ?? "") : "";
  const canAct = status === "pending" || status === "returned";
  const finance = detail?.canonical_finance ?? null;

  const runConfirm = () => {
    setErrorCode(null);
    startTransition(async () => {
      const paidAtIso = paidAt ? `${paidAt}T12:00:00.000Z` : undefined;
      const result = await confirmConsultantPaymentDeclarationAction({
        declarationId,
        paidAt: paidAtIso,
        methodCode,
      });
      if (!result.ok) {
        setErrorCode(result.errorCode);
        return;
      }
      router.refresh();
      onClose();
    });
  };

  const runReject = () => {
    setErrorCode(null);
    startTransition(async () => {
      const result = await rejectConsultantRevenueDeclarationAction({
        declarationId,
        reviewNotes,
      });
      if (!result.ok) {
        setErrorCode(result.errorCode);
        return;
      }
      router.refresh();
      onClose();
    });
  };

  return (
    <div
      className="fixed inset-0 z-50 flex justify-end bg-black/30"
      data-testid="finance-declaration-review-drawer"
    >
      <button type="button" className="flex-1" aria-label={t("closeOverlay")} onClick={onClose} />
      <div
        ref={panelRef}
        role="dialog"
        aria-modal="true"
        aria-labelledby={titleId}
        tabIndex={-1}
        className="flex h-full w-full max-w-md flex-col overflow-y-auto bg-white p-4 shadow-xl sm:max-w-lg"
      >
        <header className="mb-4 flex items-start justify-between gap-2">
          <h2 id={titleId} className="text-lg font-semibold text-slate-900">
            {t("title")}
          </h2>
          <button type="button" className="text-sm underline" onClick={onClose} disabled={pending}>
            {t("close")}
          </button>
        </header>

        {loading ? <p className="text-sm text-slate-600">{t("loading")}</p> : null}

        {!loading && detail && decl ? (
          <div className="space-y-4 text-sm">
            <dl className="space-y-2">
              <div>
                <dt className="text-slate-600">{t("consultant")}</dt>
                <dd data-testid="finance-review-consultant">{detail.consultant_name ?? "—"}</dd>
              </div>
              <div>
                <dt className="text-slate-600">{t("student")}</dt>
                <dd data-testid="finance-review-student">{detail.student_name ?? "—"}</dd>
              </div>
              <div>
                <dt className="text-slate-600">{t("declarationDate")}</dt>
                <dd>{String(decl.declaration_date ?? "—")}</dd>
              </div>
              <div>
                <dt className="text-slate-600">{t("amount")}</dt>
                <dd data-testid="finance-review-amount">
                  {formatMoneyVnd(Number(decl.declared_amount ?? 0), locale)}
                </dd>
              </div>
              <div>
                <dt className="text-slate-600">{t("status")}</dt>
                <dd>{t(`declarationStatus.${status}` as "declarationStatus.pending")}</dd>
              </div>
              {decl.declaration_kind ? (
                <div>
                  <dt className="text-slate-600">{t("declarationKind")}</dt>
                  <dd>{String(decl.declaration_kind)}</dd>
                </div>
              ) : null}
              {finance ? (
                <>
                  <div>
                    <dt className="text-slate-600">{t("tuitionOutstanding")}</dt>
                    <dd>
                      {formatMoneyVnd(Number(finance.course_outstanding_amount ?? 0), locale)}
                    </dd>
                  </div>
                  <div>
                    <dt className="text-slate-600">{t("tuitionPaid")}</dt>
                    <dd>{formatMoneyVnd(Number(finance.allocated_amount ?? 0), locale)}</dd>
                  </div>
                  {finance.tuition_payment_state ? (
                    <div>
                      <dt className="text-slate-600">{t("tuitionState")}</dt>
                      <dd>
                        {tPayState(String(finance.tuition_payment_state) as "chua_coc")}
                      </dd>
                    </div>
                  ) : null}
                </>
              ) : null}
            </dl>

            {detail.periodic_effect_preview ? (
              <p className="rounded border border-slate-200 bg-slate-50 p-2 text-xs text-slate-700">
                {t("periodicPreview")}
              </p>
            ) : null}

            {canAct ? (
              <div className="space-y-3 border-t border-slate-100 pt-4">
                {canConfirm ? (
                  <>
                    <label className="block">
                      <span className="text-slate-700">{t("paidAt")}</span>
                      <input
                        type="date"
                        className="mt-1 w-full rounded border border-slate-300 px-2 py-2"
                        value={paidAt}
                        disabled={pending}
                        onChange={(e) => setPaidAt(e.target.value)}
                        data-testid="finance-review-paid-at"
                      />
                    </label>
                    <label className="block">
                      <span className="text-slate-700">{t("paymentMethod")}</span>
                      <select
                        className="mt-1 w-full rounded border border-slate-300 px-2 py-2"
                        value={methodCode}
                        disabled={pending}
                        onChange={(e) => setMethodCode(e.target.value)}
                        data-testid="finance-review-method"
                      >
                        <option value="cash">{t("methodCash")}</option>
                        <option value="bank_transfer">{t("methodBankTransfer")}</option>
                      </select>
                    </label>
                  </>
                ) : (
                  <p className="text-xs text-amber-800">{t("confirmRequiresPaymentRecord")}</p>
                )}
                <label className="block">
                  <span className="text-slate-700">{t("reviewNotes")}</span>
                  <textarea
                    className="mt-1 w-full rounded border border-slate-300 px-2 py-2"
                    rows={3}
                    value={reviewNotes}
                    disabled={pending}
                    onChange={(e) => setReviewNotes(e.target.value)}
                    data-testid="finance-review-notes"
                  />
                </label>
              </div>
            ) : (
              <p className="text-slate-600">{t("notReviewable")}</p>
            )}
          </div>
        ) : null}

        {errorCode ? (
          <p className="mt-3 text-sm text-red-700" role="alert" data-testid="finance-review-error">
            {t(`errors.${errorCode}` as "errors.unknown")}
          </p>
        ) : null}

        {canAct && !loading ? (
          <div className="mt-auto flex flex-col gap-2 pt-6 sm:flex-row">
            {canConfirm ? (
              <button
                type="button"
                className="rounded bg-slate-900 px-4 py-2 text-sm font-medium text-white disabled:opacity-50"
                disabled={pending}
                onClick={runConfirm}
                data-testid="finance-review-confirm"
              >
                {pending ? t("confirming") : t("confirmPayment")}
              </button>
            ) : null}
            <button
              type="button"
              className="rounded border border-red-300 px-4 py-2 text-sm text-red-800 disabled:opacity-50"
              disabled={pending}
              onClick={runReject}
              data-testid="finance-review-reject"
            >
              {pending ? t("rejecting") : t("reject")}
            </button>
          </div>
        ) : null}
      </div>
    </div>
  );
}
