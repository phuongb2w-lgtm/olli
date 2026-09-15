import Link from "next/link";
import { getTranslations } from "next-intl/server";
import { RoomForm } from "@/components/rooms/room-form";
import { can } from "@/lib/permissions/can";

export const dynamic = "force-dynamic";

export default async function NewRoomPage() {
  const t = await getTranslations("teaching");
  const hasCreate = await can("enrollment.create");

  if (!hasCreate) {
    return (
      <div className="space-y-4">
        <h1 className="text-xl font-semibold">{t("addRoom")}</h1>
        <section className="rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-600">
          <p>{t("permissionDenied")}</p>
          <Link href="/rooms" className="mt-3 inline-block text-slate-900 underline">
            {t("backToRooms")}
          </Link>
        </section>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <header className="space-y-2">
        <Link href="/rooms" className="text-sm text-slate-600 underline">
          {t("backToRooms")}
        </Link>
        <h1 className="text-xl font-semibold text-slate-900">{t("addRoom")}</h1>
      </header>
      <RoomForm />
    </div>
  );
}
