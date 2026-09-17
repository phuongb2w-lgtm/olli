function firstString(value: string | string[] | undefined): string {
  if (Array.isArray(value)) return value[0] ?? "";
  return value ?? "";
}

function formatDate(date: Date): string {
  return date.toISOString().slice(0, 10);
}

export type CrmReportParams = {
  startDate: string;
  endDate: string;
};

export function parseCrmReportParams(
  raw: Record<string, string | string[] | undefined>,
): CrmReportParams {
  const end = new Date();
  const start = new Date(end);
  start.setDate(start.getDate() - 30);

  const startRaw = firstString(raw.startDate).trim();
  const endRaw = firstString(raw.endDate).trim();

  const startDate = /^\d{4}-\d{2}-\d{2}$/.test(startRaw) ? startRaw : formatDate(start);
  const endDate = /^\d{4}-\d{2}-\d{2}$/.test(endRaw) ? endRaw : formatDate(end);

  if (endDate < startDate) {
    return { startDate: endDate, endDate: startDate };
  }

  return { startDate, endDate };
}
