import {
  CLASS_NAME_MAX_LENGTH,
  CLASS_STATUSES,
  DEFAULT_CLASS_STATUS,
  type ClassStatus,
} from "@/lib/academic/constants";

export type ClassFieldErrors = Partial<
  Record<"name" | "courseId" | "termStartDate" | "termEndDate" | "capacity" | "status", string>
>;

export type ValidatedClassInput = {
  name: string;
  courseId: string;
  termStartDate: string | null;
  termEndDate: string | null;
  capacity: number | null;
  status: ClassStatus;
};

function isValidIsoDate(value: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const [year, month, day] = value.split("-").map(Number);
  if (month < 1 || month > 12 || day < 1 || day > 31) return false;
  const date = new Date(Date.UTC(year, month - 1, day));
  return (
    date.getUTCFullYear() === year &&
    date.getUTCMonth() === month - 1 &&
    date.getUTCDate() === day
  );
}

export function validateClassInput(input: {
  name: string;
  courseId: string;
  termStartDate?: string | null;
  termEndDate?: string | null;
  capacity?: string | null;
  status?: string | null;
}): { ok: true; data: ValidatedClassInput } | { ok: false; fieldErrors: ClassFieldErrors } {
  const fieldErrors: ClassFieldErrors = {};

  const name = (input.name ?? "").trim();
  const courseId = (input.courseId ?? "").trim();

  if (!name) fieldErrors.name = "required";
  if (name.length > CLASS_NAME_MAX_LENGTH) fieldErrors.name = "tooLong";
  if (!courseId) fieldErrors.courseId = "required";

  let termStartDate: string | null = null;
  const rawStart = (input.termStartDate ?? "").trim();
  if (rawStart) {
    if (!isValidIsoDate(rawStart)) fieldErrors.termStartDate = "invalid";
    else termStartDate = rawStart;
  }

  let termEndDate: string | null = null;
  const rawEnd = (input.termEndDate ?? "").trim();
  if (rawEnd) {
    if (!isValidIsoDate(rawEnd)) fieldErrors.termEndDate = "invalid";
    else termEndDate = rawEnd;
  }

  if (termStartDate && termEndDate && termEndDate < termStartDate) {
    fieldErrors.termEndDate = "beforeStart";
  }

  let capacity: number | null = null;
  const rawCapacity = (input.capacity ?? "").trim();
  if (rawCapacity) {
    const parsed = Number.parseInt(rawCapacity, 10);
    if (!Number.isFinite(parsed) || parsed < 1) {
      fieldErrors.capacity = "invalid";
    } else {
      capacity = parsed;
    }
  }

  const rawStatus = (input.status ?? DEFAULT_CLASS_STATUS).trim();
  const status = rawStatus as ClassStatus;
  if (!CLASS_STATUSES.includes(status)) {
    fieldErrors.status = "invalid";
  }

  if (Object.keys(fieldErrors).length > 0) {
    return { ok: false, fieldErrors };
  }

  return {
    ok: true,
    data: { name, courseId, termStartDate, termEndDate, capacity, status },
  };
}
