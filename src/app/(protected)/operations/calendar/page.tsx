import { getTranslations } from "next-intl/server";
import { OperationalCalendarView } from "@/components/operations/operational-calendar-view";
import { OperationsSubnav } from "@/components/operations/operations-subnav";
import { can } from "@/lib/permissions/can";
import { createClient } from "@/lib/supabase/server";
import { fetchOperationalCalendar } from "@/lib/teaching/query-operational-calendar";
import { todayInTimezone } from "@/lib/teaching/query-daily-operations";

export const dynamic = "force-dynamic";

type Props = {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
};

function firstParam(value: string | string[] | undefined): string {
  if (Array.isArray(value)) return value[0] ?? "";
  return value ?? "";
}

export default async function OperationsCalendarPage({ searchParams }: Props) {
  const t = await getTranslations("operations");
  const raw = await searchParams;
  const hasRead = await can("enrollment.read");

  if (!hasRead) {
    return (
      <div className="space-y-4">
        <h1 className="text-xl font-semibold text-slate-900">{t("calendarTitle")}</h1>
        <section className="rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-600">
          <p>{t("denied")}</p>
        </section>
      </div>
    );
  }

  const supabase = await createClient();
  const orgRes = await supabase.from("organization").select("timezone").limit(1).maybeSingle();
  const timezone = orgRes.data?.timezone ?? "Asia/Ho_Chi_Minh";
  const today = todayInTimezone(timezone);

  const dateFrom = firstParam(raw.from) || today;
  const dateTo = firstParam(raw.to) || dateFrom;
  const classId = firstParam(raw.classId);
  const teacherId = firstParam(raw.teacherId);
  const roomId = firstParam(raw.roomId);

  const [{ entries, error }, classesRes, teachersRes, roomsRes] = await Promise.all([
    fetchOperationalCalendar(supabase, {
      dateFrom,
      dateTo,
      classId: classId || null,
      teacherId: teacherId || null,
      roomId: roomId || null,
    }),
    supabase.from("class").select("id, name").order("name"),
    supabase
      .from("teacher")
      .select("id, given_name, family_name")
      .eq("status", "active")
      .order("family_name"),
    supabase.from("room").select("id, name, code").eq("status", "active").order("name"),
  ]);

  const classes = (classesRes.data ?? []).map((c) => ({ id: c.id, label: c.name }));
  const teachers = (teachersRes.data ?? []).map((teach) => ({
    id: teach.id,
    label: `${teach.given_name} ${teach.family_name}`.trim(),
  }));
  const rooms = (roomsRes.data ?? []).map((room) => ({
    id: room.id,
    label: room.code ? `${room.name} (${room.code})` : room.name,
  }));

  return (
    <div className="space-y-6">
      <header>
        <h1 className="text-xl font-semibold text-slate-900">{t("calendarTitle")}</h1>
        <p className="text-sm text-slate-600">{t("calendarSubtitle")}</p>
      </header>

      <OperationsSubnav />

      <OperationalCalendarView
        dateFrom={dateFrom}
        dateTo={dateTo}
        classId={classId}
        teacherId={teacherId}
        roomId={roomId}
        classes={classes}
        teachers={teachers}
        rooms={rooms}
        entries={entries}
        error={error}
        timezone={timezone}
      />
    </div>
  );
}
