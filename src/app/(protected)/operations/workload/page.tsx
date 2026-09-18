import { getTranslations } from "next-intl/server";
import { OperationsSubnav } from "@/components/operations/operations-subnav";
import { WorkloadAnalyticsView } from "@/components/operations/workload-analytics-view";
import { can } from "@/lib/permissions/can";
import { createClient } from "@/lib/supabase/server";
import {
  currentMonthRange,
  fetchOperationalPlanningGaps,
  fetchRoomUsage,
  fetchTeacherWorkload,
} from "@/lib/teaching/query-workload-analytics";

export const dynamic = "force-dynamic";

type Props = {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
};

function firstParam(value: string | string[] | undefined): string {
  if (Array.isArray(value)) return value[0] ?? "";
  return value ?? "";
}

export default async function OperationsWorkloadPage({ searchParams }: Props) {
  const t = await getTranslations("operationsAnalytics");
  const raw = await searchParams;
  const hasRead = await can("enrollment.read");

  const defaultRange = currentMonthRange();
  const dateFrom = firstParam(raw.from) || defaultRange.from;
  const dateTo = firstParam(raw.to) || defaultRange.to;
  const classId = firstParam(raw.classId);
  const teacherId = firstParam(raw.teacherId);
  const roomId = firstParam(raw.roomId);

  if (!hasRead) {
    return (
      <div className="space-y-4">
        <header>
          <h1 className="text-xl font-semibold text-slate-900">{t("title")}</h1>
        </header>
        <OperationsSubnav />
        <section className="rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-600">
          <p>{t("denied")}</p>
        </section>
      </div>
    );
  }

  const supabase = await createClient();
  const filters = {
    dateFrom,
    dateTo,
    classId: classId || null,
    teacherId: teacherId || null,
    roomId: roomId || null,
  };

  const [teacherRes, roomRes, gapsRes, classesRes, teachersRes, roomsRes] = await Promise.all([
    fetchTeacherWorkload(supabase, filters),
    fetchRoomUsage(supabase, filters),
    fetchOperationalPlanningGaps(supabase, dateFrom, dateTo, classId || null),
    supabase.from("class").select("id, name").order("name"),
    supabase
      .from("teacher")
      .select("id, given_name, family_name")
      .eq("status", "active")
      .order("family_name"),
    supabase.from("room").select("id, name, code").eq("status", "active").order("name"),
  ]);

  const error = teacherRes.error ?? roomRes.error ?? gapsRes.error;

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
        <h1 className="text-xl font-semibold text-slate-900">{t("title")}</h1>
        <p className="text-sm text-slate-600">{t("subtitle")}</p>
      </header>

      <OperationsSubnav />

      <WorkloadAnalyticsView
        dateFrom={dateFrom}
        dateTo={dateTo}
        classId={classId}
        teacherId={teacherId}
        roomId={roomId}
        classes={classes}
        teachers={teachers}
        rooms={rooms}
        teacherRows={teacherRes.rows}
        roomRows={roomRes.rows}
        planningGaps={gapsRes.gaps}
        error={error}
      />
    </div>
  );
}
