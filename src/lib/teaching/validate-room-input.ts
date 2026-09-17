import { ROOM_STATUSES, type RoomStatus } from "./constants";

export type RoomFormValues = {
  name: string;
  code: string;
  capacity: string;
  notes: string;
  status: RoomStatus;
};

export function validateRoomInput(input: Partial<RoomFormValues>) {
  const fieldErrors: Partial<Record<keyof RoomFormValues, string>> = {};
  const name = (input.name ?? "").trim();
  const code = (input.code ?? "").trim();
  const capacityRaw = (input.capacity ?? "").trim();
  const notes = (input.notes ?? "").trim();
  const statusRaw = (input.status ?? "active").trim() as RoomStatus;

  if (!name) fieldErrors.name = "required";
  if (name.length > 200) fieldErrors.name = "tooLong";

  if (code.length > 50) fieldErrors.code = "tooLong";
  if (notes.length > 500) fieldErrors.notes = "tooLong";

  let capacity: number | null = null;
  if (capacityRaw) {
    const parsed = Number(capacityRaw);
    if (!Number.isInteger(parsed) || parsed <= 0) fieldErrors.capacity = "invalid";
    else capacity = parsed;
  }

  if (!ROOM_STATUSES.includes(statusRaw)) fieldErrors.status = "invalid";

  return {
    ok: Object.keys(fieldErrors).length === 0,
    fieldErrors,
    data: {
      name,
      code: code || null,
      capacity,
      notes: notes || null,
      status: statusRaw,
    },
  };
}

export function getRoomCapacityWarning(
  classCapacity: number | null,
  roomCapacity: number | null,
): boolean {
  if (classCapacity == null || classCapacity <= 0) return false;
  if (roomCapacity == null || roomCapacity <= 0) return false;
  return classCapacity > roomCapacity;
}
