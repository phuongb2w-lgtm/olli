"use client";

import { useActionState } from "react";
import { useTranslations } from "next-intl";
import { retireCapitalAsset, type CapitalAssetActionState } from "@/app/actions/capital-assets";

type Props = { assetId: string };

const initialState: CapitalAssetActionState = {};

async function retireAction(_prev: CapitalAssetActionState, formData: FormData) {
  return retireCapitalAsset(String(formData.get("assetId")), String(formData.get("retiredAt")));
}

export function RetireAssetForm({ assetId }: Props) {
  const t = useTranslations("finance.assets");
  const tCommon = useTranslations("finance.common");
  const [state, formAction, pending] = useActionState(retireAction, initialState);

  return (
    <form action={formAction} className="rounded-lg border border-amber-200 bg-amber-50 p-4 text-sm">
      <input type="hidden" name="assetId" value={assetId} />
      <label className="block">
        <span>{t("retireDate")}</span>
        <input name="retiredAt" type="date" required className="mt-1 rounded border border-slate-300 px-3 py-2" />
      </label>
      {state.error ? <p className="mt-2 text-red-700">{tCommon("saveError")}</p> : null}
      <button type="submit" disabled={pending} className="mt-3 rounded bg-amber-800 px-4 py-2 text-sm text-white disabled:opacity-50">
        {pending ? tCommon("saving") : t("retire")}
      </button>
    </form>
  );
}
