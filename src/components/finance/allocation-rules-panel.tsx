import { getTranslations } from "next-intl/server";
import { AllocationRuleForm } from "@/components/finance/allocation-rule-form";
import { can } from "@/lib/permissions/can";
import { formatDate } from "@/lib/formatting";
import { resolveLocale } from "@/i18n/resolve-locale";
import { getIdentityState } from "@/lib/auth/get-identity-state";
import { createClient } from "@/lib/supabase/server";

export async function AllocationRulesPanel() {
  const t = await getTranslations("finance.allocationRules");
  const tScope = await getTranslations("finance.sourceScope");
  const tBasis = await getTranslations("allocationBasis");
  const identity = await getIdentityState();
  const locale = await resolveLocale(identity.kind === "active" ? identity.appUser : null);

  if (!(await can("class_economics.read"))) return null;

  const canManage = await can("cost_allocation.manage");
  const supabase = await createClient();
  const { data: rules } = await supabase
    .from("cost_allocation_rule")
    .select("id, source_scope_code, allocation_basis_code, effective_from, effective_to, notes")
    .order("effective_from", { ascending: false });

  return (
    <section className="space-y-3">
      <h3 className="font-medium">{t("title")}</h3>
      {canManage ? <AllocationRuleForm /> : null}
      {(rules ?? []).length === 0 ? (
        <p className="text-sm text-slate-600">{t("empty")}</p>
      ) : (
        <div className="overflow-x-auto rounded-lg border border-slate-200 bg-white">
          <table className="min-w-full text-sm">
            <thead className="bg-slate-50">
              <tr>
                <th className="px-4 py-2 text-left">{t("sourceScope")}</th>
                <th className="px-4 py-2 text-left">{t("basis")}</th>
                <th className="px-4 py-2 text-left">{t("effectiveFrom")}</th>
                <th className="px-4 py-2 text-left">{t("effectiveTo")}</th>
              </tr>
            </thead>
            <tbody>
              {(rules ?? []).map((rule) => (
                <tr key={rule.id} className="border-t border-slate-100">
                  <td className="px-4 py-2">{tScope(rule.source_scope_code as "operating_overhead")}</td>
                  <td className="px-4 py-2">{tBasis(rule.allocation_basis_code as "equal")}</td>
                  <td className="px-4 py-2">{formatDate(rule.effective_from, locale)}</td>
                  <td className="px-4 py-2">{rule.effective_to ? formatDate(rule.effective_to, locale) : "—"}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </section>
  );
}
