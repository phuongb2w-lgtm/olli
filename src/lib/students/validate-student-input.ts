import {
  DEFAULT_STUDENT_STATUS,
  STUDENT_CODE_MAX_LENGTH,
  STUDENT_STATUSES,
  type StudentStatus,
} from "@/lib/students/constants";
import { normalizeStudentCode } from "@/lib/students/normalize-student-code";

export type StudentFieldErrors = Partial<
  Record<"familyName" | "givenName" | "studentCode" | "dateOfBirth" | "status", string>
>;

export type ValidatedStudentInput = {
  familyName: string;
  givenName: string;
  studentCode: string | null;
  dateOfBirth: string | null;
  status: StudentStatus;
};

export type StudentValidationResult =
  | { ok: true; data: ValidatedStudentInput }
  | { ok: false; fieldErrors: StudentFieldErrors };

function trimName(value: string): string {
  return value.trim();
}

function isValidIsoDate(value: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const [year, month, day] = value.split("-").map(Number);
  if (month < 1 || month > 12 || day < 1 || day > 31) return false;
  const date = new Date(Date.UTC(year, month - 1, day));
  if (
    date.getUTCFullYear() !== year ||
    date.getUTCMonth() !== month - 1 ||
    date.getUTCDate() !== day
  ) {
    return false;
  }
  return true;
}

export function validateStudentInput(input: {
  familyName: string;
  givenName: string;
  studentCode?: string | null;
  dateOfBirth?: string | null;
  status?: string | null;
}): StudentValidationResult {
  const fieldErrors: StudentFieldErrors = {};

  const familyName = trimName(input.familyName ?? "");
  const givenName = trimName(input.givenName ?? "");

  if (!familyName) {
    fieldErrors.familyName = "required";
  }
  if (!givenName) {
    fieldErrors.givenName = "required";
  }

  const studentCode = normalizeStudentCode(input.studentCode ?? null);
  if (studentCode && studentCode.length > STUDENT_CODE_MAX_LENGTH) {
    fieldErrors.studentCode = "tooLong";
  }

  let dateOfBirth: string | null = null;
  const rawDob = (input.dateOfBirth ?? "").trim();
  if (rawDob) {
    if (!isValidIsoDate(rawDob)) {
      fieldErrors.dateOfBirth = "invalid";
    } else {
      dateOfBirth = rawDob;
    }
  }

  const rawStatus = (input.status ?? DEFAULT_STUDENT_STATUS).trim();
  const status = rawStatus as StudentStatus;
  if (!STUDENT_STATUSES.includes(status)) {
    fieldErrors.status = "invalid";
  }

  if (Object.keys(fieldErrors).length > 0) {
    return { ok: false, fieldErrors };
  }

  return {
    ok: true,
    data: {
      familyName,
      givenName,
      studentCode,
      dateOfBirth,
      status,
    },
  };
}
