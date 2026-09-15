import { TEACHER_ASSIGNMENT_ROLES, type TeacherAssignmentRole } from "./constants";

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

export type TeacherAssignmentFormValues = {
  teacherId: string;
  roleCode: TeacherAssignmentRole;
  effectiveFrom: string;
  effectiveTo: string;
};

export function validateTeacherAssignmentInput(input: Partial<TeacherAssignmentFormValues>) {
  const fieldErrors: Partial<Record<keyof TeacherAssignmentFormValues, string>> = {};
  const teacherId = (input.teacherId ?? "").trim();
  const roleRaw = (input.roleCode ?? "primary").trim() as TeacherAssignmentRole;
  const effectiveFromRaw = (input.effectiveFrom ?? "").trim();
  const effectiveToRaw = (input.effectiveTo ?? "").trim();

  if (!teacherId) fieldErrors.teacherId = "required";
  if (!TEACHER_ASSIGNMENT_ROLES.includes(roleRaw)) fieldErrors.roleCode = "invalid";

  let effectiveFrom = "";
  if (!effectiveFromRaw) fieldErrors.effectiveFrom = "required";
  else if (!isValidIsoDate(effectiveFromRaw)) fieldErrors.effectiveFrom = "invalid";
  else effectiveFrom = effectiveFromRaw;

  let effectiveTo = "";
  if (effectiveToRaw) {
    if (!isValidIsoDate(effectiveToRaw)) fieldErrors.effectiveTo = "invalid";
    else {
      effectiveTo = effectiveToRaw;
      if (effectiveFrom && effectiveTo < effectiveFrom) {
        fieldErrors.effectiveTo = "beforeStart";
      }
    }
  }

  return {
    ok: Object.keys(fieldErrors).length === 0,
    fieldErrors,
    data: {
      teacherId,
      roleCode: roleRaw,
      effectiveFrom,
      effectiveTo: effectiveTo || null,
    },
  };
}
