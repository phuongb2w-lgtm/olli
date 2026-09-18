import type { SupabaseClient } from "@supabase/supabase-js";

export type SessionChangeType =
  | "rescheduled"
  | "cancelled"
  | "teacher_substituted"
  | "room_changed";

export type TeachingSessionChange = {
  id: string;
  changeType: SessionChangeType;
  reason: string | null;
  actorId: string;
  occurredAt: string;
  previousScheduledStartAt: string | null;
  previousScheduledEndAt: string | null;
  newScheduledStartAt: string | null;
  newScheduledEndAt: string | null;
  previousTeacherId: string | null;
  newTeacherId: string | null;
  previousRoomId: string | null;
  newRoomId: string | null;
  previousStatus: string | null;
  newStatus: string | null;
};

export async function listTeachingSessionChanges(
  supabase: SupabaseClient,
  sessionId: string,
): Promise<TeachingSessionChange[]> {
  const { data, error } = await supabase.rpc("list_teaching_session_changes", {
    p_session_id: sessionId,
  });
  if (error || !data) return [];

  return (data as Record<string, unknown>[]).map((row) => ({
    id: String(row.id),
    changeType: row.change_type as SessionChangeType,
    reason: (row.reason as string | null) ?? null,
    actorId: String(row.actor_id),
    occurredAt: String(row.occurred_at),
    previousScheduledStartAt: (row.previous_scheduled_start_at as string | null) ?? null,
    previousScheduledEndAt: (row.previous_scheduled_end_at as string | null) ?? null,
    newScheduledStartAt: (row.new_scheduled_start_at as string | null) ?? null,
    newScheduledEndAt: (row.new_scheduled_end_at as string | null) ?? null,
    previousTeacherId: (row.previous_teacher_id as string | null) ?? null,
    newTeacherId: (row.new_teacher_id as string | null) ?? null,
    previousRoomId: (row.previous_room_id as string | null) ?? null,
    newRoomId: (row.new_room_id as string | null) ?? null,
    previousStatus: (row.previous_status as string | null) ?? null,
    newStatus: (row.new_status as string | null) ?? null,
  }));
}
