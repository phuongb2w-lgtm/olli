import { getTranslations } from "next-intl/server";
import { can } from "@/lib/permissions/can";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

export default async function ExecutiveOverviewPage() {
  const t = await getTranslations("executive");

  if (!(await can("report.executive.read"))) {
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
  const { data, error } = await supabase.rpc("get_executive_reporting_access");

  return (
    <div className="space-y-4">
      <h1 className="text-xl font-semibold">{t("title")}</h1>
      <p className="text-sm text-slate-600">{t("foundationDescription")}</p>
      <section className="rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-700">
        <p>{t("accessConfirmed")}</p>
        {error ? (
          <p className="mt-2 text-red-600">{t("loadError")}</p>
        ) : (
          <pre className="mt-2 overflow-x-auto rounded bg-slate-50 p-2 text-xs">
            {JSON.stringify(data, null, 2)}
          </pre>
        )}
      </section>
    </div>
  );
}
