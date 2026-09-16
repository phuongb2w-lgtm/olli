"use client";

import { useActionState, useEffect } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import {
  createDetailedCapitalAsset,
  createQuickCapitalAsset,
  type CapitalAssetActionState,
} from "@/app/actions/capital-assets";

type Props = { mode: "quick" | "detailed" };

const initialState: CapitalAssetActionState = {};

async function createQuickAction(_prev: CapitalAssetActionState, formData: FormData) {
  return createQuickCapitalAsset({
    name: String(formData.get("name") ?? ""),
    totalInvestment: Number(formData.get("totalInvestment")),
    usefulLifeMonths: Number(formData.get("usefulLifeMonths")),
    placedInServiceDate: String(formData.get("placedInServiceDate") ?? ""),
  });
}

async function createDetailedAction(_prev: CapitalAssetActionState, formData: FormData) {
  return createDetailedCapitalAsset({
    name: String(formData.get("name") ?? ""),
    originalCost: Number(formData.get("originalCost")),
    usefulLifeMonths: Number(formData.get("usefulLifeMonths")),
    placedInServiceDate: String(formData.get("placedInServiceDate") ?? ""),
    categoryCode: (String(formData.get("categoryCode") ?? "") || null) as
      | "fit_out"
      | "signage"
      | "furniture"
      | "equipment"
      | "technology"
      | "other_capital"
      | null,
    notes: String(formData.get("notes") ?? "") || null,
  });
}

export function CapitalAssetForm({ mode }: Props) {
  const t = useTranslations("finance.assets");
  const tCommon = useTranslations("finance.common");
  const router = useRouter();
  const action = mode === "quick" ? createQuickAction : createDetailedAction;
  const [state, formAction, pending] = useActionState(action, initialState);

  useEffect(() => {
    if (state.assetId) {
      router.push(`/finance/costs/assets/${state.assetId}`);
    }
  }, [state.assetId, router]);

  return (
    <form action={formAction} className="max-w-lg space-y-4 rounded-lg border border-slate-200 bg-white p-4">
      <label className="block text-sm">
        <span>{t("name")}</span>
        <input name="name" required className="mt-1 w-full rounded border border-slate-300 px-3 py-2" />
      </label>
      {mode === "quick" ? (
        <label className="block text-sm">
          <span>{t("totalInvestment")}</span>
          <input name="totalInvestment" type="number" min={1} required className="mt-1 w-full rounded border border-slate-300 px-3 py-2" />
        </label>
      ) : (
        <>
          <label className="block text-sm">
            <span>{t("originalCost")}</span>
            <input name="originalCost" type="number" min={1} required className="mt-1 w-full rounded border border-slate-300 px-3 py-2" />
          </label>
          <label className="block text-sm">
            <span>{t("category")}</span>
            <input name="categoryCode" className="mt-1 w-full rounded border border-slate-300 px-3 py-2" />
          </label>
          <label className="block text-sm">
            <span>{t("notes")}</span>
            <textarea name="notes" rows={2} className="mt-1 w-full rounded border border-slate-300 px-3 py-2" />
          </label>
        </>
      )}
      <label className="block text-sm">
        <span>{t("usefulLifeMonths")}</span>
        <input name="usefulLifeMonths" type="number" min={1} required className="mt-1 w-full rounded border border-slate-300 px-3 py-2" />
      </label>
      <label className="block text-sm">
        <span>{t("placedInServiceDate")}</span>
        <input name="placedInServiceDate" type="date" required className="mt-1 w-full rounded border border-slate-300 px-3 py-2" />
      </label>
      <div className="flex gap-3">
        <button type="submit" disabled={pending} className="rounded bg-slate-900 px-4 py-2 text-sm text-white disabled:opacity-50">
          {pending ? tCommon("saving") : t("create")}
        </button>
        <Link href="/finance/costs/assets" className="rounded border border-slate-300 px-4 py-2 text-sm">
          {tCommon("cancel")}
        </Link>
      </div>
    </form>
  );
}
