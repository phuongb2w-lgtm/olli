"use client";

import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { useMemo, useRef, useState, useTransition } from "react";
import { useLocale, useTranslations } from "next-intl";
import {
  saveConsultantPortfolioCustomFields,
  saveConsultantPortfolioProfile,
} from "@/lib/consultant-workspace/fetch-portfolio-detail";
import { createClient } from "@/lib/supabase/client";
import { PaymentDeclarationDrawer } from "@/components/consultant-workspace/payment-declaration-drawer";
import { formatPortfolioNamePart } from "@/lib/consultant-workspace/display-format";
import {
  portfolioDetailToDeclarationRow,
  type ConsultantPortfolioDetail,
} from "@/lib/consultant-workspace/portfolio-detail-read-model";
import { formatMoneyVnd } from "@/lib/formatting";
import type { Locale } from "@/i18n/config";

type Props = {
  initialDetail: ConsultantPortfolioDetail;
  startInEditMode: boolean;
};

export function ConsultantPortfolioDetailView({ initialDetail, startInEditMode }: Props) {
  const t = useTranslations("consultantWorkspace.detail");
  const tWs = useTranslations("consultantWorkspace");
  const locale = useLocale() as Locale;
  const router = useRouter();
  const searchParams = useSearchParams();
  const [detail, setDetail] = useState(initialDetail);
  const [editing, setEditing] = useState(startInEditMode && detail.editable.can_edit_profile);
  const [errorCode, setErrorCode] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();
  const [drawerOpen, setDrawerOpen] = useState(false);
  const drawerTriggerRef = useRef<HTMLButtonElement>(null);

  const returnHref = searchParams.get("return") || "/consultant";

  const [form, setForm] = useState({
    familyName: detail.family_name ?? "",
    givenName: detail.given_name ?? "",
    dateOfBirth: detail.date_of_birth ?? "",
    personalIdentificationNumber: detail.personal_identification_number ?? "",
    guardianFamilyName: detail.primary_guardian_family_name ?? "",
    guardianGivenName: detail.primary_guardian_given_name ?? "",
    guardianPhone: detail.primary_guardian_phone ?? "",
    customFields: detail.custom_fields.map((f) => ({ field_key: f.field_key, value: f.value })),
  });

  const declarationRow = useMemo(() => portfolioDetailToDeclarationRow(detail), [detail]);

  const lifecycleLabel = tWs(`lifecycle.${detail.lifecycle_status}` as "lifecycle.tiem_nang");
  const paymentLabel = tWs(`paymentState.${detail.tuition_payment_state}` as "paymentState.dong_phi");

  const onSave = () => {
    setErrorCode(null);
    startTransition(async () => {
      const supabase = createClient();
      const profileResult = await saveConsultantPortfolioProfile(supabase, {
        portfolioEntryId: detail.portfolio_entry_id,
        familyName: form.familyName,
        givenName: form.givenName,
        dateOfBirth: form.dateOfBirth || null,
        personalIdentificationNumber: form.personalIdentificationNumber || null,
        guardianFamilyName: form.guardianFamilyName,
        guardianGivenName: form.guardianGivenName,
        guardianPhone: form.guardianPhone,
        expectedSubjectUpdatedAt: detail.subject_updated_at,
      });
      if (!profileResult.ok) {
        setErrorCode(profileResult.errorCode);
        return;
      }
      let nextDetail = profileResult.detail;
      if (detail.editable.can_edit_custom_fields && form.customFields.length > 0) {
        const cfResult = await saveConsultantPortfolioCustomFields(supabase, {
          portfolioEntryId: detail.portfolio_entry_id,
          values: form.customFields,
        });
        if (!cfResult.ok) {
          setErrorCode(cfResult.errorCode);
          return;
        }
        nextDetail = cfResult.detail;
      }
      setDetail(nextDetail);
      setEditing(false);
      router.refresh();
    });
  };

  return (
    <div className="space-y-6" data-testid="consultant-portfolio-detail">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <Link
          href={returnHref}
          className="text-sm text-slate-600 underline underline-offset-2"
          data-testid="detail-back-link"
        >
          {t("backToWorkspace")}
        </Link>
        {detail.editable.can_edit_profile && !editing ? (
          <button
            type="button"
            className="rounded border border-slate-300 px-3 py-1.5 text-sm"
            onClick={() => setEditing(true)}
            data-testid="detail-edit-toggle"
          >
            {t("edit")}
          </button>
        ) : null}
      </div>

      <header>
        <h1 className="text-xl font-semibold text-slate-900">{t("title")}</h1>
        <p className="text-sm text-slate-600">
          {t("sttLabel", { stt: detail.workspace_sequence })}
          {detail.is_hidden ? ` · ${t("hiddenRowHint")}` : ""}
        </p>
      </header>

      {errorCode ? (
        <p className="text-sm text-red-700" role="alert" data-testid="detail-error">
          {t(`errors.${errorCode}` as "errors.unknown")}
        </p>
      ) : null}

      <section className="space-y-3 rounded-lg border border-slate-200 bg-white p-4">
        <h2 className="text-sm font-semibold text-slate-800">{t("sections.identity")}</h2>
        {editing ? (
          <div className="grid gap-3 sm:grid-cols-2">
            <label className="block text-sm">
              <span className="text-slate-600">{tWs("columns.familyName")}</span>
              <input
                className="mt-1 w-full rounded border border-slate-300 px-2 py-1.5 uppercase"
                value={form.familyName}
                onChange={(e) => setForm((p) => ({ ...p, familyName: e.target.value }))}
                data-testid="detail-family-name"
              />
            </label>
            <label className="block text-sm">
              <span className="text-slate-600">{tWs("columns.givenName")}</span>
              <input
                className="mt-1 w-full rounded border border-slate-300 px-2 py-1.5 uppercase"
                value={form.givenName}
                onChange={(e) => setForm((p) => ({ ...p, givenName: e.target.value }))}
                data-testid="detail-given-name"
              />
            </label>
            <label className="block text-sm sm:col-span-2">
              <span className="text-slate-600">{t("dateOfBirth")}</span>
              <input
                type="date"
                className="mt-1 w-full rounded border border-slate-300 px-2 py-1.5"
                value={form.dateOfBirth}
                disabled={!detail.editable.can_edit_date_of_birth}
                onChange={(e) => setForm((p) => ({ ...p, dateOfBirth: e.target.value }))}
                data-testid="detail-dob"
              />
            </label>
            <label className="block text-sm sm:col-span-2">
              <span className="text-slate-600">{tWs("columns.personalId")}</span>
              <input
                className="mt-1 w-full rounded border border-slate-300 px-2 py-1.5"
                value={form.personalIdentificationNumber}
                disabled={!detail.editable.can_edit_profile}
                onChange={(e) =>
                  setForm((p) => ({ ...p, personalIdentificationNumber: e.target.value }))
                }
                data-testid="detail-personal-id"
              />
            </label>
          </div>
        ) : (
          <dl className="grid gap-2 text-sm sm:grid-cols-2">
            <div>
              <dt className="text-slate-500">{tWs("columns.familyName")}</dt>
              <dd data-testid="detail-display-family">
                {formatPortfolioNamePart(detail.family_name, locale)}
              </dd>
            </div>
            <div>
              <dt className="text-slate-500">{tWs("columns.givenName")}</dt>
              <dd data-testid="detail-display-given">
                {formatPortfolioNamePart(detail.given_name, locale)}
              </dd>
            </div>
            <div>
              <dt className="text-slate-500">{tWs("columns.studentCode")}</dt>
              <dd data-testid="detail-student-code">
                {detail.student_code_display ?? "—"}
                {detail.student_code_is_provisional ? (
                  <span className="ml-1 text-xs text-slate-500">({t("provisionalCode")})</span>
                ) : null}
              </dd>
            </div>
            <div>
              <dt className="text-slate-500">{tWs("columns.status")}</dt>
              <dd data-testid="detail-lifecycle">{lifecycleLabel}</dd>
            </div>
            <div>
              <dt className="text-slate-500">{t("dateOfBirth")}</dt>
              <dd data-testid="detail-dob-display">{detail.date_of_birth ?? "—"}</dd>
            </div>
            <div>
              <dt className="text-slate-500">{tWs("columns.personalId")}</dt>
              <dd data-testid="detail-personal-id-display">
                {detail.personal_identification_number ?? "—"}
              </dd>
            </div>
          </dl>
        )}
      </section>

      <section className="space-y-3 rounded-lg border border-slate-200 bg-white p-4">
        <h2 className="text-sm font-semibold text-slate-800">{t("sections.guardian")}</h2>
        {editing ? (
          <div className="grid gap-3 sm:grid-cols-2">
            <label className="block text-sm">
              <span className="text-slate-600">{t("guardianFamilyName")}</span>
              <input
                className="mt-1 w-full rounded border border-slate-300 px-2 py-1.5"
                value={form.guardianFamilyName}
                onChange={(e) => setForm((p) => ({ ...p, guardianFamilyName: e.target.value }))}
                data-testid="detail-guardian-family"
              />
            </label>
            <label className="block text-sm">
              <span className="text-slate-600">{t("guardianGivenName")}</span>
              <input
                className="mt-1 w-full rounded border border-slate-300 px-2 py-1.5"
                value={form.guardianGivenName}
                onChange={(e) => setForm((p) => ({ ...p, guardianGivenName: e.target.value }))}
                data-testid="detail-guardian-given"
              />
            </label>
            <label className="block text-sm sm:col-span-2">
              <span className="text-slate-600">{tWs("columns.phone")}</span>
              <input
                className="mt-1 w-full rounded border border-slate-300 px-2 py-1.5"
                value={form.guardianPhone}
                onChange={(e) => setForm((p) => ({ ...p, guardianPhone: e.target.value }))}
                data-testid="detail-guardian-phone"
              />
            </label>
          </div>
        ) : (
          <dl className="grid gap-2 text-sm sm:grid-cols-2">
            <div>
              <dt className="text-slate-500">{tWs("columns.guardian")}</dt>
              <dd>
                {[detail.primary_guardian_family_name, detail.primary_guardian_given_name]
                  .filter(Boolean)
                  .join(" ") || "—"}
              </dd>
            </div>
            <div>
              <dt className="text-slate-500">{tWs("columns.phone")}</dt>
              <dd data-testid="detail-guardian-phone-display">{detail.primary_guardian_phone ?? "—"}</dd>
            </div>
          </dl>
        )}
      </section>

      <section className="space-y-3 rounded-lg border border-slate-200 bg-white p-4">
        <h2 className="text-sm font-semibold text-slate-800">{t("sections.learning")}</h2>
        <dl className="grid gap-2 text-sm sm:grid-cols-2">
          <div>
            <dt className="text-slate-500">{t("course")}</dt>
            <dd>{detail.course_name ?? "—"}</dd>
          </div>
          <div>
            <dt className="text-slate-500">{t("class")}</dt>
            <dd>{detail.class_name ?? "—"}</dd>
          </div>
          <div>
            <dt className="text-slate-500">{t("enrollmentStatus")}</dt>
            <dd>{detail.enrollment_status ?? "—"}</dd>
          </div>
        </dl>
      </section>

      <section
        className="space-y-3 rounded-lg border border-slate-200 bg-white p-4"
        data-testid="detail-finance-section"
      >
        <h2 className="text-sm font-semibold text-slate-800">{t("sections.finance")}</h2>
        <p className="text-xs text-slate-500">{t("financeReadOnly")}</p>
        <dl className="grid gap-2 text-sm sm:grid-cols-2">
          <div>
            <dt className="text-slate-500">{tWs("columns.tuition")}</dt>
            <dd>{formatMoneyVnd(detail.tuition_total_net, locale)}</dd>
          </div>
          <div>
            <dt className="text-slate-500">{t("confirmedPaid")}</dt>
            <dd>{formatMoneyVnd(detail.tuition_paid, locale)}</dd>
          </div>
          <div>
            <dt className="text-slate-500">{tWs("tuition.outstanding")}</dt>
            <dd>{formatMoneyVnd(detail.tuition_outstanding, locale)}</dd>
          </div>
          <div>
            <dt className="text-slate-500">{tWs("filters.paymentState")}</dt>
            <dd data-testid="detail-payment-state">{paymentLabel}</dd>
          </div>
        </dl>
      </section>

      {detail.custom_fields.length > 0 ? (
        <section className="space-y-3 rounded-lg border border-slate-200 bg-white p-4">
          <h2 className="text-sm font-semibold text-slate-800">{t("sections.consultantInfo")}</h2>
          <div className="grid gap-3">
            {detail.custom_fields.map((field, index) => (
              <label key={field.definition_id} className="block text-sm">
                <span className="text-slate-600">{field.label}</span>
                {editing && detail.editable.can_edit_custom_fields ? (
                  <input
                    className="mt-1 w-full rounded border border-slate-300 px-2 py-1.5"
                    value={form.customFields[index]?.value ?? ""}
                    onChange={(e) =>
                      setForm((p) => {
                        const customFields = [...p.customFields];
                        customFields[index] = { field_key: field.field_key, value: e.target.value };
                        return { ...p, customFields };
                      })
                    }
                    data-testid={`detail-custom-${field.field_key}`}
                  />
                ) : (
                  <span className="mt-1 block" data-testid={`detail-custom-display-${field.field_key}`}>
                    {field.value || "—"}
                  </span>
                )}
              </label>
            ))}
          </div>
        </section>
      ) : null}

      <section className="flex flex-wrap gap-2">
        {detail.capabilities.can_create_payment_declaration ||
        detail.capabilities.can_open_payment_declaration ? (
          <button
            type="button"
            className="rounded bg-slate-900 px-3 py-2 text-sm text-white"
            ref={drawerTriggerRef}
            onClick={() => setDrawerOpen(true)}
            data-testid="detail-declare-payment"
          >
            {tWs("declaration.openAction")}
          </button>
        ) : null}
        {editing ? (
          <>
            <button
              type="button"
              className="rounded border border-slate-300 px-3 py-2 text-sm"
              disabled={pending}
              onClick={() => setEditing(false)}
              data-testid="detail-cancel"
            >
              {t("cancel")}
            </button>
            <button
              type="button"
              className="rounded bg-slate-900 px-3 py-2 text-sm text-white disabled:opacity-50"
              disabled={pending}
              onClick={onSave}
              data-testid="detail-save"
            >
              {pending ? t("saving") : t("save")}
            </button>
          </>
        ) : null}
      </section>

      {drawerOpen ? (
        <PaymentDeclarationDrawer
          key={detail.portfolio_entry_id}
          row={declarationRow}
          onClose={() => setDrawerOpen(false)}
          onSuccess={() => {
            setDrawerOpen(false);
            router.refresh();
          }}
          triggerRef={drawerTriggerRef}
        />
      ) : null}
    </div>
  );
}
