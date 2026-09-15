import Link from "next/link";
import { getTranslations } from "next-intl/server";
import { RoomListCards } from "@/components/rooms/room-list-cards";
import { RoomListTable } from "@/components/rooms/room-list-table";
import { can } from "@/lib/permissions/can";
import { createClient } from "@/lib/supabase/server";
import { fetchRoomList } from "@/lib/teaching/query-rooms";

export const dynamic = "force-dynamic";

type Props = {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
};

export default async function RoomsPage({ searchParams }: Props) {
  const t = await getTranslations("teaching");
  const rawParams = await searchParams;
  const hasRead = await can("enrollment.read");

  if (!hasRead) {
    return (
      <div className="space-y-4">
        <h1 className="text-xl font-semibold">{t("rooms")}</h1>
        <section className="rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-600">
          <p>{t("denied")}</p>
        </section>
      </div>
    );
  }

  const hasCreate = await can("enrollment.create");
  const hasUpdate = await can("enrollment.update");
  const supabase = await createClient();
  const rooms = await fetchRoomList(supabase);
  const success = rawParams.success;
  const successKey = typeof success === "string" ? success : undefined;

  return (
    <div className="space-y-6">
      <header className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-xl font-semibold text-slate-900">{t("rooms")}</h1>
          <p className="text-sm text-slate-600">{t("roomsSubtitle")}</p>
        </div>
        {hasCreate ? (
          <Link
            href="/rooms/new"
            className="rounded-md bg-slate-900 px-4 py-2 text-sm font-medium text-white"
          >
            {t("addRoom")}
          </Link>
        ) : null}
      </header>

      {successKey ? (
        <p className="rounded-md bg-green-50 px-3 py-2 text-sm text-green-800" role="status">
          {t(`success.${successKey}`)}
        </p>
      ) : null}

      {rooms.length === 0 ? (
        <p className="text-sm text-slate-600">{t("noRooms")}</p>
      ) : (
        <>
          <RoomListTable items={rooms} canUpdate={hasUpdate} />
          <RoomListCards items={rooms} canUpdate={hasUpdate} />
        </>
      )}
    </div>
  );
}
