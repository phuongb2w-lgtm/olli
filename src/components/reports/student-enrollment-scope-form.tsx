"use client";

type EnrollmentOption = {
  id: string;
  label: string;
};

type Props = {
  enrollments: EnrollmentOption[];
  selectedEnrollmentId?: string;
  allHistoryLabel: string;
  selectEnrollmentLabel: string;
  submitLabel: string;
  startDate: string;
  endDate: string;
  fromLabel: string;
  toLabel: string;
};

export function StudentEnrollmentScopeForm({
  enrollments,
  selectedEnrollmentId,
  allHistoryLabel,
  selectEnrollmentLabel,
  submitLabel,
  startDate,
  endDate,
  fromLabel,
  toLabel,
}: Props) {
  return (
    <form method="get" className="report-no-print space-y-3 rounded-lg border border-slate-200 bg-white p-4">
      <label className="flex flex-col gap-1 text-sm">
        <span className="font-medium text-slate-700">{selectEnrollmentLabel}</span>
        <select
          name="enrollmentId"
          defaultValue={selectedEnrollmentId ?? ""}
          className="rounded border border-slate-300 px-2 py-1.5"
        >
          <option value="">{allHistoryLabel}</option>
          {enrollments.map((enr) => (
            <option key={enr.id} value={enr.id}>
              {enr.label}
            </option>
          ))}
        </select>
      </label>
      <div className="flex flex-wrap items-end gap-3">
        <label className="flex flex-col gap-1 text-sm">
          <span className="font-medium text-slate-700">{fromLabel}</span>
          <input type="date" name="startDate" defaultValue={startDate} className="rounded border border-slate-300 px-2 py-1.5" />
        </label>
        <label className="flex flex-col gap-1 text-sm">
          <span className="font-medium text-slate-700">{toLabel}</span>
          <input type="date" name="endDate" defaultValue={endDate} className="rounded border border-slate-300 px-2 py-1.5" />
        </label>
        <button type="submit" className="rounded bg-slate-900 px-4 py-2 text-sm font-medium text-white hover:bg-slate-800">
          {submitLabel}
        </button>
      </div>
    </form>
  );
}
