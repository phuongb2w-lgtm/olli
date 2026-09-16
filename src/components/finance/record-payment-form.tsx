"use client";

import { useActionState, useState, useTransition } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import {
  allocatePayment,
  recordPaymentFormAction,
  suggestPaymentAllocation,
  type PaymentActionState,
} from "@/app/actions/payments";
import { PAYMENT_METHOD_CODES } from "@/lib/payments/constants";

type GuardianOption = { id: string; name: string };
type ChargeOption = {
  chargeId: string;
  dueDate: string;
  chargeAmount: number;
  adjustments: number;
  outstandingBalance: number;
};

type Props = {
  guardians: GuardianOption[];
  enrollmentId?: string;
  studentId?: string;
  charges?: ChargeOption[];
};

const initialState: PaymentActionState = {};

export function RecordPaymentForm({ guardians, enrollmentId, studentId, charges = [] }: Props) {
  const t = useTranslations("finance.payments");
  const tMethod = useTranslations("paymentMethod");
  const tCommon = useTranslations("finance.common");
  const router = useRouter();
  const [state, formAction, pending] = useActionState(recordPaymentFormAction, initialState);
  const recordedPayment = state.payment as Record<string, unknown> | undefined;
  const paymentId = recordedPayment
    ? String(recordedPayment.payment_id ?? recordedPayment.id ?? "")
    : null;
  const [suggestions, setSuggestions] = useState<Array<{ chargeId: string; amount: number }>>([]);
  const [allocations, setAllocations] = useState<Record<string, number>>({});
  const [isSuggesting, startSuggest] = useTransition();
  const [isAllocating, startAllocate] = useTransition();
  const [amount, setAmount] = useState("");

  const globalError =
    state.error === "permission_denied"
      ? tCommon("permissionDenied")
      : state.error === "validation_error"
        ? tCommon("validationError")
        : state.error === "save_error"
          ? tCommon("saveError")
          : null;

  function handleSuggest() {
    if (!paymentId) return;
    startSuggest(async () => {
      const result = await suggestPaymentAllocation(paymentId, { enrollmentId, studentId });
      const sug = result.suggestions as Record<string, unknown> | undefined;
      const items = (sug?.suggestions as Array<{ charge_id: string; amount: number }>) ?? [];
      setSuggestions(items.map((i) => ({ chargeId: i.charge_id, amount: Number(i.amount) })));
      const next: Record<string, number> = {};
      items.forEach((i) => {
        next[i.charge_id] = Number(i.amount);
      });
      setAllocations(next);
    });
  }

  function handleApplyAllocations() {
    if (!paymentId) return;
    startAllocate(async () => {
      const payload = Object.entries(allocations)
        .filter(([, v]) => v > 0)
        .map(([chargeId, amt]) => ({ chargeId, amount: amt }));
      await allocatePayment({ paymentId, allocations: payload });
      router.push(`/finance/payments/${paymentId}`);
      router.refresh();
    });
  }

  const paymentAmount = Number(amount) || 0;
  const allocatedTotal = Object.values(allocations).reduce((s, v) => s + v, 0);
  const unallocatedTotal = Math.max(paymentAmount - allocatedTotal, 0);

  return (
    <div className="space-y-6">
      {!paymentId ? (
        <form action={formAction} className="max-w-lg space-y-4 rounded-lg border border-slate-200 bg-white p-4">
          {globalError ? <p className="text-sm text-red-700">{globalError}</p> : null}
          <label className="block text-sm">
            <span className="text-slate-700">{t("guardian")}</span>
            <select name="guardianId" required className="mt-1 w-full rounded border border-slate-300 px-3 py-2">
              <option value="">{t("selectGuardian")}</option>
              {guardians.map((g) => (
                <option key={g.id} value={g.id}>
                  {g.name}
                </option>
              ))}
            </select>
          </label>
          {studentId ? <input type="hidden" name="studentId" value={studentId} /> : null}
          <label className="block text-sm">
            <span className="text-slate-700">{t("amount")}</span>
            <input
              name="amount"
              type="number"
              min={1}
              required
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
              className="mt-1 w-full rounded border border-slate-300 px-3 py-2"
            />
          </label>
          <label className="block text-sm">
            <span className="text-slate-700">{t("paymentDate")}</span>
            <input
              name="paidAt"
              type="datetime-local"
              className="mt-1 w-full rounded border border-slate-300 px-3 py-2"
            />
          </label>
          <label className="block text-sm">
            <span className="text-slate-700">{t("method")}</span>
            <select name="methodCode" defaultValue="cash" className="mt-1 w-full rounded border border-slate-300 px-3 py-2">
              {PAYMENT_METHOD_CODES.map((code) => (
                <option key={code} value={code}>
                  {tMethod(code)}
                </option>
              ))}
            </select>
          </label>
          <label className="block text-sm">
            <span className="text-slate-700">{t("reference")}</span>
            <input name="referenceNumber" className="mt-1 w-full rounded border border-slate-300 px-3 py-2" />
          </label>
          <label className="block text-sm">
            <span className="text-slate-700">{t("payer")}</span>
            <input name="payerNameSnapshot" className="mt-1 w-full rounded border border-slate-300 px-3 py-2" />
          </label>
          <label className="block text-sm">
            <span className="text-slate-700">{t("notes")}</span>
            <textarea name="notes" rows={3} className="mt-1 w-full rounded border border-slate-300 px-3 py-2" />
          </label>
          <div className="flex gap-3">
            <button
              type="submit"
              disabled={pending}
              className="rounded bg-slate-900 px-4 py-2 text-sm font-medium text-white hover:bg-slate-800 disabled:opacity-50"
            >
              {pending ? tCommon("saving") : t("recordPayment")}
            </button>
            <Link href="/finance/payments" className="rounded border border-slate-300 px-4 py-2 text-sm">
              {tCommon("cancel")}
            </Link>
          </div>
        </form>
      ) : (
        <section className="space-y-4 rounded-lg border border-slate-200 bg-white p-4">
          <p className="text-sm text-green-800">{t("recordedSuccess")}</p>
          <div className="grid gap-3 sm:grid-cols-3 text-sm">
            <div>
              <p className="text-slate-600">{t("amount")}</p>
              <p className="font-medium">{paymentAmount || "—"}</p>
            </div>
            <div>
              <p className="text-slate-600">{t("allocated")}</p>
              <p className="font-medium">{allocatedTotal}</p>
            </div>
            <div>
              <p className="text-slate-600">{t("unallocated")}</p>
              <p className="font-medium">{unallocatedTotal}</p>
            </div>
          </div>
          <button
            type="button"
            onClick={handleSuggest}
            disabled={isSuggesting}
            className="rounded border border-slate-300 px-4 py-2 text-sm hover:bg-slate-50"
          >
            {isSuggesting ? tCommon("loading") : t("suggestAllocation")}
          </button>
          {charges.length > 0 || suggestions.length > 0 ? (
            <div className="overflow-x-auto">
              <table className="min-w-full text-sm">
                <thead>
                  <tr className="border-b border-slate-200 text-left">
                    <th className="py-2 pr-4">{t("dueDate")}</th>
                    <th className="py-2 pr-4">{t("chargeAmount")}</th>
                    <th className="py-2 pr-4">{t("outstanding")}</th>
                    <th className="py-2">{t("allocationAmount")}</th>
                  </tr>
                </thead>
                <tbody>
                  {(charges.length ? charges : suggestions.map((s) => ({
                    chargeId: s.chargeId,
                    dueDate: "",
                    chargeAmount: 0,
                    adjustments: 0,
                    outstandingBalance: s.amount,
                  }))).map((c) => (
                    <tr key={c.chargeId} className="border-b border-slate-100">
                      <td className="py-2 pr-4">{c.dueDate || "—"}</td>
                      <td className="py-2 pr-4">{c.chargeAmount}</td>
                      <td className="py-2 pr-4">{c.outstandingBalance}</td>
                      <td className="py-2">
                        <input
                          type="number"
                          min={0}
                          value={allocations[c.chargeId] ?? ""}
                          onChange={(e) =>
                            setAllocations((prev) => ({
                              ...prev,
                              [c.chargeId]: Number(e.target.value) || 0,
                            }))
                          }
                          className="w-32 rounded border border-slate-300 px-2 py-1"
                        />
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          ) : null}
          <button
            type="button"
            onClick={handleApplyAllocations}
            disabled={isAllocating || allocatedTotal <= 0}
            className="rounded bg-slate-900 px-4 py-2 text-sm font-medium text-white hover:bg-slate-800 disabled:opacity-50"
          >
            {isAllocating ? tCommon("saving") : t("applyAllocation")}
          </button>
        </section>
      )}
    </div>
  );
}
