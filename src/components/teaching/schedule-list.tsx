import { getLocale, getTranslations } from "next-intl/server";
import { EndScheduleForm } from "@/components/teaching/end-schedule-form";
import { GenerateSessionsForm } from "@/components/teaching/generate-sessions-form";
import { formatTimeRange, formatWeekdayLabel } from "@/lib/teaching/format-weekday";
import type { ScheduleItem } from "@/lib/teaching/query-class-teaching";
import type { WeekdayCode } from "@/lib/teaching/constants";

type Props = {
  classId: string;
  schedules: ScheduleItem[];
  canCreate: boolean;
  canUpdate: boolean;
  defaultRangeStart: string;
  defaultRangeEnd: string;
};

export async function ScheduleList({
  classId,
  schedules,
  canCreate,
  canUpdate,
  defaultRangeStart,
  defaultRangeEnd,
}: Props) {
  const t = await getTranslations("teaching");
  const tStatus = await getTranslations("status.schedule");
  const locale = await getLocale();

  if (schedules.length === 0) {
    return <p className="text-sm text-slate-600">{t("noSchedule")}</p>;
  }

  return (
    <div className="space-y-3">
      {schedules.map((item) => (
        <article
          key={item.id}
          className="rounded-lg border border-slate-200 bg-white p-4 text-sm"
        >
          <div className="flex flex-wrap items-start justify-between gap-2">
            <div>
              <p className="font-medium text-slate-900">
                {formatWeekdayLabel(item.weekdayCode as WeekdayCode, locale)} ·{" "}
                {formatTimeRange(item.startTime, item.endTime, locale)}
              </p>
              <p className="text-slate-600">
                {t("effectiveFrom")} {item.effectiveFrom}
                {item.effectiveTo ? ` · ${t("effectiveUntil")} ${item.effectiveTo}` : ""}
              </p>
              {item.roomName ? (
                <p className="text-slate-600">
                  {t("room")}: {item.roomName}
                </p>
              ) : null}
              {item.teacherName ? (
                <p className="text-slate-600">
                  {t("teacher")}: {item.teacherName}
                </p>
              ) : null}
            </div>
            <span className="inline-flex rounded-full bg-slate-100 px-2.5 py-0.5 text-xs font-medium text-slate-800">
              {tStatus(item.status)}
            </span>
          </div>
          {canUpdate && item.status === "active" ? (
            <div className="mt-3 flex flex-wrap gap-2">
              <EndScheduleForm classId={classId} scheduleId={item.id} />
            </div>
          ) : null}
          {canCreate && item.status === "active" ? (
            <div className="mt-3 border-t border-slate-100 pt-3">
              <GenerateSessionsForm
                classId={classId}
                scheduleId={item.id}
                defaultRangeStart={defaultRangeStart}
                defaultRangeEnd={defaultRangeEnd}
              />
            </div>
          ) : null}
        </article>
      ))}
    </div>
  );
}
