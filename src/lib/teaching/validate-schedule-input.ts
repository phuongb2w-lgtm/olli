import type { ClassStatus } from "@/lib/academic/constants";
import { MAX_GENERATION_RANGE_DAYS, WEEKDAY_CODES, type WeekdayCode } from "./constants";

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

function isValidTime(value: string): boolean {
  return /^\d{2}:\d{2}(:\d{2})?$/.test(value);
}

function compareTime(a: string, b: string): number {
  return a.localeCompare(b);
}

export type ScheduleFormValues = {
  weekdayCode: WeekdayCode;
  startTime: string;
  endTime: string;
  effectiveFrom: string;
  effectiveTo: string;
  roomId: string;
  teacherId: string;
};

export function validateScheduleInput(
  input: Partial<ScheduleFormValues>,
  options?: { classStatus?: ClassStatus; termStart?: string | null; termEnd?: string | null },
) {
  const fieldErrors: Partial<Record<keyof ScheduleFormValues, string>> = {};
  const weekdayRaw = (input.weekdayCode ?? "").trim();
  const startTime = (input.startTime ?? "").trim();
  const endTime = (input.endTime ?? "").trim();
  const effectiveFromRaw = (input.effectiveFrom ?? "").trim();
  const effectiveToRaw = (input.effectiveTo ?? "").trim();
  const roomId = (input.roomId ?? "").trim();
  const teacherId = (input.teacherId ?? "").trim();

  let weekdayCode = weekdayRaw as WeekdayCode;
  if (!WEEKDAY_CODES.includes(weekdayRaw as WeekdayCode)) {
    fieldErrors.weekdayCode = "invalid";
    weekdayCode = "mon";
  }

  if (!startTime) fieldErrors.startTime = "required";
  else if (!isValidTime(startTime)) fieldErrors.startTime = "invalid";

  if (!endTime) fieldErrors.endTime = "required";
  else if (!isValidTime(endTime)) fieldErrors.endTime = "invalid";

  if (
    startTime &&
    endTime &&
    isValidTime(startTime) &&
    isValidTime(endTime) &&
    compareTime(endTime, startTime) <= 0
  ) {
    fieldErrors.endTime = "beforeStart";
  }

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

  if (options?.classStatus === "closed") {
    return {
      ok: false,
      fieldErrors: { ...fieldErrors, effectiveFrom: "classClosed" },
      data: null as null,
    };
  }

  if (effectiveFrom && options?.termStart && effectiveFrom < options.termStart) {
    fieldErrors.effectiveFrom = "outsideClassTerm";
  }
  if (effectiveFrom && options?.termEnd && effectiveFrom > options.termEnd) {
    fieldErrors.effectiveFrom = "outsideClassTerm";
  }
  if (effectiveTo && options?.termEnd && effectiveTo > options.termEnd) {
    fieldErrors.effectiveTo = "outsideClassTerm";
  }

  return {
    ok: Object.keys(fieldErrors).length === 0,
    fieldErrors,
    data: {
      weekdayCode,
      startTime: startTime.length === 5 ? `${startTime}:00` : startTime,
      endTime: endTime.length === 5 ? `${endTime}:00` : endTime,
      effectiveFrom,
      effectiveTo: effectiveTo || null,
      roomId: roomId || null,
      teacherId: teacherId || null,
    },
  };
}

export function validateGenerationRange(rangeStart: string, rangeEnd: string) {
  const fieldErrors: Partial<Record<"rangeStart" | "rangeEnd", string>> = {};
  if (!rangeStart || !isValidIsoDate(rangeStart)) fieldErrors.rangeStart = "invalid";
  if (!rangeEnd || !isValidIsoDate(rangeEnd)) fieldErrors.rangeEnd = "invalid";
  if (
    rangeStart &&
    rangeEnd &&
    isValidIsoDate(rangeStart) &&
    isValidIsoDate(rangeEnd) &&
    rangeEnd < rangeStart
  ) {
    fieldErrors.rangeEnd = "beforeStart";
  }
  if (
    rangeStart &&
    rangeEnd &&
    isValidIsoDate(rangeStart) &&
    isValidIsoDate(rangeEnd)
  ) {
    const start = new Date(`${rangeStart}T00:00:00Z`);
    const end = new Date(`${rangeEnd}T00:00:00Z`);
    const days = Math.round((end.getTime() - start.getTime()) / 86400000);
    if (days > MAX_GENERATION_RANGE_DAYS) {
      fieldErrors.rangeEnd = "tooLarge";
    }
  }
  return {
    ok: Object.keys(fieldErrors).length === 0,
    fieldErrors,
    data: { rangeStart, rangeEnd },
  };
}

export function isScheduleConflict(error: { code?: string; message?: string } | null) {
  if (!error) return false;
  if (error.code === "23P01") return true;
  return error.message?.includes("schedule_conflict") ?? false;
}

export function isRoomConflict(error: { code?: string; message?: string } | null) {
  if (!error) return false;
  if (error.code === "23P01") return true;
  return error.message?.includes("schedule_conflict") ?? false;
}

export function isTeacherConflict(error: { code?: string; message?: string } | null) {
  if (!error) return false;
  if (error.code === "23P01") return true;
  return error.message?.includes("schedule_conflict") ?? false;
}
