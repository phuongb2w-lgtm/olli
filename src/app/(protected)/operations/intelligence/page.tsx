import Link from "next/link";
import { getTranslations } from "next-intl/server";
import { OperationsSubnav } from "@/components/operations/operations-subnav";
import { TeachingOpsChangesPanel } from "@/components/operations/teaching-ops-changes-panel";
import { TeachingOpsExceptionsPanel } from "@/components/operations/teaching-ops-exceptions-panel";
import { ReportingPeriodFilterForm } from "@/components/finance/reporting-period-filter-form";
import { can } from "@/lib/permissions/can";
import { parseReportingSearchParams } from "@/lib/reporting/parse-reporting-search-params";
import {
  fetchTeachingOpsChangeMetrics,
  fetchTeachingOpsExceptions,
  fetchTeachingOpsOperationalChanges,
  fetchTeachingOpsSessionMetrics,
} from "@/lib/reporting/teaching-ops-read-model";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

type Props = {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
};

export default async function OperationsIntelligencePage({ searchParams }: Props) {
  const t = await getTranslations("teachingOps.workspace");
  const rawParams = await searchParams;
  const { period } = parseReportingSearchParams(rawParams);
  const hasRead = await can("enrollment.read");

  if (!hasRead) {
    return (
      <div className="space-y-4">
        <h1 className="text-xl font-semibold">{t("title")}</h1>
        <OperationsSubnav />
        <section className="rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-600">
          <p>{t("denied")}</p>
        </section>
      </div>
    );
  }

  const supabase = await createClient();
  const [sessionRes, changeRes, { exceptions, error: exError }, { changes, error: chError }] =
    await Promise.all([
      fetchTeachingOpsSessionMetrics(supabase, period),
      fetchTeachingOpsChangeMetrics(supabase, period),
      fetchTeachingOpsExceptions(supabase, period),
      fetchTeachingOpsOperationalChanges(supabase, period),
    ]);

  const loadError =
    sessionRes.error ?? changeRes.error ?? exError ?? chError
      ? t("loadError")
      : null;

  const changeTypeLabels: Record<string, string> = {
    rescheduled: t("changeTypes.rescheduled"),
    cancelled: t("changeTypes.cancelled"),
    teacher_substituted: t("changeTypes.teacherSubstituted"),
    room_changed: t("changeTypes.roomChanged"),
  };

  return (
    <div className="space-y-6">
      <header>
        <h1 className="text-xl font-semibold text-slate-900">{t("title")}</h1>
        <p className="text-sm text-slate-600">{t("subtitle")}</p>
      </header>

      <OperationsSubnav />

      <ReportingPeriodFilterForm
        action="/operations/intelligence"
        startDate={period.startDate}
        endDate={period.endDate}
        comparePrevious={false}
      />

      {loadError ? (
        <section className="rounded-lg border border-red-200 bg-red-50 p-4 text-sm text-red-800">
          <p>{loadError}</p>
        </section>
      ) : null}

      {sessionRes.data ? (
        <section className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          <article className="rounded-lg border border-slate-200 bg-white p-4">
            <p className="text-xs text-slate-600">{t("projectedOccurrences")}</p>
            <p className="text-2xl font-semibold">{sessionRes.data.projected_occurrences}</p>
          </article>
          <article className="rounded-lg border border-slate-200 bg-white p-4">
            <p className="text-xs text-slate-600">{t("materializedSessions")}</p>
            <p className="text-2xl font-semibold">{sessionRes.data.materialized_sessions}</p>
          </article>
          <article className="rounded-lg border border-slate-200 bg-white p-4">
            <p className="text-xs text-slate-600">{t("deliveredSessions")}</p>
            <p className="text-2xl font-semibold">{sessionRes.data.delivered_sessions}</p>
          </article>
          <article className="rounded-lg border border-slate-200 bg-white p-4">
            <p className="text-xs text-slate-600">{t("cancelledSessions")}</p>
            <p className="text-2xl font-semibold">{sessionRes.data.cancelled_sessions}</p>
          </article>
        </section>
      ) : null}

      {changeRes.data ? (
        <section className="rounded-lg border border-slate-200 bg-white p-4 text-sm">
          <h2 className="font-semibold text-slate-900">{t("changesSummary")}</h2>
          <ul className="mt-2 grid gap-2 sm:grid-cols-2">
            <li>
              {t("rescheduleEvents")}: {changeRes.data.reschedule.event_count} (
              {t("affectedSessions", { count: changeRes.data.reschedule.affected_session_count })})
            </li>
            <li>
              {t("cancellationEvents")}: {changeRes.data.cancellation.event_count}
            </li>
            <li>
              {t("substitutionEvents")}: {changeRes.data.teacher_substitution.event_count}
            </li>
            <li>
              {t("roomChangeEvents")}: {changeRes.data.room_change.event_count}
            </li>
          </ul>
        </section>
      ) : null}

      <div className="flex flex-wrap gap-3 text-sm">
        <Link href="/operations/workload" className="font-medium underline">
          {t("workloadLink")}
        </Link>
        <Link href="/operations" className="font-medium underline">
          {t("dailyOpsLink")}
        </Link>
      </div>

      <TeachingOpsChangesPanel
        changes={changes}
        title={t("recentChanges")}
        emptyLabel={t("changesEmpty")}
        viewLabel={t("viewDrillDown")}
        changeTypeLabels={changeTypeLabels}
      />

      <TeachingOpsExceptionsPanel
        exceptions={exceptions}
        title={t("exceptionsTitle")}
        emptyLabel={t("exceptionsEmpty")}
        viewLabel={t("viewDrillDown")}
      />
    </div>
  );
}
