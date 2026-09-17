import Link from "next/link";
import { getTranslations } from "next-intl/server";
import { CrmSettingsView } from "@/components/crm/crm-settings-view";
import { can } from "@/lib/permissions/can";
import { queryLeadCatalogs } from "@/lib/leads/query-lead-catalogs";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

export default async function CrmSettingsPage() {
  const t = await getTranslations("crm.settings");
  const hasManage = await can("lead.manage_sources");

  if (!hasManage) {
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
  const { sources, campaigns, lostReasons, error } = await queryLeadCatalogs(supabase);

  if (error) {
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
        {t("backToLeads")}
      </Link>
      <h1 className="text-xl font-semibold text-slate-900">{t("title")}</h1>
      <p className="text-sm text-slate-600">{t("subtitle")}</p>
      <CrmSettingsView sources={sources} campaigns={campaigns} lostReasons={lostReasons} />
    </div>
  );
}
