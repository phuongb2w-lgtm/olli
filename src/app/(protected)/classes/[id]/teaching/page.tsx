import Link from "next/link";
import { notFound } from "next/navigation";
import { getTranslations } from "next-intl/server";
import { ScheduleForm } from "@/components/teaching/schedule-form";
import { ScheduleList } from "@/components/teaching/schedule-list";
import { SessionList } from "@/components/teaching/session-list";
import { TeacherAssignmentForm } from "@/components/teaching/teacher-assignment-form";
import { TeacherAssignmentList } from "@/components/teaching/teacher-assignment-list";
import { can } from "@/lib/permissions/can";
import { createClient } from "@/lib/supabase/server";
import {
  fetchActiveRooms,
  fetchClassSchedules,
  fetchClassSessions,
  fetchClassTeachingContext,
  fetchEligibleTeachers,
  fetchTeacherAssignments,
} from "@/lib/teaching/query-class-teaching";

export const dynamic = "force-dynamic";

type Props = {
  params: Promise<{ id: string }>;
  searchParams: Promise<Record<string, string | string[] | undefined>>;
};

export default async function ClassTeachingPage({ params, searchParams }: Props) {
  const t = await getTranslations("teaching");
  const { id: classId } = await params;
  const rawParams = await searchParams;
  const hasRead = await can("enrollment.read");

  if (!hasRead) {
    return (
      <div className="space-y-4">
        <h1 className="text-xl font-semibold">{t("title")}</h1>
        <section className="rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-600">
          <p>{t("denied")}</p>
        </section>
      </div>
    );
  }

  const hasCreate = await can("enrollment.create");
  const hasUpdate = await can("enrollment.update");
  const supabase = await createClient();

  const classContext = await fetchClassTeachingContext(supabase, classId);
  if (!classContext) notFound();

  const today = new Date();
  const defaultRangeStart = today.toISOString().slice(0, 10);
  const defaultRangeEnd = new Date(today.getTime() + 28 * 86400000).toISOString().slice(0, 10);

  const [assignments, schedules, sessions, teachers, rooms] = await Promise.all([
    fetchTeacherAssignments(supabase, classId),
    fetchClassSchedules(supabase, classId),
    fetchClassSessions(supabase, classId),
    fetchEligibleTeachers(supabase),
    fetchActiveRooms(supabase),
  ]);

  const success = rawParams.success;
  const successKey = typeof success === "string" ? success : undefined;

  return (
    <div className="space-y-8">
      <header className="space-y-2">
        <Link href="/classes" className="text-sm text-slate-600 underline">
          {t("backToClasses")}
        </Link>
        <h1 className="text-xl font-semibold text-slate-900">
          {t("title")} — {classContext.name}
        </h1>
        <p className="text-sm text-slate-600">{t("subtitle")}</p>
        {successKey ? (
          <p className="rounded-md bg-green-50 px-3 py-2 text-sm text-green-800" role="status">
            {t(`success.${successKey}`)}
          </p>
        ) : null}
      </header>

      <section className="space-y-4">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <h2 className="text-lg font-semibold text-slate-900">{t("teachers")}</h2>
          <Link href="/rooms" className="text-sm text-slate-700 underline">
            {t("manageRooms")}
          </Link>
        </div>
        <TeacherAssignmentList
          classId={classId}
          assignments={assignments}
          canUpdate={hasUpdate}
        />
        {hasCreate ? <TeacherAssignmentForm classId={classId} teachers={teachers} /> : null}
      </section>

      <section className="space-y-4">
        <h2 className="text-lg font-semibold text-slate-900">{t("recurringSchedule")}</h2>
        <ScheduleList
          classId={classId}
          schedules={schedules}
          canCreate={hasCreate}
          canUpdate={hasUpdate}
          defaultRangeStart={defaultRangeStart}
          defaultRangeEnd={defaultRangeEnd}
        />
        {hasCreate && classContext.status !== "closed" ? (
          <ScheduleForm
            classId={classId}
            classCapacity={classContext.capacity}
            teachers={teachers}
            rooms={rooms}
          />
        ) : null}
      </section>

      <section className="space-y-4">
        <h2 className="text-lg font-semibold text-slate-900">{t("teachingSessions")}</h2>
        <SessionList classId={classId} sessions={sessions} canUpdate={hasUpdate} />
      </section>
    </div>
  );
}
