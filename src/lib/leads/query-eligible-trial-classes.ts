import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "@/types/database";

type DbClient = SupabaseClient<Database>;

export type EligibleTrialClass = {
  classId: string;
  className: string;
  classStatus: string;
};

export type TrialTeachingSession = {
  sessionId: string;
  scheduledStartAt: string;
  scheduledEndAt: string;
  status: string;
};

export async function queryEligibleTrialClasses(
  supabase: DbClient,
): Promise<{ classes: EligibleTrialClass[]; error: boolean }> {
  const { data, error } = await supabase.rpc("list_eligible_trial_classes");

  if (error) {
    return { classes: [], error: true };
  }

  return {
    classes: (data ?? []).map((row) => ({
      classId: row.class_id,
      className: row.class_name,
      classStatus: row.class_status,
    })),
    error: false,
  };
}

export async function queryTrialTeachingSessions(
  supabase: DbClient,
  classId: string,
): Promise<{ sessions: TrialTeachingSession[]; error: boolean }> {
  const { data, error } = await supabase.rpc("list_trial_teaching_sessions", {
    p_class_id: classId,
  });

  if (error) {
    return { sessions: [], error: true };
  }

  return {
    sessions: (data ?? []).map((row) => ({
      sessionId: row.session_id,
      scheduledStartAt: row.scheduled_start_at,
      scheduledEndAt: row.scheduled_end_at,
      status: row.status,
    })),
    error: false,
  };
}
