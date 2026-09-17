import { UNAVAILABILITY_BLOCK_TYPES, UNAVAILABILITY_STATUSES, WEEKDAY_CODES, type UnavailabilityBlockType, type UnavailabilityStatus, type WeekdayCode } from "./constants";

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

export type RecurringUnavailabilityFormValues = {
  teacherId: string;
  weekdayCode: WeekdayCode;
  startTime: string;
  endTime: string;
  effectiveFrom: string;
  effectiveTo: string;
  reason: string;
};

export type OneOffUnavailabilityFormValues = {
  teacherId: string;
  startsAt: string;
  endsAt: string;
  reason: string;
};

export type UpdateRecurringUnavailabilityFormValues = RecurringUnavailabilityFormValues & {
  blockId: string;
  status?: UnavailabilityStatus;
};

export type UpdateOneOffUnavailabilityFormValues = OneOffUnavailabilityFormValues & {
  blockId: string;
  status?: UnavailabilityStatus;
};

export function validateRecurringUnavailabilityInput(input: Partial<RecurringUnavailabilityFormValues>) {
  const fieldErrors: Partial<Record<keyof RecurringUnavailabilityFormValues, string>> = {};
  const teacherId = (input.teacherId ?? "").trim();
  const weekdayRaw = (input.weekdayCode ?? "").trim();
  const startTime = (input.startTime ?? "").trim();
  const endTime = (input.endTime ?? "").trim();
  const effectiveFromRaw = (input.effectiveFrom ?? "").trim();
  const effectiveToRaw = (input.effectiveTo ?? "").trim();
  const reason = (input.reason ?? "").trim();

  if (!teacherId) fieldErrors.teacherId = "required";

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

  let effectiveTo: string | null = null;
  if (effectiveToRaw) {
    if (!isValidIsoDate(effectiveToRaw)) fieldErrors.effectiveTo = "invalid";
    else {
      effectiveTo = effectiveToRaw;
      if (effectiveFrom && effectiveTo < effectiveFrom) {
        fieldErrors.effectiveTo = "beforeStart";
      }
    }
  }

  if (reason.length > 500) fieldErrors.reason = "tooLong";

  return {
    ok: Object.keys(fieldErrors).length === 0,
    fieldErrors,
    data: {
      teacherId,
      weekdayCode,
      startTime: startTime.length === 5 ? `${startTime}:00` : startTime,
      endTime: endTime.length === 5 ? `${endTime}:00` : endTime,
      effectiveFrom,
      effectiveTo,
      reason: reason || null,
    },
  };
}

export function validateOneOffUnavailabilityInput(input: Partial<OneOffUnavailabilityFormValues>) {
  const fieldErrors: Partial<Record<keyof OneOffUnavailabilityFormValues, string>> = {};
  const teacherId = (input.teacherId ?? "").trim();
  const startsAtRaw = (input.startsAt ?? "").trim();
  const endsAtRaw = (input.endsAt ?? "").trim();
  const reason = (input.reason ?? "").trim();

  if (!teacherId) fieldErrors.teacherId = "required";

  let startsAt = "";
  if (!startsAtRaw) fieldErrors.startsAt = "required";
  else {
    const parsed = Date.parse(startsAtRaw);
    if (Number.isNaN(parsed)) fieldErrors.startsAt = "invalid";
    else startsAt = new Date(parsed).toISOString();
  }

  let endsAt = "";
  if (!endsAtRaw) fieldErrors.endsAt = "required";
  else {
    const parsed = Date.parse(endsAtRaw);
    if (Number.isNaN(parsed)) fieldErrors.endsAt = "invalid";
    else endsAt = new Date(parsed).toISOString();
  }

  if (startsAt && endsAt && endsAt <= startsAt) {
    fieldErrors.endsAt = "beforeStart";
  }

  if (reason.length > 500) fieldErrors.reason = "tooLong";

  return {
    ok: Object.keys(fieldErrors).length === 0,
    fieldErrors,
    data: {
      teacherId,
      startsAt,
      endsAt,
      reason: reason || null,
    },
  };
}

export function validateEndUnavailabilityInput(effectiveTo?: string) {
  const fieldErrors: Record<string, string> = {};
  const value = (effectiveTo ?? "").trim();
  if (value && !isValidIsoDate(value)) {
    fieldErrors.effectiveTo = "invalid";
  }
  return {
    ok: Object.keys(fieldErrors).length === 0,
    fieldErrors,
    data: { effectiveTo: value || null },
  };
}

export function isUnavailabilityBlockType(value: string): value is UnavailabilityBlockType {
  return UNAVAILABILITY_BLOCK_TYPES.includes(value as UnavailabilityBlockType);
}

export function isUnavailabilityStatus(value: string): value is UnavailabilityStatus {
  return UNAVAILABILITY_STATUSES.includes(value as UnavailabilityStatus);
}
