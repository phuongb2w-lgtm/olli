import type { ClassListParams } from "@/lib/academic/parse-list-params";
import type { CourseListParams } from "@/lib/academic/parse-list-params";

export function buildClassListUrl(params: Partial<ClassListParams>): string {
  const search = new URLSearchParams();

  if (params.q?.trim()) {
    search.set("q", params.q.trim());
  }

  if (params.status && params.status !== "all") {
    search.set("status", params.status);
  }

  if (params.course) {
    search.set("course", params.course);
  }

  if (params.page && params.page > 1) {
    search.set("page", String(params.page));
  }

  if (params.pageSize && params.pageSize !== 25) {
    search.set("pageSize", String(params.pageSize));
  }

  const query = search.toString();
  return query ? `/classes?${query}` : "/classes";
}

export function buildCourseListUrl(params: Partial<CourseListParams>): string {
  const search = new URLSearchParams();

  if (params.page && params.page > 1) {
    search.set("page", String(params.page));
  }

  if (params.pageSize && params.pageSize !== 25) {
    search.set("pageSize", String(params.pageSize));
  }

  const query = search.toString();
  return query ? `/courses?${query}` : "/courses";
}
