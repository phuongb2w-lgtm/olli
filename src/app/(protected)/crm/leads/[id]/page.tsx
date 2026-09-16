import Link from "next/link";
import { getTranslations } from "next-intl/server";
import { LeadDetailView } from "@/components/leads/lead-detail-view";
import { can } from "@/lib/permissions/can";
import { queryEligibleAssignees } from "@/lib/leads/query-eligible-assignees";
import {
  queryEligibleTrialClasses,
  queryTrialTeachingSessions,
} from "@/lib/leads/query-eligible-trial-classes";
import { queryLeadDetail } from "@/lib/leads/query-lead-detail";
import type { TrialTeachingSession } from "@/lib/leads/query-eligible-trial-classes";
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
  const [{ detail, error, notFound }, { assignees }, { classes: eligibleClasses }] =
    await Promise.all([
      queryLeadDetail(supabase, id),
      hasAssign ? queryEligibleAssignees(supabase) : Promise.resolve({ assignees: [], error: false }),
      hasRead ? queryEligibleTrialClasses(supabase) : Promise.resolve({ classes: [], error: false }),
    ]);

  const sessionsByClass: Record<string, TrialTeachingSession[]> = {};
  if (hasRead && eligibleClasses.length > 0) {
    const sessionResults = await Promise.all(
      eligibleClasses.map(async (c) => {
        const { sessions } = await queryTrialTeachingSessions(supabase, c.classId);
        return [c.classId, sessions] as const;
      }),
    );
    for (const [classId, sessions] of sessionResults) {
      sessionsByClass[classId] = sessions;
    }
  }

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
        eligibleClasses={eligibleClasses}
        sessionsByClass={sessionsByClass}
      />
    </div>
  );
}
