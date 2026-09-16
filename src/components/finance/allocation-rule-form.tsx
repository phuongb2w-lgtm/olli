"use client";

import { useActionState } from "react";
import { useTranslations } from "next-intl";
import { createCostAllocationRule, type CostAllocationActionState } from "@/app/actions/cost-allocation";

const initialState: CostAllocationActionState = {};

async function submitAction(_prev: CostAllocationActionState, formData: FormData) {
  return createCostAllocationRule({
    sourceScopeCode: String(formData.get("sourceScopeCode")),
    allocationBasisCode: String(formData.get("allocationBasisCode")),
    effectiveFrom: String(formData.get("effectiveFrom")),
    notes: String(formData.get("notes") ?? "") || null,
  });
}

export function AllocationRuleForm() {
  const t = useTranslations("finance.allocationRules");
  const tScope = useTranslations("finance.sourceScope");
  const tBasis = useTranslations("allocationBasis");
  const tCommon = useTranslations("finance.common");
  const [state, formAction, pending] = useActionState(submitAction, initialState);

  return (
    <form action={formAction} className="flex flex-wrap items-end gap-3 rounded-lg border border-slate-200 bg-white p-4 text-sm">
      <label>
        <span className="mb-1 block">{t("sourceScope")}</span>
        <select name="sourceScopeCode" className="rounded border border-slate-300 px-3 py-2">
          <option value="operating_overhead">{tScope("operating_overhead")}</option>
          <option value="marketing_sales">{tScope("marketing_sales")}</option>
          <option value="depreciation">{tScope("depreciation")}</option>
        </select>
      </label>
      <label>
        <span className="mb-1 block">{t("basis")}</span>
        <select name="allocationBasisCode" className="rounded border border-slate-300 px-3 py-2">
          <option value="equal">{tBasis("equal")}</option>
          <option value="active_enrollment_count">{tBasis("active_enrollment_count")}</option>
          <option value="delivered_session_count">{tBasis("delivered_session_count")}</option>
          <option value="recognized_revenue">{tBasis("recognized_revenue")}</option>
        </select>
      </label>
      <label>
        <span className="mb-1 block">{t("effectiveFrom")}</span>
        <input name="effectiveFrom" type="date" required className="rounded border border-slate-300 px-3 py-2" />
      </label>
      <label>
        <span className="mb-1 block">{tCommon("notes")}</span>
        <input name="notes" className="rounded border border-slate-300 px-3 py-2" />
      </label>
      <button type="submit" disabled={pending} className="rounded bg-slate-900 px-4 py-2 text-sm text-white disabled:opacity-50">
        {pending ? tCommon("saving") : t("createRule")}
      </button>
      {state.error ? <p className="w-full text-red-700">{tCommon("saveError")}</p> : null}
      {state.ruleId ? <p className="w-full text-green-800">{t("created")}</p> : null}
    </form>
  );
}
