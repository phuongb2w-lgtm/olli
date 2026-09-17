import Link from "next/link";
import { getTranslations } from "next-intl/server";
import { LeadIntakeForm } from "@/components/leads/lead-intake-form";
import { can } from "@/lib/permissions/can";
import { queryEligibleAssignees } from "@/lib/leads/query-eligible-assignees";
import { queryLeadCatalogs } from "@/lib/leads/query-lead-catalogs";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

export default async function NewLeadPage() {
  const t = await getTranslations("crm.intake");
  const hasCreate = await can("lead.create");
  const hasAssign = await can("lead.assign");

  if (!hasCreate) {
    return (
      <div className="space-y-4">
        <h1 className="text-xl font-semibold">{t("title")}</h1>
        <section className="rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-600">
          <p>{t("denied")}</p>
        </section>
      </div>
    );
  }

  const supabase = await createClient();
  const [{ sources, campaigns, error: catalogError }, { assignees }] = await Promise.all([
    queryLeadCatalogs(supabase),
    hasAssign ? queryEligibleAssignees(supabase) : Promise.resolve({ assignees: [], error: false }),
  ]);

  if (catalogError) {
    return (
      <div className="space-y-4">
        <h1 className="text-xl font-semibold">{t("title")}</h1>
        <section className="rounded-lg border border-red-200 bg-red-50 p-4 text-sm text-red-800">
          <p>{t("loadError")}</p>
        </section>
      </div>
    );
  }

  return (
    <div className="space-y-4">
      <Link href="/crm/leads" className="text-sm text-slate-600 hover:text-slate-900">
        {t("backToList")}
      </Link>
      <h1 className="text-xl font-semibold text-slate-900">{t("title")}</h1>
      <p className="text-sm text-slate-600">{t("subtitle")}</p>
      <LeadIntakeForm
        sources={sources}
        campaigns={campaigns}
        assignees={assignees}
        canAssign={hasAssign}
      />
    </div>
  );
}
