import type { WeekdayCode } from "./constants";

export function formatWeekdayLabel(code: WeekdayCode, locale: string): string {
  const index = { sun: 0, mon: 1, tue: 2, wed: 3, thu: 4, fri: 5, sat: 6 }[code];
  const date = new Date(Date.UTC(2024, 0, 7 + index));
  return new Intl.DateTimeFormat(locale, { weekday: "long" }).format(date);
}

export function formatTimeRange(startTime: string, endTime: string, locale: string): string {
  const base = "1970-01-01";
  const start = new Date(`${base}T${startTime}`);
  const end = new Date(`${base}T${endTime}`);
  const fmt = new Intl.DateTimeFormat(locale, { hour: "2-digit", minute: "2-digit" });
  return `${fmt.format(start)}–${fmt.format(end)}`;
}
