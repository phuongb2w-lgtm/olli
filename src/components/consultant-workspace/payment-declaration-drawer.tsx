"use client";

import { useCallback, useEffect, useId, useRef, useState, useTransition } from "react";
import { useLocale, useTranslations } from "next-intl";
import {
  loadDeclarationDrawerAction,
  loadTuitionDeclarationContextAction,
  loadTuitionDeclarationContextForPortfolioAction,
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
  const tV2 = useTranslations("consultantWorkspace.declarationV2");
  const locale = useLocale() as Locale;
  const titleId = useId();
  const panelRef = useRef<HTMLDivElement>(null);
  const [pending, startTransition] = useTransition();

  const readOnly =
    row.declaration_status === "approved" || row.declaration_status === "rejected";

  const [declarationId, setDeclarationId] = useState<string | null>(
    row.declaration_status === "pending" ? null : row.declaration_id,
  );
  const [amountInput, setAmountInput] = useState("");
  const [promotion, setPromotion] = useState("");
  const [note, setNote] = useState("");
  const [errorCode, setErrorCode] = useState<string | null>(null);
  const [finance, setFinance] = useState({
    total: row.tuition_total_net,
    paid: row.tuition_paid,
    outstanding: row.tuition_outstanding,
    pending: row.tuition_pending_declaration ?? 0,
  });
  const [tuitionEstablished, setTuitionEstablished] = useState(row.tuition_total_net > 0);
  const [billingMode, setBillingMode] = useState<"course_lump_sum" | "periodic" | "">("");
  const [courseTotalInput, setCourseTotalInput] = useState("");
  const [periodUnit, setPeriodUnit] = useState<"lesson" | "week" | "month" | "school_year">("month");
  const [periodQuantityInput, setPeriodQuantityInput] = useState("1");
  const [amountPerPeriodInput, setAmountPerPeriodInput] = useState("");
  const [paymentMethod, setPaymentMethod] = useState("cash");
  const [declarationDate, setDeclarationDate] = useState(new Date().toISOString().slice(0, 10));
  const [hasOrganizationAcademicYear, setHasOrganizationAcademicYear] = useState(false);

  const refreshFinance = useCallback(async () => {
    if (!row.enrollment_financial_terms_id) return;
    const result = await refreshDeclarationFinanceAction(row.enrollment_financial_terms_id);
    if (result.ok) {
      setFinance({
        total: Number(result.finance.tuition_total_net ?? row.tuition_total_net),
        paid: Number(result.finance.tuition_paid ?? row.tuition_paid),
        outstanding: Number(result.finance.tuition_outstanding ?? row.tuition_outstanding),
        pending: Number(
          result.finance.tuition_pending_declaration ?? row.tuition_pending_declaration ?? 0,
        ),
      });
    }
  }, [row]);

  useEffect(() => {
    let cancelled = false;
    const loadContext = row.enrollment_id
      ? loadTuitionDeclarationContextAction(row.enrollment_id)
      : loadTuitionDeclarationContextForPortfolioAction(row.portfolio_entry_id);
    void loadContext.then((res) => {
      if (cancelled || !res.ok) return;
      const fin = (res.data.finance ?? {}) as Record<string, unknown>;
      setTuitionEstablished(Boolean(res.data.tuition_established));
      setHasOrganizationAcademicYear(Boolean(res.data.has_organization_academic_year ?? true));
      if (typeof fin.tuition_total_net === "number") {
        setFinance((prev) => ({
          ...prev,
          total: Number(fin.tuition_total_net),
          paid: Number(fin.tuition_paid ?? prev.paid),
          outstanding: Number(fin.tuition_outstanding ?? prev.outstanding),
          pending: Number(fin.tuition_pending_declaration ?? prev.pending),
        }));
      }
      const mode = res.data.billing_mode as string | null;
      if (mode === "course_lump_sum" || mode === "periodic") setBillingMode(mode);
    });
    if (row.declaration_id && row.declaration_status !== "pending") {
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
  }, [row.declaration_id, row.declaration_status, row.enrollment_id, row.portfolio_entry_id, locale]);

  const effectivePeriodUnit =
    !hasOrganizationAcademicYear && periodUnit === "school_year" ? "month" : periodUnit;

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
  const isInitialSetup = !tuitionEstablished && billingMode !== "";
  const isUnpaidInitial =
    row.tuition_payment_state === "chua_nop_phi" || row.tuition_payment_state === "chua_coc";
  const canMutate =
    !readOnly &&
    row.capabilities.can_create_payment_declaration &&
    (isInitialSetup || finance.outstanding > 0 || isUnpaidInitial) &&
    (Boolean(row.enrollment_id) || Boolean(row.lead_id));

  const saveOrSubmit = (mode: "draft" | "submit") => {
    const amount = parseVndInput(amountInput);
    if (!amount) {
      setErrorCode("invalid_amount");
      return;
    }
    const enrollmentId = row.enrollment_id;
    if (!enrollmentId && !row.lead_id) {
      setErrorCode("context_incomplete");
      return;
    }
    const enrollmentFinancialTermsId = row.enrollment_financial_terms_id;
    const proposedTotal = parseVndInput(courseTotalInput);
    const perPeriod = parseVndInput(amountPerPeriodInput);
    const periodQty = Number.parseInt(periodQuantityInput, 10);
    const declarationKind = isInitialSetup ? "initial_tuition_setup" : "payment_only";
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
        enrollmentId: enrollmentId ?? undefined,
        enrollmentFinancialTermsId: enrollmentFinancialTermsId ?? undefined,
        guardianId: guardianId ?? undefined,
        totalObligationAmount: isInitialSetup ? proposedTotal ?? finance.total : finance.total,
        idempotencyKey: declarationId ? undefined : `cw2-drawer-${row.portfolio_entry_id}`,
        tuitionBillingMode: isInitialSetup ? billingMode || null : null,
        proposedNetTuitionAmount:
          isInitialSetup && billingMode === "course_lump_sum" ? proposedTotal : undefined,
        periodicPeriodUnit:
          isInitialSetup && billingMode === "periodic" ? effectivePeriodUnit : undefined,
        periodicPeriodQuantity:
          isInitialSetup && billingMode === "periodic" ? periodQty : undefined,
        periodicAmountPerPeriod:
          isInitialSetup && billingMode === "periodic" ? perPeriod ?? undefined : undefined,
        paymentMethodCode: paymentMethod,
        declarationKind,
        declarationDate,
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
            {(row.tuition_pending_declaration ?? 0) > 0 ? (
              <p className="text-sm text-amber-700">{t("pendingDeclarationNote")}</p>
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

        {!tuitionEstablished ? (
          <fieldset className="mb-4 space-y-2 text-sm" data-testid="tuition-billing-mode">
            <legend className="font-medium text-slate-800">{tV2("billingModeTitle")}</legend>
            <label className="flex items-center gap-2">
              <input
                type="radio"
                name="billingMode"
                checked={billingMode === "course_lump_sum"}
                disabled={pending}
                onChange={() => setBillingMode("course_lump_sum")}
              />
              {tV2("courseLumpSum")}
            </label>
            <label className="flex items-center gap-2">
              <input
                type="radio"
                name="billingMode"
                checked={billingMode === "periodic"}
                disabled={pending}
                onChange={() => setBillingMode("periodic")}
              />
              {tV2("periodic")}
            </label>
          </fieldset>
        ) : null}

        {isInitialSetup && billingMode === "course_lump_sum" ? (
          <label className="mb-3 block text-sm">
            <span className="text-slate-700">{tV2("courseTotal")}</span>
            <input
              className="mt-1 w-full rounded border border-slate-300 px-2 py-2"
              value={courseTotalInput}
              disabled={pending}
              onChange={(e) => setCourseTotalInput(e.target.value)}
              data-testid="drawer-course-total"
            />
          </label>
        ) : null}

        {isInitialSetup && billingMode === "periodic" ? (
          <div className="mb-3 space-y-2 text-sm">
            <label className="block">
              <span className="text-slate-700">{tV2("periodUnit")}</span>
              <select
                className="mt-1 w-full rounded border border-slate-300 px-2 py-2"
                value={effectivePeriodUnit}
                disabled={pending}
                onChange={(e) =>
                  setPeriodUnit(e.target.value as "lesson" | "week" | "month" | "school_year")
                }
                data-testid="drawer-period-unit"
              >
                <option value="month">{tV2("periodUnitMonth")}</option>
                <option value="lesson">{tV2("periodUnitLesson")}</option>
                <option value="week">{tV2("periodUnitWeek")}</option>
                <option value="school_year" disabled={!hasOrganizationAcademicYear}>
                  {tV2("periodUnitSchoolYear")}
                </option>
              </select>
              {!hasOrganizationAcademicYear ? (
                <span className="mt-1 block text-xs text-slate-500" data-testid="school-year-unavailable">
                  {tV2("schoolYearRequiresAcademicYear")}
                </span>
              ) : null}
            </label>
            {effectivePeriodUnit === "lesson" ? (
              <label className="block">
                <span className="text-slate-700">{tV2("periodQuantity")}</span>
                <input
                  className="mt-1 w-full rounded border border-slate-300 px-2 py-2"
                  inputMode="numeric"
                  value={periodQuantityInput}
                  disabled={pending}
                  onChange={(e) => setPeriodQuantityInput(e.target.value)}
                  data-testid="drawer-period-quantity"
                />
              </label>
            ) : null}
            <label className="block">
              <span className="text-slate-700">{tV2("amountPerPeriod")}</span>
              <input
                className="mt-1 w-full rounded border border-slate-300 px-2 py-2"
                value={amountPerPeriodInput}
                disabled={pending}
                onChange={(e) => setAmountPerPeriodInput(e.target.value)}
                data-testid="drawer-amount-per-period"
              />
            </label>
          </div>
        ) : null}

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
          {finance.pending > 0 ? (
            <div>
              <dt className="text-slate-600">{t("pendingConfirmation")}</dt>
              <dd data-testid="drawer-pending">{formatMoneyVnd(finance.pending, locale)}</dd>
            </div>
          ) : null}
          <div>
            <dt className="text-slate-600">{t("outstandingDue")}</dt>
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
            <span className="text-slate-700">{tV2("payThisTime")}</span>
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
            <span className="text-slate-700">{tV2("paymentDate")}</span>
            <input
              type="date"
              className="mt-1 w-full rounded border border-slate-300 px-2 py-2"
              value={declarationDate}
              disabled={!canMutate || pending}
              onChange={(e) => setDeclarationDate(e.target.value)}
              data-testid="drawer-payment-date"
            />
          </label>
          <label className="block text-sm">
            <span className="text-slate-700">{tV2("paymentMethod")}</span>
            <select
              className="mt-1 w-full rounded border border-slate-300 px-2 py-2"
              value={paymentMethod}
              disabled={!canMutate || pending}
              onChange={(e) => setPaymentMethod(e.target.value)}
              data-testid="drawer-payment-method"
            >
              <option value="cash">Cash</option>
              <option value="bank_transfer">Bank transfer</option>
            </select>
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
            {pending ? t("submitting") : tV2("submitAccounting")}
          </button>
        </div>
      </div>
    </div>
  );
}
