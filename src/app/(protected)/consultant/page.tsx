import { getTranslations } from "next-intl/server";
import { ConsultantPortfolioWorkspace } from "@/components/consultant-workspace/consultant-portfolio-workspace";
import { loadConsultantGridPreferencesAction } from "@/app/actions/consultant-workspace";
import { can } from "@/lib/permissions/can";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

export default async function ConsultantWorkspacePage() {
  const t = await getTranslations("consultantWorkspace");

  if (!(await can("consultant_workspace.read"))) {
    return (
      <section
        className="rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-600"
        data-testid="consultant-workspace-denied"
      >
        <p>{t("denied")}</p>
      </section>
    );
  }

  const initialPreferences = await loadConsultantGridPreferencesAction();

  let courseOptions: { id: string; name: string }[] = [];
  if (await can("enrollment.read")) {
    const supabase = await createClient();
    const { data } = await supabase
      .from("course")
      .select("id, name")
      .order("name")
      .limit(200);
    courseOptions =
      data?.map((row) => ({ id: row.id, name: row.name ?? row.id })) ?? [];
  }

  return (
    <ConsultantPortfolioWorkspace
      initialPreferences={initialPreferences}
      courseOptions={courseOptions}
    />
  );
}
