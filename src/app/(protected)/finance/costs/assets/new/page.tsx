import { getTranslations } from "next-intl/server";
import { CapitalAssetForm } from "@/components/finance/capital-asset-form";
import { can } from "@/lib/permissions/can";

export const dynamic = "force-dynamic";

type Props = { searchParams: Promise<Record<string, string | string[] | undefined>> };

export default async function NewCapitalAssetPage({ searchParams }: Props) {
  const t = await getTranslations("finance.assets");
  const raw = await searchParams;
  const mode = raw.mode === "detailed" ? "detailed" : "quick";

  if (!(await can("asset.create"))) {
    return (
      <section className="rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-600">
        <p>{t("denied")}</p>
      </section>
    );
  }

  return (
    <div className="space-y-4">
      <h2 className="text-lg font-semibold">{mode === "quick" ? t("quickCreate") : t("detailedCreate")}</h2>
      <CapitalAssetForm mode={mode} />
    </div>
  );
}
