import { getTranslations } from "next-intl/server";
import { ConsultantPortfolioDetailLoader } from "@/components/consultant-workspace/consultant-portfolio-detail-loader";
import { can } from "@/lib/permissions/can";

export const dynamic = "force-dynamic";

type Props = {
  params: Promise<{ portfolioEntryId: string }>;
  searchParams: Promise<{ edit?: string }>;
};

export default async function ConsultantPortfolioDetailPage({ params, searchParams }: Props) {
  const t = await getTranslations("consultantWorkspace");
  const { portfolioEntryId } = await params;
  const sp = await searchParams;
  const startInEditMode = sp.edit === "1";

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

  return (
    <div className="mx-auto max-w-3xl">
      <ConsultantPortfolioDetailLoader
        portfolioEntryId={portfolioEntryId}
        startInEditMode={startInEditMode}
      />
    </div>
  );
}
