import type { SupabaseClient } from "@supabase/supabase-js";
import type { OperationalCalendarEntry } from "@/lib/teaching/query-operational-calendar";
import { mapOperationalCalendarEntry } from "@/lib/teaching/query-operational-calendar";

export type DailyOperationsEntry = OperationalCalendarEntry;

export type DailyOperationsFilters = {
  date: string;
  classId?: string | null;
  teacherId?: string | null;
  roomId?: string | null;
};

export type DailySummary = {
  materializedCount: number;
  inProgressCount: number;
  upcomingScheduledCount: number;
  completedCount: number;
  cancelledCount: number;
  projectedCount: number;
  unresolvedProjectedCount: number;
  roomlessProjectedCount: number;
  scheduledMinutes: number;
  deliveredScheduledMinutes: number;
};

export type DailyAttentionItem = {
  id: string;
  kind:
    | "unresolved_teacher"
    | "roomless_projection"
    | "session_no_teacher"
    | "session_no_room";
  labelKey: string;
  className: string;
  startsAt: string;
};

function minutesBetween(startIso: string, endIso: string): number {
  const ms = new Date(endIso).getTime() - new Date(startIso).getTime();
  if (Number.isNaN(ms) || ms <= 0) return 0;
  return Math.round(ms / 60000);
}

export function todayInTimezone(timezone: string): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: timezone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(new Date());
}

export function deriveDailySummary(
  entries: DailyOperationsEntry[],
  gaps: {
    unresolvedProjectedSessionCount: number;
    roomlessProjectedSessionCount: number;
  } | null,
): DailySummary {
  let materializedCount = 0;
  let inProgressCount = 0;
  let upcomingScheduledCount = 0;
  let completedCount = 0;
  let cancelledCount = 0;
  let projectedCount = 0;
  let scheduledMinutes = 0;
  let deliveredScheduledMinutes = 0;

  for (const e of entries) {
    if (e.entryType === "projected") {
      projectedCount += 1;
      continue;
    }
    materializedCount += 1;
    const mins = minutesBetween(e.startsAt, e.endsAt);
    if (e.sessionStatus === "cancelled") {
      cancelledCount += 1;
    } else {
      scheduledMinutes += mins;
      if (e.sessionStatus === "completed") {
        completedCount += 1;
        deliveredScheduledMinutes += mins;
      } else if (e.sessionStatus === "in_progress") {
        inProgressCount += 1;
      } else if (e.sessionStatus === "scheduled") {
        upcomingScheduledCount += 1;
      }
    }
  }

  return {
    materializedCount,
    inProgressCount,
    upcomingScheduledCount,
    completedCount,
    cancelledCount,
    projectedCount,
    unresolvedProjectedCount: gaps?.unresolvedProjectedSessionCount ?? 0,
    roomlessProjectedCount: gaps?.roomlessProjectedSessionCount ?? 0,
    scheduledMinutes,
    deliveredScheduledMinutes,
  };
}

export function deriveAttentionItems(entries: DailyOperationsEntry[]): DailyAttentionItem[] {
  const items: DailyAttentionItem[] = [];
  for (const e of entries) {
    const key =
      e.teachingSessionId ??
      `${e.classScheduleId}-${e.occurrenceDate}-${e.startsAt}`;
    if (e.entryType === "projected") {
      if (
        e.teacherResolutionStatus !== "resolved" ||
        e.teacherId === null
      ) {
        items.push({
          id: key,
          kind: "unresolved_teacher",
          labelKey: "attentionUnresolvedTeacher",
          className: e.className,
          startsAt: e.startsAt,
        });
      }
      if (!e.roomId) {
        items.push({
          id: `${key}-room`,
          kind: "roomless_projection",
          labelKey: "attentionRoomlessProjection",
          className: e.className,
          startsAt: e.startsAt,
        });
      }
    } else if (e.sessionStatus === "scheduled" || e.sessionStatus === "in_progress") {
      if (!e.teacherId) {
        items.push({
          id: key,
          kind: "session_no_teacher",
          labelKey: "attentionSessionNoTeacher",
          className: e.className,
          startsAt: e.startsAt,
        });
      }
      if (!e.roomId) {
        items.push({
          id: `${key}-room`,
          kind: "session_no_room",
          labelKey: "attentionSessionNoRoom",
          className: e.className,
          startsAt: e.startsAt,
        });
      }
    }
  }
  return items;
}

function mapDailyError(msg: string): string {
  if (msg.includes("invalid_daily_date")) return "invalid_date";
  if (msg.includes("invalid_calendar_range")) return "invalid_date";
  if (msg.includes("permission_denied")) return "permission_denied";
  if (msg.includes("invalid_class")) return "invalid_class";
  if (msg.includes("invalid_teacher")) return "invalid_teacher";
  if (msg.includes("invalid_room")) return "invalid_room";
  return "load_error";
}

export async function fetchDailyOperations(
  supabase: SupabaseClient,
  filters: DailyOperationsFilters,
): Promise<{ entries: DailyOperationsEntry[]; error: string | null }> {
  const { data, error } = await supabase.rpc("list_daily_operations", {
    p_date: filters.date,
    p_class_id: filters.classId || undefined,
    p_teacher_id: filters.teacherId || undefined,
    p_room_id: filters.roomId || undefined,
  });

  if (error) {
    return { entries: [], error: mapDailyError(error.message ?? "") };
  }

  const rows = (data ?? []) as Record<string, unknown>[];
  return {
    entries: rows.map((row) => mapOperationalCalendarEntry(row)),
    error: null,
  };
}
