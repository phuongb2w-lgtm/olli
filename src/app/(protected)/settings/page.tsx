import Link from "next/link";
import { getTranslations } from "next-intl/server";
import { can } from "@/lib/permissions/can";

export const dynamic = "force-dynamic";

export default async function SettingsPage() {
  const t = await getTranslations("settings");

  const canOrg = await can("organization.update");
  const canRoles = await can("role.read") || (await can("role.manage"));
  const canCrmSources = await can("lead.manage_sources");

  if (!canOrg && !canRoles && !canCrmSources) {
    return (
      <div className="space-y-4">
        <h1 className="text-xl font-semibold">{t("title")}</h1>
        <section className="rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-600">
          <p>{t("denied")}</p>
        </section>
      </div>
    );
  }

  return (
    <div className="space-y-4">
      <h1 className="text-xl font-semibold">{t("title")}</h1>
      <ul className="space-y-2 text-sm">
        {canCrmSources ? (
          <li>
            <Link href="/crm/settings" className="font-medium text-slate-900 underline">
              {t("crmSources")}
            </Link>
          </li>
        ) : null}
        {canOrg ? <li>{t("organizationFoundation")}</li> : null}
        {canRoles ? <li>{t("rolesFoundation")}</li> : null}
      </ul>
    </div>
  );
}
