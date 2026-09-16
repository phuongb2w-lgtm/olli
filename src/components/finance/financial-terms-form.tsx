"use client";

import { useActionState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import {
  activateEnrollmentFinancialTerms,
  createDraftEnrollmentFinancialTerms,
  generateEnrollmentCharges,
  setEqualInstallmentPaymentSchedule,
  setFullUpfrontPaymentSchedule,
  type EnrollmentFinanceActionState,
} from "@/app/actions/enrollment-finance";

type TermsRow = {
  id: string;
  status: string;
  agreedTuitionAmount: number;
  discountAmount: number;
  netTuitionAmount: number;
};

type Props = {
  enrollmentId: string;
  draftTerms: TermsRow | null;
  activeTerms: TermsRow | null;
  canManage: boolean;
};

const initialState: EnrollmentFinanceActionState = {};

async function createTermsAction(_prev: EnrollmentFinanceActionState, formData: FormData) {
  return createDraftEnrollmentFinancialTerms({
    enrollmentId: String(formData.get("enrollmentId")),
    agreedTuitionAmount: Number(formData.get("agreedTuitionAmount")),
    discountAmount: Number(formData.get("discountAmount") ?? 0),
    agreementDate: String(formData.get("agreementDate") ?? ""),
  });
}

export function FinancialTermsForm({ enrollmentId, draftTerms, activeTerms, canManage }: Props) {
  const t = useTranslations("finance.enrollment");
  const tTerms = useTranslations("tuitionTerms");
  const tSchedule = useTranslations("paymentSchedule");
  const tCommon = useTranslations("finance.common");
  const router = useRouter();
  const [createState, createAction, createPending] = useActionState(createTermsAction, initialState);
  const [pending, startTransition] = useTransition();

  const termsId = draftTerms?.id ?? createState.termsId;

  if (activeTerms) {
    return (
      <section className="rounded-lg border border-slate-200 bg-white p-4 text-sm">
        <p className="font-medium">{t("activeTerms")}</p>
        <dl className="mt-2 grid gap-2 sm:grid-cols-3">
          <div><dt className="text-slate-600">{tTerms("agreedTuition")}</dt><dd>{activeTerms.agreedTuitionAmount}</dd></div>
          <div><dt className="text-slate-600">{tTerms("discount")}</dt><dd>{activeTerms.discountAmount}</dd></div>
          <div><dt className="text-slate-600">{t("netTuition")}</dt><dd>{activeTerms.netTuitionAmount}</dd></div>
        </dl>
        <p className="mt-3 text-slate-600">{t("activeTermsLocked")}</p>
      </section>
    );
  }

  if (!canManage) {
    return (
      <section className="rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-600">
        <p>{t("noTerms")}</p>
      </section>
    );
  }

  function run(action: () => Promise<unknown>) {
    startTransition(async () => {
      await action();
      router.refresh();
    });
  }

  return (
    <div className="space-y-4">
      {!termsId ? (
        <form action={createAction} className="space-y-3 rounded-lg border border-slate-200 bg-white p-4 text-sm">
          <input type="hidden" name="enrollmentId" value={enrollmentId} />
          <label className="block">
            <span>{tTerms("agreedTuition")}</span>
            <input name="agreedTuitionAmount" type="number" min={0} required className="mt-1 w-full rounded border border-slate-300 px-3 py-2" />
          </label>
          <label className="block">
            <span>{tTerms("discount")}</span>
            <input name="discountAmount" type="number" min={0} defaultValue={0} className="mt-1 w-full rounded border border-slate-300 px-3 py-2" />
          </label>
          <label className="block">
            <span>{tTerms("agreementDate")}</span>
            <input name="agreementDate" type="date" required className="mt-1 w-full rounded border border-slate-300 px-3 py-2" />
          </label>
          <button type="submit" disabled={createPending} className="rounded bg-slate-900 px-4 py-2 text-sm text-white disabled:opacity-50">
            {createPending ? tCommon("saving") : t("createDraftTerms")}
          </button>
        </form>
      ) : (
        <section className="space-y-4 rounded-lg border border-slate-200 bg-white p-4 text-sm">
          <p className="font-medium">{t("configureSchedule")}</p>
          <div className="space-y-3 border-t border-slate-100 pt-3">
            <p className="font-medium">{tSchedule("fullPayment")}</p>
            <input id="full-due" type="date" className="rounded border border-slate-300 px-3 py-2" />
            <button
              type="button"
              disabled={pending}
              onClick={() => {
                const el = document.getElementById("full-due") as HTMLInputElement;
                run(() => setFullUpfrontPaymentSchedule(termsId, el.value));
              }}
              className="ml-2 rounded border border-slate-300 px-3 py-2 text-sm"
            >
              {tCommon("apply")}
            </button>
          </div>
          <div className="space-y-3 border-t border-slate-100 pt-3">
            <p className="font-medium">{tSchedule("installments")}</p>
            <input id="inst-count" type="number" min={2} defaultValue={3} className="rounded border border-slate-300 px-3 py-2" />
            <input id="inst-date" type="date" className="ml-2 rounded border border-slate-300 px-3 py-2" />
            <button
              type="button"
              disabled={pending}
              onClick={() => {
                const count = Number((document.getElementById("inst-count") as HTMLInputElement).value);
                const date = (document.getElementById("inst-date") as HTMLInputElement).value;
                run(() => setEqualInstallmentPaymentSchedule(termsId, count, date));
              }}
              className="ml-2 rounded border border-slate-300 px-3 py-2 text-sm"
            >
              {tCommon("apply")}
            </button>
          </div>
          <div className="flex flex-wrap gap-2 pt-2">
            <button
              type="button"
              disabled={pending}
              onClick={() => run(() => activateEnrollmentFinancialTerms(termsId))}
              className="rounded bg-slate-900 px-4 py-2 text-sm text-white disabled:opacity-50"
            >
              {t("activateTerms")}
            </button>
            <button
              type="button"
              disabled={pending}
              onClick={() => run(() => generateEnrollmentCharges(termsId))}
              className="rounded border border-slate-300 px-4 py-2 text-sm disabled:opacity-50"
            >
              {t("generateCharges")}
            </button>
          </div>
        </section>
      )}
    </div>
  );
}
