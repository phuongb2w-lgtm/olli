import Link from "next/link";
import { notFound } from "next/navigation";
import { getLocale, getTranslations } from "next-intl/server";
import { SessionOperationsPanel } from "@/components/session-execution/session-operations-panel";
import { SessionRoster } from "@/components/session-execution/session-roster";
import { SessionStatusActions } from "@/components/session-execution/session-status-actions";
import { formatDateTime } from "@/lib/formatting";
import { can } from "@/lib/permissions/can";
import { createClient } from "@/lib/supabase/server";
import {
  countAttendanceProgress,
  fetchObservationIndicators,
  fetchSessionExecutionContext,
  fetchSessionRoster,
} from "@/lib/session-execution/query-session-execution";
import { listTeachingSessionChanges } from "@/lib/teaching/query-session-changes";
import type { Locale } from "@/i18n/config";

export const dynamic = "force-dynamic";

type Props = {
  params: Promise<{ id: string; sessionId: string }>;
  searchParams: Promise<Record<string, string | string[] | undefined>>;
};

export default async function SessionExecutionPage({ params, searchParams }: Props) {
  const t = await getTranslations("sessionExecution");
  const tStatus = await getTranslations("status.session");
  const locale = (await getLocale()) as Locale;
  const { id: classId, sessionId } = await params;
  const rawParams = await searchParams;

  const hasRead = (await can("attendance.read")) || (await can("enrollment.read"));
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

  const canRecordAttendance = await can("attendance.record");
  const canReadObservation = await can("observation.read");
  const canRecordObservation = await can("observation.record");
  const canManageSession = await can("enrollment.update");
  const canReadOps = await can("enrollment.read");

  const supabase = await createClient();
  const context = await fetchSessionExecutionContext(supabase, classId, sessionId);
  if (!context) notFound();

  const roster = await fetchSessionRoster(supabase, context, {
    includeObservations: canReadObservation || canRecordObservation,
  });
  const indicators =
    canReadObservation || canRecordObservation
      ? await fetchObservationIndicators(supabase)
      : [];
  const progress = countAttendanceProgress(roster);
  const changes = canReadOps
    ? await listTeachingSessionChanges(supabase, sessionId)
    : [];

  const [{ data: teachers }, { data: rooms }] = await Promise.all([
    supabase
      .from("teacher")
      .select("id, given_name, family_name")
      .eq("status", "active")
      .order("family_name"),
    supabase.from("room").select("id, name, code").eq("status", "active").order("name"),
  ]);

  const success = rawParams.success;
  const successKey = typeof success === "string" ? success : undefined;
  const locationLabel =
    context.roomName ??
    context.locationFallback ??
    t("noLocation");

  const tOps = await getTranslations("sessionOperations");
  const opsSuccess =
    successKey &&
    ["rescheduled", "cancelled", "teacher_substituted", "room_changed"].includes(successKey)
      ? tOps(`success.${successKey}`)
      : null;

  return (
    <div className="space-y-8">
      <header className="space-y-3">
        <Link
          href={`/classes/${classId}/teaching`}
          className="text-sm text-slate-600 underline"
        >
          {t("backToTeaching")}
        </Link>
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div>
            <h1 className="text-xl font-semibold text-slate-900">{t("title")}</h1>
            <p className="text-sm text-slate-600">
              {context.className}
              {context.courseCode ? ` · ${context.courseCode}` : ""}
            </p>
          </div>
          <span className="inline-flex rounded-full bg-slate-100 px-3 py-1 text-sm font-medium text-slate-800">
            {tStatus(context.status)}
          </span>
        </div>

        <dl className="grid gap-2 text-sm sm:grid-cols-2 lg:grid-cols-3">
          <div>
            <dt className="text-slate-500">{t("date")}</dt>
            <dd className="font-medium text-slate-900">{context.occurrenceDate}</dd>
          </div>
          <div>
            <dt className="text-slate-500">{t("time")}</dt>
            <dd className="font-medium text-slate-900">
              {formatDateTime(context.scheduledStartAt, locale)} –{" "}
              {formatDateTime(context.scheduledEndAt, locale)}
            </dd>
          </div>
          <div>
            <dt className="text-slate-500">{t("teacher")}</dt>
            <dd className="font-medium text-slate-900">{context.teacherName}</dd>
          </div>
          <div>
            <dt className="text-slate-500">{t("room")}</dt>
            <dd className="font-medium text-slate-900">{locationLabel}</dd>
          </div>
          <div>
            <dt className="text-slate-500">{t("attendanceProgress")}</dt>
            <dd className="font-medium text-slate-900">
              {t("attendanceProgressSummary", {
                recorded: progress.recorded,
                total: progress.total,
              })}
              {progress.notRecorded > 0
                ? ` · ${t("learnersNotRecorded", { count: progress.notRecorded })}`
                : null}
            </dd>
          </div>
        </dl>

        {successKey ? (
          <p className="rounded-md bg-green-50 px-3 py-2 text-sm text-green-800" role="status">
            {opsSuccess ?? t(`success.${successKey}`)}
          </p>
        ) : null}
      </header>

      {canManageSession ? (
        <section>
          <SessionStatusActions
            classId={classId}
            sessionId={sessionId}
            status={context.status}
            notRecordedCount={progress.notRecorded}
          />
        </section>
      ) : null}

      {canReadOps ? (
        <SessionOperationsPanel
          classId={classId}
          sessionId={sessionId}
          status={context.status}
          scheduledStartAt={context.scheduledStartAt}
          scheduledEndAt={context.scheduledEndAt}
          teacherId={context.teacherId}
          roomId={context.roomId}
          teachers={(teachers ?? []).map((row) => ({
            id: row.id,
            label: `${row.given_name} ${row.family_name}`.trim(),
          }))}
          rooms={(rooms ?? []).map((row) => ({
            id: row.id,
            label: row.code ? `${row.name} (${row.code})` : row.name,
          }))}
          changes={changes}
          canMutate={canManageSession}
        />
      ) : null}

      <section className="space-y-4">
        <h2 className="text-lg font-semibold text-slate-900">{t("learnerRoster")}</h2>
        <SessionRoster
          classId={classId}
          sessionId={sessionId}
          sessionStatus={context.status}
          roster={roster}
          indicators={indicators}
          canRecordAttendance={canRecordAttendance}
          canReadObservation={canReadObservation}
          canRecordObservation={canRecordObservation}
        />
      </section>
    </div>
  );
}
