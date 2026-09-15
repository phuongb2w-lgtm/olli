"use client";

import { useActionState, useState } from "react";
import { useTranslations } from "next-intl";
import {
  completeEnrollment,
  transferEnrollment,
  withdrawEnrollment,
  type EnrollmentActionState,
  type TransferActionState,
} from "@/app/actions/enrollments";
import { CREATE_ENROLLMENT_STATUSES } from "@/lib/enrollments/constants";

type ClassOption = {
  id: string;
  name: string;
  courseCode: string;
};

type Props = {
  enrollmentId: string;
  canUpdate: boolean;
  classOptions: ClassOption[];
  currentClassId: string;
};

const initialWithdrawState: EnrollmentActionState = {};
const initialCompleteState: EnrollmentActionState = {};
const initialTransferState: TransferActionState = {};

export function RosterLifecycleActions({
  enrollmentId,
  canUpdate,
  classOptions,
  currentClassId,
}: Props) {
  const t = useTranslations("enrollments");
  const tStatus = useTranslations("status.enrollment");
  const [showTransfer, setShowTransfer] = useState(false);

  const [withdrawState, withdrawAction, withdrawPending] = useActionState(
    withdrawEnrollment,
    initialWithdrawState,
  );
  const [completeState, completeAction, completePending] = useActionState(
    completeEnrollment,
    initialCompleteState,
  );
  const [transferState, transferAction, transferPending] = useActionState(
    transferEnrollment,
    initialTransferState,
  );

  if (!canUpdate) return null;

  const transferError =
    transferState.error === "overlap_conflict"
      ? t("overlapConflict")
      : transferState.error === "capacity_reached"
        ? t("capacityReached")
        : transferState.error === "class_closed"
          ? t("classClosed")
          : transferState.error === "save_error"
            ? t("saveError")
            : null;

  const destClasses = classOptions.filter((c) => c.id !== currentClassId);

  return (
    <div className="flex flex-col gap-2 text-sm">
      <form action={withdrawAction} className="space-y-2">
        <input type="hidden" name="enrollmentId" value={enrollmentId} />
        {withdrawState.confirmRequired === "withdraw" ? (
          <div className="rounded border border-amber-200 bg-amber-50 p-2 text-amber-900">
            <p>{t("withdrawConfirmMessage")}</p>
            <label className="mt-2 flex items-start gap-2">
              <input type="checkbox" name="confirmWithdraw" value="true" className="mt-0.5" />
              <span>{t("confirmWithdraw")}</span>
            </label>
          </div>
        ) : null}
        <button
          type="submit"
          disabled={withdrawPending}
          className="text-left font-medium text-slate-900 underline hover:text-slate-700 disabled:opacity-50"
        >
          {t("withdraw")}
        </button>
      </form>

      <form action={completeAction} className="space-y-2">
        <input type="hidden" name="enrollmentId" value={enrollmentId} />
        {completeState.confirmRequired === "complete" ? (
          <div className="rounded border border-amber-200 bg-amber-50 p-2 text-amber-900">
            <p>{t("completeConfirmMessage")}</p>
            <label className="mt-2 flex items-start gap-2">
              <input type="checkbox" name="confirmComplete" value="true" className="mt-0.5" />
              <span>{t("confirmComplete")}</span>
            </label>
          </div>
        ) : null}
        <button
          type="submit"
          disabled={completePending}
          className="text-left font-medium text-slate-900 underline hover:text-slate-700 disabled:opacity-50"
        >
          {t("complete")}
        </button>
      </form>

      <button
        type="button"
        onClick={() => setShowTransfer((v) => !v)}
        className="text-left font-medium text-slate-900 underline hover:text-slate-700"
      >
        {t("transfer")}
      </button>

      {showTransfer ? (
        <form action={transferAction} className="mt-2 space-y-2 rounded border border-slate-200 p-3">
          <input type="hidden" name="enrollmentId" value={enrollmentId} />
          <div>
            <label htmlFor={`dest-${enrollmentId}`} className="mb-1 block text-xs font-medium">
              {t("transferDestination")}
            </label>
            <select
              id={`dest-${enrollmentId}`}
              name="destinationClassId"
              required
              defaultValue={transferState.values?.destinationClassId ?? ""}
              className="w-full rounded border border-slate-300 px-2 py-1 text-sm"
            >
              <option value="">{t("selectClass")}</option>
              {destClasses.map((cls) => (
                <option key={cls.id} value={cls.id}>
                  {cls.courseCode} — {cls.name}
                </option>
              ))}
            </select>
          </div>
          <div>
            <label htmlFor={`start-${enrollmentId}`} className="mb-1 block text-xs font-medium">
              {t("startDate")}
            </label>
            <input
              id={`start-${enrollmentId}`}
              name="startDate"
              type="date"
              required
              defaultValue={transferState.values?.startDate ?? ""}
              className="w-full rounded border border-slate-300 px-2 py-1 text-sm"
            />
          </div>
          <div>
            <label htmlFor={`status-${enrollmentId}`} className="mb-1 block text-xs font-medium">
              {t("statusColumn")}
            </label>
            <select
              id={`status-${enrollmentId}`}
              name="status"
              defaultValue={transferState.values?.status ?? "pending"}
              className="w-full rounded border border-slate-300 px-2 py-1 text-sm"
            >
              {CREATE_ENROLLMENT_STATUSES.map((status) => (
                <option key={status} value={status}>
                  {tStatus(status)}
                </option>
              ))}
            </select>
          </div>
          <label className="flex items-start gap-2 text-xs">
            <input type="checkbox" name="confirmTransfer" value="true" className="mt-0.5" />
            <span>{t("confirmTransfer")}</span>
          </label>
          {transferError ? (
            <p className="text-xs text-red-600" role="alert">
              {transferError}
            </p>
          ) : null}
          <button
            type="submit"
            disabled={transferPending}
            className="rounded bg-slate-900 px-3 py-1 text-xs font-medium text-white disabled:opacity-50"
          >
            {transferPending ? t("saving") : t("transfer")}
          </button>
        </form>
      ) : null}
    </div>
  );
}
