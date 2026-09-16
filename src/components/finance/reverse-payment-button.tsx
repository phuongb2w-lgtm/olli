"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { reversePayment } from "@/app/actions/payments";

type Props = { paymentId: string };

export function ReversePaymentButton({ paymentId }: Props) {
  const t = useTranslations("finance.payments");
  const router = useRouter();
  const [confirmed, setConfirmed] = useState(false);
  const [pending, startTransition] = useTransition();

  function handleReverse() {
    if (!confirmed) return;
    startTransition(async () => {
      await reversePayment(paymentId);
      router.refresh();
    });
  }

  return (
    <div className="rounded-lg border border-amber-200 bg-amber-50 p-4 text-sm">
      <label className="flex items-center gap-2">
        <input type="checkbox" checked={confirmed} onChange={(e) => setConfirmed(e.target.checked)} />
        <span>{t("reverseConfirm")}</span>
      </label>
      <button
        type="button"
        onClick={handleReverse}
        disabled={!confirmed || pending}
        className="mt-3 rounded bg-amber-800 px-4 py-2 text-sm font-medium text-white hover:bg-amber-900 disabled:opacity-50"
      >
        {pending ? t("reversing") : t("reversePayment")}
      </button>
    </div>
  );
}
