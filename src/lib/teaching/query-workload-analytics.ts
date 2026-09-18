import type { SupabaseClient } from "@supabase/supabase-js";

export type TeacherWorkloadRow = {
  teacherId: string;
  teacherDisplayName: string | null;
  materializedSessionCount: number;
  materializedScheduledMinutes: number;
  projectedSessionCount: number;
  projectedMinutes: number;
  completedSessionCount: number;
  deliveredScheduledMinutes: number;
  actualDeliveredMinutes: number;
  inProgressSessionCount: number;
  cancelledSessionCount: number;
  distinctClassCount: number;
};

export type RoomUsageRow = {
  roomId: string;
  roomName: string;
  roomCode: string | null;
  materializedSessionCount: number;
  materializedBookedMinutes: number;
  projectedSessionCount: number;
  projectedBookedMinutes: number;
  completedSessionCount: number;
  deliveredScheduledMinutes: number;
  actualDeliveredMinutes: number;
  cancelledSessionCount: number;
  distinctClassCount: number;
};

export type OperationalPlanningGaps = {
  unresolvedProjectedSessionCount: number;
  unresolvedProjectedMinutes: number;
  roomlessProjectedSessionCount: number;
  roomlessProjectedMinutes: number;
};

export type WorkloadAnalyticsFilters = {
  dateFrom: string;
  dateTo: string;
  classId?: string | null;
  teacherId?: string | null;
  roomId?: string | null;
};

function mapTeacherRow(row: Record<string, unknown>): TeacherWorkloadRow {
  return {
    teacherId: String(row.teacher_id),
    teacherDisplayName: (row.teacher_display_name as string | null) ?? null,
    materializedSessionCount: Number(row.materialized_session_count ?? 0),
    materializedScheduledMinutes: Number(row.materialized_scheduled_minutes ?? 0),
    projectedSessionCount: Number(row.projected_session_count ?? 0),
    projectedMinutes: Number(row.projected_minutes ?? 0),
    completedSessionCount: Number(row.completed_session_count ?? 0),
    deliveredScheduledMinutes: Number(row.delivered_scheduled_minutes ?? 0),
    actualDeliveredMinutes: Number(row.actual_delivered_minutes ?? 0),
    inProgressSessionCount: Number(row.in_progress_session_count ?? 0),
    cancelledSessionCount: Number(row.cancelled_session_count ?? 0),
    distinctClassCount: Number(row.distinct_class_count ?? 0),
  };
}

function mapRoomRow(row: Record<string, unknown>): RoomUsageRow {
  return {
    roomId: String(row.room_id),
    roomName: String(row.room_name ?? ""),
    roomCode: (row.room_code as string | null) ?? null,
    materializedSessionCount: Number(row.materialized_session_count ?? 0),
    materializedBookedMinutes: Number(row.materialized_booked_minutes ?? 0),
    projectedSessionCount: Number(row.projected_session_count ?? 0),
    projectedBookedMinutes: Number(row.projected_booked_minutes ?? 0),
    completedSessionCount: Number(row.completed_session_count ?? 0),
    deliveredScheduledMinutes: Number(row.delivered_scheduled_minutes ?? 0),
    actualDeliveredMinutes: Number(row.actual_delivered_minutes ?? 0),
    cancelledSessionCount: Number(row.cancelled_session_count ?? 0),
    distinctClassCount: Number(row.distinct_class_count ?? 0),
  };
}

function mapAnalyticsError(msg: string): string {
  if (msg.includes("analytics_range_too_large")) return "range_too_large";
  if (msg.includes("invalid_analytics_range")) return "invalid_range";
  if (msg.includes("permission_denied")) return "permission_denied";
  if (msg.includes("invalid_class")) return "invalid_class";
  if (msg.includes("invalid_teacher")) return "invalid_teacher";
  if (msg.includes("invalid_room")) return "invalid_room";
  return "load_error";
}

export function formatMinutesAsHours(minutes: number): string {
  const h = Math.floor(minutes / 60);
  const m = minutes % 60;
  if (h === 0) return `${m}m`;
  if (m === 0) return `${h}h`;
  return `${h}h ${m}m`;
}

export async function fetchTeacherWorkload(
  supabase: SupabaseClient,
  filters: WorkloadAnalyticsFilters,
): Promise<{ rows: TeacherWorkloadRow[]; error: string | null }> {
  const { data, error } = await supabase.rpc("list_teacher_workload", {
    p_date_from: filters.dateFrom,
    p_date_to: filters.dateTo,
    p_class_id: filters.classId || undefined,
    p_teacher_id: filters.teacherId || undefined,
    p_room_id: filters.roomId || undefined,
  });

  if (error) {
    return { rows: [], error: mapAnalyticsError(error.message ?? "") };
  }

  const rows = (data ?? []) as Record<string, unknown>[];
  return { rows: rows.map(mapTeacherRow), error: null };
}

export async function fetchRoomUsage(
  supabase: SupabaseClient,
  filters: WorkloadAnalyticsFilters,
): Promise<{ rows: RoomUsageRow[]; error: string | null }> {
  const { data, error } = await supabase.rpc("list_room_usage", {
    p_date_from: filters.dateFrom,
    p_date_to: filters.dateTo,
    p_class_id: filters.classId || undefined,
    p_room_id: filters.roomId || undefined,
  });

  if (error) {
    return { rows: [], error: mapAnalyticsError(error.message ?? "") };
  }

  const rows = (data ?? []) as Record<string, unknown>[];
  return { rows: rows.map(mapRoomRow), error: null };
}

export async function fetchOperationalPlanningGaps(
  supabase: SupabaseClient,
  dateFrom: string,
  dateTo: string,
  classId?: string | null,
): Promise<{ gaps: OperationalPlanningGaps | null; error: string | null }> {
  const { data, error } = await supabase.rpc("get_operational_planning_gaps", {
    p_date_from: dateFrom,
    p_date_to: dateTo,
    p_class_id: classId || undefined,
  });

  if (error) {
    return { gaps: null, error: mapAnalyticsError(error.message ?? "") };
  }

  const row = (Array.isArray(data) ? data[0] : data) as Record<string, unknown> | null;
  if (!row) {
    return {
      gaps: {
        unresolvedProjectedSessionCount: 0,
        unresolvedProjectedMinutes: 0,
        roomlessProjectedSessionCount: 0,
        roomlessProjectedMinutes: 0,
      },
      error: null,
    };
  }

  return {
    gaps: {
      unresolvedProjectedSessionCount: Number(row.unresolved_projected_session_count ?? 0),
      unresolvedProjectedMinutes: Number(row.unresolved_projected_minutes ?? 0),
      roomlessProjectedSessionCount: Number(row.roomless_projected_session_count ?? 0),
      roomlessProjectedMinutes: Number(row.roomless_projected_minutes ?? 0),
    },
    error: null,
  };
}

export function currentMonthRange(): { from: string; to: string } {
  const now = new Date();
  const from = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1));
  const to = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() + 1, 0));
  return {
    from: from.toISOString().slice(0, 10),
    to: to.toISOString().slice(0, 10),
  };
}
