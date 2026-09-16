import Link from "next/link";
import { getTranslations } from "next-intl/server";
import { LeadDetailView } from "@/components/leads/lead-detail-view";
import { can } from "@/lib/permissions/can";
import { queryEligibleAssignees } from "@/lib/leads/query-eligible-assignees";
import { queryLeadDetail } from "@/lib/leads/query-lead-detail";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

type Props = {
  params: Promise<{ id: string }>;
};

export default async function LeadDetailPage({ params }: Props) {
  const t = await getTranslations("crm.detail");
  const { id } = await params;
  const hasRead = await can("lead.read");
  const hasUpdate = await can("lead.update");
  const hasAssign = await can("lead.assign");

  if (!hasRead) {
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
  const [{ detail, error, notFound }, { assignees }] = await Promise.all([
    queryLeadDetail(supabase, id),
    hasAssign ? queryEligibleAssignees(supabase) : Promise.resolve({ assignees: [], error: false }),
  ]);

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

  if (notFound || !detail) {
    return (
      <div className="space-y-4">
        <h1 className="text-xl font-semibold">{t("title")}</h1>
        <section className="rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-600">
          <p>{t("notFound")}</p>
        </section>
      </div>
    );
  }

  return (
    <div className="space-y-4">
      <Link href="/crm/leads" className="text-sm text-slate-600 hover:text-slate-900">
        {t("backToList")}
      </Link>
      <LeadDetailView
        detail={detail}
        canUpdate={hasUpdate}
        canAssign={hasAssign}
        assignees={assignees}
      />
    </div>
  );
}
