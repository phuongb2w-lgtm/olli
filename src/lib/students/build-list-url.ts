import type { StudentListParams } from "@/lib/students/types";

export function buildStudentListUrl(params: Partial<StudentListParams>): string {
  const search = new URLSearchParams();

  if (params.q?.trim()) {
    search.set("q", params.q.trim());
  }

  if (params.status && params.status !== "all") {
    search.set("status", params.status);
  }

  if (params.page && params.page > 1) {
    search.set("page", String(params.page));
  }

  if (params.pageSize && params.pageSize !== 25) {
    search.set("pageSize", String(params.pageSize));
  }

  const query = search.toString();
  return query ? `/students?${query}` : "/students";
}
