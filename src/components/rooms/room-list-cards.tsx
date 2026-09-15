import Link from "next/link";
import { getTranslations } from "next-intl/server";
import type { RoomListItem } from "@/lib/teaching/query-rooms";

type Props = {
  items: RoomListItem[];
  canUpdate: boolean;
};

export async function RoomListCards({ items, canUpdate }: Props) {
  const t = await getTranslations("teaching");
  const tStatus = await getTranslations("status.room");

  return (
    <div className="space-y-3 lg:hidden">
      {items.map((item) => (
        <article
          key={item.id}
          className="rounded-lg border border-slate-200 bg-white p-4 text-sm"
        >
          <div className="flex items-start justify-between gap-2">
            <div>
              <p className="font-medium text-slate-900">{item.name}</p>
              {item.code ? <p className="text-slate-600">{item.code}</p> : null}
              {item.capacity ? (
                <p className="text-slate-600">
                  {t("roomCapacity")}: {item.capacity}
                </p>
              ) : null}
            </div>
            <span className="inline-flex rounded-full bg-slate-100 px-2.5 py-0.5 text-xs font-medium text-slate-800">
              {tStatus(item.status)}
            </span>
          </div>
          {canUpdate ? (
            <Link
              href={`/rooms/${item.id}/edit`}
              className="mt-3 inline-block text-sm font-medium text-slate-900 underline"
            >
              {t("editRoom")}
            </Link>
          ) : null}
        </article>
      ))}
    </div>
  );
}
