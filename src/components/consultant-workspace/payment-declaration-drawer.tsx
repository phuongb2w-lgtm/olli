"use client";

import { useCallback, useEffect, useId, useRef, useState, useTransition } from "react";
import { useLocale, useTranslations } from "next-intl";
import {
  loadDeclarationDrawerAction,
  refreshDeclarationFinanceAction,
  saveConsultantPaymentDeclarationDraftAction,
  submitConsultantPaymentDeclarationAction,
} from "@/app/actions/consultant-payment-declaration";
import { formatPortfolioNamePart } from "@/lib/consultant-workspace/display-format";
import type { ConsultantWorkspacePortfolioRow } from "@/lib/consultant-workspace/portfolio-read-model";
import { formatVndInputValue, parseVndInput } from "@/lib/consultant-workspace/vnd-input";
import { formatMoneyVnd } from "@/lib/formatting";
import type { Locale } from "@/i18n/config";

type Props = {
  row: ConsultantWorkspacePortfolioRow;
  onClose: () => void;
  onSuccess: () => void;
  triggerRef: React.RefObject<HTMLElement | null>;
};

export function PaymentDeclarationDrawer({ row, onClose, onSuccess, triggerRef }: Props) {
  const t = useTranslations("consultantWorkspace.declaration");
  const locale = useLocale() as Locale;
  const titleId = useId();
  const panelRef = useRef<HTMLDivElement>(null);
  const [pending, startTransition] = useTransition();

  const readOnly =
    row.declaration_status === "pending" ||
    row.declaration_status === "approved" ||
    row.declaration_status === "rejected";

  const [declarationId, setDeclarationId] = useState<string | null>(row.declaration_id);
  const [amountInput, setAmountInput] = useState("");
  const [promotion, setPromotion] = useState("");
  const [note, setNote] = useState("");
  const [errorCode, setErrorCode] = useState<string | null>(null);
  const [finance, setFinance] = useState({
    total: row.tuition_total_net,
    paid: row.tuition_paid,
    outstanding: row.tuition_outstanding,
  });

  const refreshFinance = useCallback(async () => {
    if (!row.enrollment_financial_terms_id) return;
    const result = await refreshDeclarationFinanceAction(row.enrollment_financial_terms_id);
    if (result.ok) {
      setFinance({
        total: Number(result.finance.tuition_total_net ?? row.tuition_total_net),
        paid: Number(result.finance.tuition_paid ?? row.tuition_paid),
        outstanding: Number(result.finance.tuition_outstanding ?? row.tuition_outstanding),
      });
    }
  }, [row]);

  useEffect(() => {
    let cancelled = false;
    if (row.declaration_id) {
      void loadDeclarationDrawerAction(row.declaration_id).then((res) => {
        if (cancelled || !res.ok) return;
        const decl = res.data.declaration;
        setDeclarationId(String(decl.id));
        if (typeof decl.declared_amount === "number") {
          setAmountInput(formatVndInputValue(decl.declared_amount, locale));
        }
        if (typeof decl.promotion_context === "string") setPromotion(decl.promotion_context);
        if (typeof decl.description === "string") setNote(decl.description);
      });
    }
    panelRef.current?.focus();
    return () => {
      cancelled = true;
    };
  }, [row.declaration_id, locale]);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape" && !pending) {
        e.preventDefault();
        onClose();
        triggerRef.current?.focus();
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose, pending, triggerRef]);

  const guardianId = row.primary_guardian_id;
  const canMutate =
    !readOnly &&
    row.enrollment_financial_terms_id &&
    row.enrollment_id &&
    guardianId &&
    finance.outstanding > 0;

  const saveOrSubmit = (mode: "draft" | "submit") => {
    const amount = parseVndInput(amountInput);
    if (!amount) {
      setErrorCode("invalid_amount");
      return;
    }
    const enrollmentId = row.enrollment_id;
    const enrollmentFinancialTermsId = row.enrollment_financial_terms_id;
    if (!enrollmentId || !enrollmentFinancialTermsId || !guardianId) {
      setErrorCode("context_incomplete");
      return;
    }
    setErrorCode(null);
    startTransition(async () => {
      const saved = await saveConsultantPaymentDeclarationDraftAction({
        declarationId,
        declaredAmount: amount,
        description: note,
        promotionContext: promotion,
        leadId: row.lead_id,
        studentId: row.student_id,
        courseId: row.course_id,
        classId: row.class_id,
        enrollmentId,
        enrollmentFinancialTermsId,
        guardianId,
        totalObligationAmount: finance.total,
        idempotencyKey: declarationId ? undefined : `cw2-drawer-${row.portfolio_entry_id}`,
      });
      if (!saved.ok) {
        setErrorCode(saved.errorCode);
        await refreshFinance();
        return;
      }
      setDeclarationId(saved.declarationId);
      if (mode === "draft") {
        onSuccess();
        return;
      }
      const submitted = await submitConsultantPaymentDeclarationAction(saved.declarationId);
      if (!submitted.ok) {
        setErrorCode(submitted.errorCode);
        await refreshFinance();
        return;
      }
      onSuccess();
      onClose();
      triggerRef.current?.focus();
    });
  };

  const displayName = `${formatPortfolioNamePart(row.family_name, locale)} ${formatPortfolioNamePart(row.given_name, locale)}`.trim();

  return (
    <div className="fixed inset-0 z-50 flex justify-end bg-black/30" data-testid="payment-declaration-drawer">
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
          <div>
            <h2 id={titleId} className="text-lg font-semibold text-slate-900">
              {t("title")}
            </h2>
            {row.declaration_status === "pending" ? (
              <p className="text-sm text-amber-700">{t("pendingReadOnly")}</p>
            ) : null}
            {row.declaration_status === "returned" ? (
              <p className="text-sm text-amber-700">{t("returnedEditable")}</p>
            ) : null}
          </div>
          <div className="flex flex-col items-end gap-1">
            <button
              type="button"
              className="text-xs text-slate-600 underline"
              disabled={pending || !row.enrollment_financial_terms_id}
              onClick={() => void refreshFinance()}
            >
              {t("refreshFinance")}
            </button>
            <button type="button" className="text-sm underline" onClick={onClose}>
              {t("close")}
            </button>
          </div>
        </header>

        <dl className="space-y-2 text-sm">
          <div>
            <dt className="text-slate-600">{t("student")}</dt>
            <dd>{displayName}</dd>
          </div>
          <div>
            <dt className="text-slate-600">{t("studentCode")}</dt>
            <dd data-testid="drawer-student-code">
              {row.student_code_display ?? "—"}
              {row.student_code_is_provisional ? ` (${t("provisional")})` : ""}
            </dd>
          </div>
          <div>
            <dt className="text-slate-600">{t("course")}</dt>
            <dd data-testid="drawer-course">{row.course_name ?? "—"}</dd>
          </div>
          <div>
            <dt className="text-slate-600">{t("totalDue")}</dt>
            <dd data-testid="drawer-total">{formatMoneyVnd(finance.total, locale)}</dd>
          </div>
          <div>
            <dt className="text-slate-600">{t("confirmedPaid")}</dt>
            <dd data-testid="drawer-paid">{formatMoneyVnd(finance.paid, locale)}</dd>
          </div>
          <div>
            <dt className="text-slate-600">{t("outstanding")}</dt>
            <dd data-testid="drawer-outstanding">{formatMoneyVnd(finance.outstanding, locale)}</dd>
          </div>
        </dl>

        {finance.outstanding <= 0 && !row.declaration_id ? (
          <p className="mt-4 text-sm text-slate-600">{t("fullySettled")}</p>
        ) : null}

        {!guardianId ? (
          <p className="mt-4 text-sm text-red-700" role="alert">
            {t("missingGuardian")}
          </p>
        ) : null}

        <div className="mt-4 space-y-3">
          <label className="block text-sm">
            <span className="text-slate-700">{t("amountThisTime")}</span>
            <input
              className="mt-1 w-full rounded border border-slate-300 px-2 py-2"
              inputMode="numeric"
              value={amountInput}
              disabled={!canMutate || pending}
              onChange={(e) => setAmountInput(e.target.value)}
              data-testid="drawer-amount"
            />
          </label>
          <label className="block text-sm">
            <span className="text-slate-700">{t("promotion")}</span>
            <input
              className="mt-1 w-full rounded border border-slate-300 px-2 py-2"
              value={promotion}
              disabled={!canMutate || pending}
              onChange={(e) => setPromotion(e.target.value)}
              data-testid="drawer-promotion"
            />
            <span className="mt-1 block text-xs text-slate-500">{t("promotionHint")}</span>
          </label>
          <label className="block text-sm">
            <span className="text-slate-700">{t("note")}</span>
            <textarea
              className="mt-1 w-full rounded border border-slate-300 px-2 py-2"
              rows={3}
              value={note}
              disabled={!canMutate || pending}
              onChange={(e) => setNote(e.target.value)}
              data-testid="drawer-note"
            />
          </label>
        </div>

        {errorCode ? (
          <p className="mt-3 text-sm text-red-700" role="alert" data-testid="drawer-error">
            {t(`errors.${errorCode}` as "errors.unknown")}
          </p>
        ) : null}

        <div className="mt-auto flex flex-col gap-2 pt-6 sm:flex-row">
          <button
            type="button"
            className="rounded border border-slate-300 px-4 py-2 text-sm"
            disabled={!canMutate || pending}
            onClick={() => saveOrSubmit("draft")}
            data-testid="drawer-save-draft"
          >
            {pending ? t("saving") : t("saveDraft")}
          </button>
          <button
            type="button"
            className="rounded bg-slate-900 px-4 py-2 text-sm font-medium text-white disabled:opacity-50"
            disabled={!canMutate || pending}
            onClick={() => saveOrSubmit("submit")}
            data-testid="drawer-submit"
          >
            {pending ? t("submitting") : t("submit")}
          </button>
        </div>
      </div>
    </div>
  );
}
