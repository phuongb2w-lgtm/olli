import { getTranslations } from "next-intl/server";
import { CrmNav } from "@/components/crm/crm-nav";
import { can } from "@/lib/permissions/can";

export const dynamic = "force-dynamic";

export default async function CrmLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  const t = await getTranslations("crm");
  const hasRead = await can("lead.read");

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-xl font-semibold text-slate-900">{t("title")}</h1>
        <p className="mt-1 text-sm text-slate-500">{t("subtitle")}</p>
      </div>
      {hasRead ? <CrmNav /> : null}
      {children}
    </div>
  );
}
