import {
  COURSE_CODE_MAX_LENGTH,
  COURSE_STATUSES,
  DEFAULT_COURSE_STATUS,
  type CourseStatus,
} from "@/lib/academic/constants";

export type CourseFieldErrors = Partial<
  Record<"code" | "name" | "levelCode" | "status", string>
>;

export type ValidatedCourseInput = {
  code: string;
  name: string;
  levelCode: string | null;
  status: CourseStatus;
};

function trimText(value: string): string {
  return value.trim();
}

export function validateCourseInput(input: {
  code: string;
  name: string;
  levelCode?: string | null;
  status?: string | null;
}): { ok: true; data: ValidatedCourseInput } | { ok: false; fieldErrors: CourseFieldErrors } {
  const fieldErrors: CourseFieldErrors = {};

  const code = trimText(input.code ?? "");
  const name = trimText(input.name ?? "");

  if (!code) fieldErrors.code = "required";
  if (code.length > COURSE_CODE_MAX_LENGTH) fieldErrors.code = "tooLong";
  if (!name) fieldErrors.name = "required";

  const levelCodeRaw = trimText(input.levelCode ?? "");
  const levelCode = levelCodeRaw.length > 0 ? levelCodeRaw : null;

  const rawStatus = (input.status ?? DEFAULT_COURSE_STATUS).trim();
  const status = rawStatus as CourseStatus;
  if (!COURSE_STATUSES.includes(status)) {
    fieldErrors.status = "invalid";
  }

  if (Object.keys(fieldErrors).length > 0) {
    return { ok: false, fieldErrors };
  }

  return { ok: true, data: { code, name, levelCode, status } };
}

export function isCourseCodeConflict(error: { code?: string } | null): boolean {
  return error?.code === "23505";
}
