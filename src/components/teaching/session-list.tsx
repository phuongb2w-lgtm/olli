import { getLocale, getTranslations } from "next-intl/server";
import Link from "next/link";
import { formatDateTime } from "@/lib/formatting";
import type { SessionItem } from "@/lib/teaching/query-class-teaching";
import type { Locale } from "@/i18n/config";

type Props = {
  classId: string;
  sessions: SessionItem[];
  canOpenExecution: boolean;
};

function partitionSessions(sessions: SessionItem[]) {
  const now = Date.now();
  const upcoming: SessionItem[] = [];
  const historical: SessionItem[] = [];
  for (const session of sessions) {
    const start = new Date(session.scheduledStartAt).getTime();
    if (session.status === "in_progress" || (start >= now && session.status === "scheduled")) {
      upcoming.push(session);
    } else {
      historical.push(session);
    }
  }
  upcoming.sort(
    (a, b) =>
      new Date(a.scheduledStartAt).getTime() - new Date(b.scheduledStartAt).getTime(),
  );
  historical.sort(
    (a, b) =>
      new Date(b.scheduledStartAt).getTime() - new Date(a.scheduledStartAt).getTime(),
  );
  return { upcoming, historical };
}

export async function SessionList({ classId, sessions, canOpenExecution }: Props) {
  const t = await getTranslations("teaching");
  const tStatus = await getTranslations("status.session");
  const locale = (await getLocale()) as Locale;

  if (sessions.length === 0) {
    return <p className="text-sm text-slate-600">{t("noSessions")}</p>;
  }

  const { upcoming, historical } = partitionSessions(sessions);

  const renderMobileCard = (session: SessionItem) => (
    <article
      key={session.id}
      className="rounded-lg border border-slate-200 bg-white p-4 text-sm lg:hidden"
    >
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div>
          <p className="font-medium text-slate-900">
            {formatDateTime(session.scheduledStartAt, locale)}
          </p>
          <p className="text-slate-600">{formatDateTime(session.scheduledEndAt, locale)}</p>
          <p className="text-slate-600">
            {t("teacher")}: {session.teacherName}
          </p>
          {session.roomName ? (
            <p className="text-slate-600">
              {t("room")}: {session.roomName}
            </p>
          ) : null}
        </div>
        <span className="inline-flex rounded-full bg-slate-100 px-2.5 py-0.5 text-xs font-medium text-slate-800">
          {tStatus(session.status)}
        </span>
      </div>
      {canOpenExecution ? (
        <div className="mt-3">
          <Link
            href={`/classes/${classId}/teaching/sessions/${session.id}`}
            className="text-sm font-medium text-slate-900 underline"
          >
            {t("openSession")}
          </Link>
        </div>
      ) : null}
    </article>
  );

  return (
    <div className="space-y-6">
      {upcoming.length > 0 ? (
        <section className="space-y-3">
          <h3 className="text-sm font-semibold text-slate-900">{t("upcomingSessions")}</h3>
          <div className="hidden overflow-x-auto lg:block">
            <table className="min-w-full divide-y divide-slate-200 text-sm">
              <thead className="bg-slate-50">
                <tr>
                  <th className="px-4 py-3 text-left font-medium text-slate-700">{t("date")}</th>
                  <th className="px-4 py-3 text-left font-medium text-slate-700">{t("time")}</th>
                  <th className="px-4 py-3 text-left font-medium text-slate-700">{t("teacher")}</th>
                  <th className="px-4 py-3 text-left font-medium text-slate-700">{t("room")}</th>
                  <th className="px-4 py-3 text-left font-medium text-slate-700">{t("status")}</th>
                  {canOpenExecution ? (
                    <th className="px-4 py-3 text-left font-medium text-slate-700">
                      <span className="sr-only">{t("actions")}</span>
                    </th>
                  ) : null}
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-200 bg-white">
                {upcoming.map((session) => (
                  <tr key={session.id}>
                    <td className="px-4 py-3">{session.occurrenceDate ?? "—"}</td>
                    <td className="px-4 py-3">
                      {formatDateTime(session.scheduledStartAt, locale)} –{" "}
                      {formatDateTime(session.scheduledEndAt, locale)}
                    </td>
                    <td className="px-4 py-3">{session.teacherName}</td>
                    <td className="px-4 py-3">{session.roomName ?? "—"}</td>
                    <td className="px-4 py-3">
                      <span className="inline-flex rounded-full bg-slate-100 px-2.5 py-0.5 text-xs font-medium text-slate-800">
                        {tStatus(session.status)}
                      </span>
                    </td>
                    {canOpenExecution ? (
                      <td className="px-4 py-3">
                        <Link
                          href={`/classes/${classId}/teaching/sessions/${session.id}`}
                          className="text-sm font-medium text-slate-900 underline"
                        >
                          {t("openSession")}
                        </Link>
                      </td>
                    ) : null}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <div className="space-y-3">{upcoming.map(renderMobileCard)}</div>
        </section>
      ) : null}

      {historical.length > 0 ? (
        <section className="space-y-3">
          <h3 className="text-sm font-semibold text-slate-900">{t("historicalSessions")}</h3>
          <div className="hidden overflow-x-auto lg:block">
            <table className="min-w-full divide-y divide-slate-200 text-sm">
              <thead className="bg-slate-50">
                <tr>
                  <th className="px-4 py-3 text-left font-medium text-slate-700">{t("date")}</th>
                  <th className="px-4 py-3 text-left font-medium text-slate-700">{t("time")}</th>
                  <th className="px-4 py-3 text-left font-medium text-slate-700">{t("teacher")}</th>
                  <th className="px-4 py-3 text-left font-medium text-slate-700">{t("room")}</th>
                  <th className="px-4 py-3 text-left font-medium text-slate-700">{t("status")}</th>
                  {canOpenExecution ? (
                    <th className="px-4 py-3 text-left font-medium text-slate-700">
                      <span className="sr-only">{t("actions")}</span>
                    </th>
                  ) : null}
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-200 bg-white">
                {historical.map((session) => (
                  <tr key={session.id}>
                    <td className="px-4 py-3">{session.occurrenceDate ?? "—"}</td>
                    <td className="px-4 py-3">
                      {formatDateTime(session.scheduledStartAt, locale)} –{" "}
                      {formatDateTime(session.scheduledEndAt, locale)}
                    </td>
                    <td className="px-4 py-3">{session.teacherName}</td>
                    <td className="px-4 py-3">{session.roomName ?? "—"}</td>
                    <td className="px-4 py-3">
                      <span className="inline-flex rounded-full bg-slate-100 px-2.5 py-0.5 text-xs font-medium text-slate-800">
                        {tStatus(session.status)}
                      </span>
                    </td>
                    {canOpenExecution ? (
                      <td className="px-4 py-3">
                        <Link
                          href={`/classes/${classId}/teaching/sessions/${session.id}`}
                          className="text-sm font-medium text-slate-900 underline"
                        >
                          {t("openSession")}
                        </Link>
                      </td>
                    ) : null}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <div className="space-y-3">{historical.map(renderMobileCard)}</div>
        </section>
      ) : null}
    </div>
  );
}
