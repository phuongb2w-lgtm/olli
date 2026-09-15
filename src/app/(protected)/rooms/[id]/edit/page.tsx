import Link from "next/link";
import { notFound } from "next/navigation";
import { getTranslations } from "next-intl/server";
import { RoomForm } from "@/components/rooms/room-form";
import { can } from "@/lib/permissions/can";
import { createClient } from "@/lib/supabase/server";
import { fetchRoomById } from "@/lib/teaching/query-rooms";

export const dynamic = "force-dynamic";

type Props = {
  params: Promise<{ id: string }>;
  searchParams: Promise<Record<string, string | string[] | undefined>>;
};

export default async function EditRoomPage({ params, searchParams }: Props) {
  const t = await getTranslations("teaching");
  const { id } = await params;
  const rawParams = await searchParams;
  const hasUpdate = await can("enrollment.update");

  if (!hasUpdate) {
    return (
      <div className="space-y-4">
        <h1 className="text-xl font-semibold">{t("editRoom")}</h1>
        <section className="rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-600">
          <p>{t("permissionDenied")}</p>
          <Link href="/rooms" className="mt-3 inline-block text-slate-900 underline">
            {t("backToRooms")}
          </Link>
        </section>
      </div>
    );
  }

  const supabase = await createClient();
  const room = await fetchRoomById(supabase, id);
  if (!room) notFound();

  const success = rawParams.success;
  const successKey = typeof success === "string" ? success : undefined;

  return (
    <div className="space-y-6">
      <header className="space-y-2">
        <Link href="/rooms" className="text-sm text-slate-600 underline">
          {t("backToRooms")}
        </Link>
        <h1 className="text-xl font-semibold text-slate-900">{t("editRoom")}</h1>
        {successKey ? (
          <p className="rounded-md bg-green-50 px-3 py-2 text-sm text-green-800" role="status">
            {t(`success.${successKey}`)}
          </p>
        ) : null}
      </header>
      <RoomForm room={room} />
    </div>
  );
}
