import { getTranslations } from "next-intl/server";
import { SimulatorScenarioForm } from "@/components/finance/simulator-scenario-form";
import { can } from "@/lib/permissions/can";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

export default async function NewSimulatorScenarioPage() {
  const t = await getTranslations("finance.simulator");

  if (!(await can("class_simulation.manage"))) {
    return (
      <section className="rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-600">
        <p>{t("denied")}</p>
      </section>
    );
  }

  const supabase = await createClient();
  const { data: classes } = await supabase.from("class").select("id, name").order("name");

  return (
    <div className="space-y-4">
      <h2 className="text-lg font-semibold">{t("createScenario")}</h2>
      <SimulatorScenarioForm classes={(classes ?? []).map((c) => ({ id: c.id, name: c.name }))} />
    </div>
  );
}
