import type { SupabaseClient } from "@supabase/supabase-js";
import { OPERATIONAL_ENROLLMENT_STATUSES } from "@/lib/enrollments/constants";

export async function countOperationalEnrollments(
  supabase: SupabaseClient,
  classId: string,
  excludeEnrollmentId?: string,
): Promise<number> {
  let query = supabase
    .from("enrollment")
    .select("id", { count: "exact", head: true })
    .eq("class_id", classId)
    .in("status", [...OPERATIONAL_ENROLLMENT_STATUSES]);

  if (excludeEnrollmentId) {
    query = query.neq("id", excludeEnrollmentId);
  }

  const { count, error } = await query;
  if (error) throw error;
  return count ?? 0;
}

export function isCapacityExceeded(
  capacity: number | null | undefined,
  operationalCount: number,
): boolean {
  if (capacity == null || capacity <= 0) return false;
  return operationalCount >= capacity;
}
