import type { RosterListParams } from "@/lib/enrollments/parse-roster-params";

export function buildRosterUrl(
  classId: string,
  params: Partial<RosterListParams>,
): string {
  const search = new URLSearchParams();

  if (params.q?.trim()) search.set("q", params.q.trim());
  if (params.status && params.status !== "operational") search.set("status", params.status);
  if (params.page && params.page > 1) search.set("page", String(params.page));
  if (params.pageSize && params.pageSize !== 25) search.set("pageSize", String(params.pageSize));

  const query = search.toString();
  return query ? `/classes/${classId}/roster?${query}` : `/classes/${classId}/roster`;
}
