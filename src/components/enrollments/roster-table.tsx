import { getTranslations } from "next-intl/server";
import { RosterLifecycleActions } from "@/components/enrollments/roster-lifecycle-actions";
import type { RosterListItem } from "@/lib/enrollments/query-class-roster";
import { OPERATIONAL_ENROLLMENT_STATUSES } from "@/lib/enrollments/constants";

type ClassOption = {
  id: string;
  name: string;
  courseCode: string;
};

type Props = {
  items: RosterListItem[];
  canUpdate: boolean;
  showOperationalTuition: boolean;
  classId: string;
  classOptions: ClassOption[];
};

export async function RosterTable({
  items,
  canUpdate,
  showOperationalTuition,
  classId,
  classOptions,
}: Props) {
  const t = await getTranslations("enrollments");
  const tStatus = await getTranslations("status.enrollment");
  const tPayState = await getTranslations("consultantWorkspace.paymentState");
  const placeholder = t("emptyValue");

  return (
    <div className="hidden overflow-x-auto lg:block">
      <table className="min-w-full divide-y divide-slate-200 text-sm">
        <thead className="bg-slate-50">
          <tr>
            <th scope="col" className="px-4 py-3 text-left font-medium text-slate-700">
              {t("studentNameColumn")}
            </th>
            <th scope="col" className="px-4 py-3 text-left font-medium text-slate-700">
              {t("studentCodeColumn")}
            </th>
            <th scope="col" className="px-4 py-3 text-left font-medium text-slate-700">
              {t("statusColumn")}
            </th>
            {showOperationalTuition ? (
              <th scope="col" className="px-4 py-3 text-left font-medium text-slate-700">
                {t("operationalTuitionColumn")}
              </th>
            ) : null}
            <th scope="col" className="px-4 py-3 text-left font-medium text-slate-700">
              {t("startDate")}
            </th>
            <th scope="col" className="px-4 py-3 text-left font-medium text-slate-700">
              {t("endDate")}
            </th>
            {canUpdate ? (
              <th scope="col" className="px-4 py-3 text-left font-medium text-slate-700">
                <span className="sr-only">{t("actionsColumn")}</span>
              </th>
            ) : null}
          </tr>
        </thead>
        <tbody className="divide-y divide-slate-200 bg-white">
          {items.map((item) => {
            const isOperational = OPERATIONAL_ENROLLMENT_STATUSES.includes(
              item.status as (typeof OPERATIONAL_ENROLLMENT_STATUSES)[number],
            );
            return (
              <tr key={item.enrollmentId}>
                <td className="px-4 py-3 font-medium text-slate-900">{item.studentName}</td>
                <td className="px-4 py-3 text-slate-700">{item.studentCode ?? placeholder}</td>
                <td className="px-4 py-3">
                  <span className="inline-flex rounded-full bg-slate-100 px-2.5 py-0.5 text-xs font-medium text-slate-800">
                    {tStatus(item.status)}
                  </span>
                </td>
                {showOperationalTuition ? (
                  <td className="px-4 py-3" data-testid="roster-operational-tuition">
                    {item.operationalTuitionStatus ? (
                      <span className="inline-flex rounded-full bg-amber-50 px-2.5 py-0.5 text-xs font-medium text-amber-900">
                        {tPayState(item.operationalTuitionStatus as "chua_coc")}
                      </span>
                    ) : (
                      placeholder
                    )}
                  </td>
                ) : null}
                <td className="px-4 py-3 text-slate-700">{item.startDate}</td>
                <td className="px-4 py-3 text-slate-700">{item.endDate ?? placeholder}</td>
                {canUpdate ? (
                  <td className="px-4 py-3">
                    {isOperational ? (
                      <RosterLifecycleActions
                        enrollmentId={item.enrollmentId}
                        canUpdate={canUpdate}
                        classOptions={classOptions}
                        currentClassId={classId}
                      />
                    ) : (
                      placeholder
                    )}
                  </td>
                ) : null}
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}
