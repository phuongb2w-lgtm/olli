"use client";

import Link from "next/link";
import { useState } from "react";
import { useTranslations } from "next-intl";
import { DailySessionOps } from "@/components/operations/daily-session-ops";
import type { DailyOperationsEntry } from "@/lib/teaching/query-daily-operations";

type Option = { id: string; label: string };

type Props = {
  entries: DailyOperationsEntry[];
  timezone: string;
  isToday: boolean;
  dailyDate: string;
  teachers: Option[];
  rooms: Option[];
  canMutate: boolean;
};

function formatLocalTime(iso: string, timeZone: string) {
  return new Intl.DateTimeFormat("en-GB", {
    timeZone,
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
  }).format(new Date(iso));
}

function entryBadgeKey(entry: DailyOperationsEntry): string {
  if (entry.entryType === "projected") return "planned";
  switch (entry.sessionStatus) {
    case "cancelled":
      return "cancelled";
    case "completed":
      return "completed";
    case "in_progress":
      return "inProgress";
    default:
      return "session";
  }
}

function badgeClass(key: string): string {
  switch (key) {
    case "cancelled":
      return "bg-slate-200 text-slate-700";
    case "completed":
      return "bg-emerald-50 text-emerald-800";
    case "inProgress":
      return "bg-sky-50 text-sky-800";
    case "planned":
      return "bg-amber-50 text-amber-900";
    default:
      return "bg-slate-100 text-slate-800";
  }
}

function groupKey(entry: DailyOperationsEntry): string | null {
  if (entry.entryType !== "session") return null;
  switch (entry.sessionStatus) {
    case "completed":
      return "completed";
    case "in_progress":
      return "inProgress";
    case "scheduled":
      return "upcoming";
    case "cancelled":
      return "cancelled";
    default:
      return "upcoming";
  }
}

function OccurrenceRow({
  entry,
  timezone,
  dailyDate,
  teachers,
  rooms,
  canMutate,
}: {
  entry: DailyOperationsEntry;
  timezone: string;
  dailyDate: string;
  teachers: Option[];
  rooms: Option[];
  canMutate: boolean;
}) {
  const t = useTranslations("operationsDaily");
  const tOps = useTranslations("operations");
  const [expanded, setExpanded] = useState(false);

  const badge = entryBadgeKey(entry);
  const timeLabel = `${formatLocalTime(entry.startsAt, timezone)}–${formatLocalTime(entry.endsAt, timezone)}`;
  const teacherLabel =
    entry.teacherDisplayName ??
    (entry.teacherResolutionStatus === "multiple_primary_teachers"
      ? tOps("teacherAmbiguous")
      : entry.teacherResolutionStatus === "teacher_not_resolved"
        ? tOps("teacherUnresolved")
        : tOps("emptyValue"));
  const roomLabel = entry.roomName ?? entry.roomCode ?? tOps("noRoom");
  const key =
    entry.teachingSessionId ??
    `${entry.classScheduleId}-${entry.occurrenceDate}-${entry.startsAt}`;

  const hasWarning =
    entry.entryType === "projected"
      ? entry.teacherResolutionStatus !== "resolved" || !entry.roomId
      : (entry.sessionStatus === "scheduled" || entry.sessionStatus === "in_progress") &&
        (!entry.teacherId || !entry.roomId);

  const mutableSession =
    entry.entryType === "session" &&
    entry.teachingSessionId &&
    entry.sessionStatus === "scheduled";

  return (
    <li
      key={key}
      data-entry-type={entry.entryType}
      data-session-status={entry.sessionStatus ?? ""}
      className={`px-4 py-3 ${entry.sessionStatus === "cancelled" ? "opacity-70" : ""}`}
    >
      <div className="flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between">
        <div className="min-w-0 space-y-0.5">
          <p className="text-sm font-medium text-slate-900">
            <span className="tabular-nums">{timeLabel}</span>
            <span className="mx-2 text-slate-300">·</span>
            {entry.entryType === "session" && entry.teachingSessionId ? (
              <Link
                href={`/classes/${entry.classId}/teaching/sessions/${entry.teachingSessionId}`}
                className="underline decoration-slate-300 underline-offset-2 hover:decoration-slate-700"
              >
                {entry.className}
              </Link>
            ) : (
              <Link
                href={`/classes/${entry.classId}/teaching`}
                className="underline decoration-slate-300 underline-offset-2 hover:decoration-slate-700"
              >
                {entry.className}
              </Link>
            )}
            {hasWarning ? (
              <span
                className="ml-2 inline-flex rounded bg-amber-100 px-1.5 py-0.5 text-xs font-medium text-amber-900"
                data-testid="occurrence-warning"
              >
                {t("needsAttention")}
              </span>
            ) : null}
          </p>
          <p className="text-sm text-slate-600">
            {teacherLabel}
            <span className="mx-2 text-slate-300">·</span>
            {roomLabel}
          </p>
        </div>
        <div className="flex shrink-0 items-center gap-2">
          <span
            className={`inline-flex rounded px-2 py-0.5 text-xs font-medium ${badgeClass(badge)}`}
          >
            {t(`occurrenceType.${badge}`)}
          </span>
          {mutableSession && canMutate ? (
            <button
              type="button"
              onClick={() => setExpanded((v) => !v)}
              className="rounded border border-slate-300 px-2 py-0.5 text-xs font-medium text-slate-800"
              data-testid="session-ops-toggle"
            >
              {expanded ? t("hideActions") : t("manageSession")}
            </button>
          ) : null}
        </div>
      </div>
      {expanded && mutableSession && entry.teachingSessionId ? (
        <DailySessionOps
          classId={entry.classId}
          sessionId={entry.teachingSessionId}
          scheduledStartAt={entry.startsAt}
          scheduledEndAt={entry.endsAt}
          teacherId={entry.teacherId ?? ""}
          roomId={entry.roomId}
          dailyDate={dailyDate}
          teachers={teachers}
          rooms={rooms}
          canMutate={canMutate}
        />
      ) : null}
    </li>
  );
}

export function DailyOccurrenceList({
  entries,
  timezone,
  isToday,
  dailyDate,
  teachers,
  rooms,
  canMutate,
}: Props) {
  const t = useTranslations("operationsDaily");

  if (entries.length === 0) {
    return (
      <p className="text-sm text-slate-600" data-testid="daily-empty">
        {t("emptyDay")}
      </p>
    );
  }

  if (!isToday) {
    return (
      <ul
        className="divide-y divide-slate-200 rounded-lg border border-slate-200 bg-white"
        data-testid="daily-occurrence-list"
      >
        {entries.map((entry) => (
          <OccurrenceRow
            key={
              entry.teachingSessionId ??
              `${entry.classScheduleId}-${entry.occurrenceDate}-${entry.startsAt}`
            }
            entry={entry}
            timezone={timezone}
            dailyDate={dailyDate}
            teachers={teachers}
            rooms={rooms}
            canMutate={canMutate}
          />
        ))}
      </ul>
    );
  }

  const groups: { key: string; labelKey: string; items: DailyOperationsEntry[] }[] = [
    { key: "inProgress", labelKey: "groupInProgress", items: [] },
    { key: "upcoming", labelKey: "groupUpcoming", items: [] },
    { key: "completed", labelKey: "groupCompleted", items: [] },
    { key: "cancelled", labelKey: "groupCancelled", items: [] },
    { key: "planned", labelKey: "groupPlanned", items: [] },
  ];

  for (const entry of entries) {
    if (entry.entryType === "projected") {
      groups.find((g) => g.key === "planned")!.items.push(entry);
      continue;
    }
    const gk = groupKey(entry);
    const bucket = groups.find((g) => g.key === gk) ?? groups.find((g) => g.key === "upcoming")!;
    bucket.items.push(entry);
  }

  return (
    <div className="space-y-4" data-testid="daily-occurrence-list">
      {groups.map((group) =>
        group.items.length === 0 ? null : (
          <section key={group.key}>
            <h2 className="mb-2 text-sm font-semibold text-slate-700">{t(group.labelKey)}</h2>
            <ul className="divide-y divide-slate-200 rounded-lg border border-slate-200 bg-white">
              {group.items.map((entry) => (
                <OccurrenceRow
                  key={
                    entry.teachingSessionId ??
                    `${entry.classScheduleId}-${entry.occurrenceDate}-${entry.startsAt}`
                  }
                  entry={entry}
                  timezone={timezone}
                  dailyDate={dailyDate}
                  teachers={teachers}
                  rooms={rooms}
                  canMutate={canMutate}
                />
              ))}
            </ul>
          </section>
        ),
      )}
    </div>
  );
}
