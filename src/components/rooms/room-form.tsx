"use client";

import { useActionState } from "react";
import { useTranslations } from "next-intl";
import {
  createRoomAction,
  updateRoomAction,
  type TeachingActionState,
} from "@/app/actions/teaching";
import { ROOM_STATUSES } from "@/lib/teaching/constants";
import type { RoomListItem } from "@/lib/teaching/query-rooms";

type Props = {
  room?: RoomListItem;
};

const initialState: TeachingActionState = {};

export function RoomForm({ room }: Props) {
  const t = useTranslations("teaching");
  const action = room ? updateRoomAction : createRoomAction;
  const [state, formAction, pending] = useActionState(action, initialState);

  return (
    <form action={formAction} className="mx-auto max-w-lg space-y-4">
      {room ? <input type="hidden" name="roomId" value={room.id} /> : null}

      {state.error === "permission_denied" ? (
        <p className="text-sm text-red-700">{t("permissionDenied")}</p>
      ) : null}
      {state.error === "save_error" && !state.fieldErrors ? (
        <p className="text-sm text-red-700">{t("saveError")}</p>
      ) : null}

      <div>
        <label htmlFor="name" className="block text-sm font-medium text-slate-700">
          {t("roomName")}
        </label>
        <input
          id="name"
          name="name"
          required
          defaultValue={state.values?.name ?? room?.name ?? ""}
          className="mt-1 block w-full rounded-md border border-slate-300 px-3 py-2 text-sm"
        />
      </div>

      <div>
        <label htmlFor="code" className="block text-sm font-medium text-slate-700">
          {t("roomCode")}
        </label>
        <input
          id="code"
          name="code"
          defaultValue={state.values?.code ?? room?.code ?? ""}
          className="mt-1 block w-full rounded-md border border-slate-300 px-3 py-2 text-sm"
        />
      </div>

      <div>
        <label htmlFor="capacity" className="block text-sm font-medium text-slate-700">
          {t("roomCapacity")}
        </label>
        <input
          id="capacity"
          name="capacity"
          type="number"
          min={1}
          defaultValue={state.values?.capacity ?? (room?.capacity?.toString() ?? "")}
          className="mt-1 block w-full rounded-md border border-slate-300 px-3 py-2 text-sm"
        />
      </div>

      <div>
        <label htmlFor="notes" className="block text-sm font-medium text-slate-700">
          {t("roomNotes")}
        </label>
        <textarea
          id="notes"
          name="notes"
          rows={3}
          defaultValue={state.values?.notes ?? room?.notes ?? ""}
          className="mt-1 block w-full rounded-md border border-slate-300 px-3 py-2 text-sm"
        />
      </div>

      <div>
        <label htmlFor="status" className="block text-sm font-medium text-slate-700">
          {t("status")}
        </label>
        <select
          id="status"
          name="status"
          defaultValue={state.values?.status ?? room?.status ?? "active"}
          className="mt-1 block w-full rounded-md border border-slate-300 px-3 py-2 text-sm"
        >
          {ROOM_STATUSES.map((status) => (
            <option key={status} value={status}>
              {t(`roomStatus.${status}`)}
            </option>
          ))}
        </select>
      </div>

      <button
        type="submit"
        disabled={pending}
        className="rounded-md bg-slate-900 px-4 py-2 text-sm font-medium text-white disabled:opacity-50"
      >
        {pending ? t("saving") : room ? t("editRoom") : t("addRoom")}
      </button>
    </form>
  );
}
