import Link from "next/link";
import { notFound } from "next/navigation";
import { getTranslations } from "next-intl/server";
import { fetchClassReportContext } from "@/lib/reports/fetch-report-data";
import { can } from "@/lib/permissions/can";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

type Props = {
  params: Promise<{ id: string }>;
};

export default async function ClassReportsHubPage({ params }: Props) {
  const t = await getTranslations("reports");
  const { id: classId } = await params;

  const [hasAttendance, hasAssessment, hasEnrollment] = await Promise.all([
    can("attendance.read"),
    can("assessment.read"),
    can("enrollment.read"),
  ]);

  if (!hasAttendance && !hasAssessment && !hasEnrollment) {
    return (
      <div className="space-y-4">
        <h1 className="text-xl font-semibold">{t("title")}</h1>
        <section className="rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-600">
          <p>{t("deniedProgress")}</p>
        </section>
      </div>
    );
  }

  const supabase = await createClient();
  const context = await fetchClassReportContext(supabase, classId);
  if (!context) notFound();

  const links = [
    hasAttendance
      ? { href: `/classes/${classId}/reports/attendance`, label: t("attendanceReport") }
      : null,
    hasAssessment
      ? { href: `/classes/${classId}/reports/assessments`, label: t("assessmentReport") }
      : null,
    hasAttendance || hasAssessment
      ? { href: `/classes/${classId}/reports/end-of-course`, label: t("endOfCourseReport") }
      : null,
  ].filter(Boolean) as Array<{ href: string; label: string }>;

  return (
    <div className="space-y-6">
      <header className="space-y-2">
        <Link href="/classes" className="text-sm text-slate-600 underline">
          {t("backToClasses")}
        </Link>
        <h1 className="text-xl font-semibold text-slate-900">
          {t("title")} — {context.className}
        </h1>
        <p className="text-sm text-slate-600">{t("hubSubtitle")}</p>
      </header>
      <ul className="grid gap-3 sm:grid-cols-2">
        {links.map((link) => (
          <li key={link.href}>
            <Link
              href={link.href}
              className="block rounded-lg border border-slate-200 bg-white px-4 py-3 text-sm font-medium text-slate-900 hover:bg-slate-50"
            >
              {link.label}
            </Link>
          </li>
        ))}
      </ul>
    </div>
  );
}
