import {
  CREATE_ENROLLMENT_STATUSES,
  ENROLLMENT_STATUSES,
  type CreateEnrollmentStatus,
  type EnrollmentStatus,
} from "@/lib/enrollments/constants";

export type EnrollmentFieldErrors = Partial<
  Record<"studentId" | "classId" | "startDate" | "endDate" | "status", string>
>;

export type ValidatedEnrollmentInput = {
  studentId: string;
  classId: string;
  startDate: string;
  endDate: string | null;
  status: CreateEnrollmentStatus;
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

export function validateCreateEnrollmentInput(input: {
  studentId: string;
  classId: string;
  startDate: string;
  status?: string | null;
}): { ok: true; data: ValidatedEnrollmentInput } | { ok: false; fieldErrors: EnrollmentFieldErrors } {
  const fieldErrors: EnrollmentFieldErrors = {};

  const studentId = (input.studentId ?? "").trim();
  const classId = (input.classId ?? "").trim();
  const startDateRaw = (input.startDate ?? "").trim();

  if (!studentId) fieldErrors.studentId = "required";
  if (!classId) fieldErrors.classId = "required";

  let startDate = "";
  if (!startDateRaw) {
    fieldErrors.startDate = "required";
  } else if (!isValidIsoDate(startDateRaw)) {
    fieldErrors.startDate = "invalid";
  } else {
    startDate = startDateRaw;
  }

  const rawStatus = (input.status ?? "pending").trim();
  const status = rawStatus as CreateEnrollmentStatus;
  if (!CREATE_ENROLLMENT_STATUSES.includes(status)) {
    fieldErrors.status = "invalid";
  }

  if (Object.keys(fieldErrors).length > 0) {
    return { ok: false, fieldErrors };
  }

  return {
    ok: true,
    data: { studentId, classId, startDate, endDate: null, status },
  };
}

export function validateEnrollmentDateEdit(input: {
  startDate: string;
  endDate?: string | null;
}): { ok: true; startDate: string; endDate: string | null } | { ok: false; fieldErrors: EnrollmentFieldErrors } {
  const fieldErrors: EnrollmentFieldErrors = {};
  const startDateRaw = (input.startDate ?? "").trim();
  let startDate = "";
  if (!startDateRaw || !isValidIsoDate(startDateRaw)) {
    fieldErrors.startDate = "invalid";
  } else {
    startDate = startDateRaw;
  }

  let endDate: string | null = null;
  const endRaw = (input.endDate ?? "").trim();
  if (endRaw) {
    if (!isValidIsoDate(endRaw)) fieldErrors.endDate = "invalid";
    else endDate = endRaw;
  }

  if (startDate && endDate && endDate < startDate) {
    fieldErrors.endDate = "beforeStart";
  }

  if (Object.keys(fieldErrors).length > 0) {
    return { ok: false, fieldErrors };
  }

  return { ok: true, startDate, endDate };
}

export function isEnrollmentStatus(value: string): value is EnrollmentStatus {
  return ENROLLMENT_STATUSES.includes(value as EnrollmentStatus);
}

export function isOverlapConflict(error: { code?: string; message?: string } | null): boolean {
  if (!error) return false;
  if (error.code === "23P01") return true;
  return error.message?.includes("overlap_conflict") ?? false;
}

export function isCapacityReached(error: { message?: string } | null): boolean {
  return error?.message?.includes("capacity_reached") ?? false;
}
