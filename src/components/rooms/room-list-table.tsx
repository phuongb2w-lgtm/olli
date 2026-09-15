import Link from "next/link";
import { getTranslations } from "next-intl/server";
import type { RoomListItem } from "@/lib/teaching/query-rooms";

type Props = {
  items: RoomListItem[];
  canUpdate: boolean;
};

export async function RoomListTable({ items, canUpdate }: Props) {
  const t = await getTranslations("teaching");
  const tStatus = await getTranslations("status.room");

  return (
    <div className="hidden overflow-x-auto lg:block">
      <table className="min-w-full divide-y divide-slate-200 text-sm">
        <thead className="bg-slate-50">
          <tr>
            <th className="px-4 py-3 text-left font-medium text-slate-700">{t("roomName")}</th>
            <th className="px-4 py-3 text-left font-medium text-slate-700">{t("roomCode")}</th>
            <th className="px-4 py-3 text-left font-medium text-slate-700">{t("roomCapacity")}</th>
            <th className="px-4 py-3 text-left font-medium text-slate-700">{t("status")}</th>
            {canUpdate ? (
              <th className="px-4 py-3 text-left font-medium text-slate-700">
                <span className="sr-only">{t("actions")}</span>
              </th>
            ) : null}
          </tr>
        </thead>
        <tbody className="divide-y divide-slate-200 bg-white">
          {items.map((item) => (
            <tr key={item.id}>
              <td className="px-4 py-3 font-medium text-slate-900">{item.name}</td>
              <td className="px-4 py-3 text-slate-700">{item.code ?? "—"}</td>
              <td className="px-4 py-3 text-slate-700">{item.capacity ?? "—"}</td>
              <td className="px-4 py-3">
                <span className="inline-flex rounded-full bg-slate-100 px-2.5 py-0.5 text-xs font-medium text-slate-800">
                  {tStatus(item.status)}
                </span>
              </td>
              {canUpdate ? (
                <td className="px-4 py-3">
                  <Link
                    href={`/rooms/${item.id}/edit`}
                    className="text-sm font-medium text-slate-900 underline hover:text-slate-700"
                  >
                    {t("editRoom")}
                  </Link>
                </td>
              ) : null}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
