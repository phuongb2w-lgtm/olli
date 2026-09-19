import Link from "next/link";
import { notFound } from "next/navigation";
import { getTranslations } from "next-intl/server";
import { AcademicReviewActions } from "@/components/academic/academic-review-actions";
import { can } from "@/lib/permissions/can";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

type Props = {
  params: Promise<{ type: string; id: string }>;
};

export default async function AcademicReviewDetailPage({ params }: Props) {
  const t = await getTranslations("academic.review");
  const { type, id } = await params;

  const hasReview =
    (await can("attendance.review")) ||
    (await can("assessment_result.review")) ||
    (await can("observation.review"));

  if (!hasReview) {
    return (
      <section className="rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-600">
        <p>{t("denied")}</p>
      </section>
    );
  }

  const supabase = await createClient();

  if (type === "attendance") {
    const { data } = await supabase
      .from("attendance")
      .select("id, status, review_status, teaching_session_id, enrollment_id")
      .eq("id", id)
      .maybeSingle();
    if (!data) notFound();

    const { data: session } = await supabase
      .from("teaching_session")
      .select("class_id")
      .eq("id", data.teaching_session_id)
      .maybeSingle();

    return (
      <div className="space-y-4">
        <Link href="/academic/review" className="text-sm underline">
          {t("title")}
        </Link>
        <h1 className="text-xl font-semibold">{t("attendanceAwaitingReview")}</h1>
        <p className="text-sm text-slate-600">
          {data.status} · {data.review_status}
        </p>
        {session ? (
          <Link
            href={`/classes/${session.class_id}/teaching/sessions/${data.teaching_session_id}`}
            className="text-sm underline"
          >
            {t("viewDetail")}
          </Link>
        ) : null}
        {(await can("attendance.review")) ? (
          <AcademicReviewActions entityType="attendance" recordId={id} canReview />
        ) : null}
      </div>
    );
  }

  if (type === "scores") {
    const { data } = await supabase
      .from("assessment_result")
      .select("id, status, raw_score, max_score, assessment_id")
      .eq("id", id)
      .maybeSingle();
    if (!data) notFound();

    const { data: assessment } = await supabase
      .from("assessment")
      .select("class_id, title")
      .eq("id", data.assessment_id)
      .maybeSingle();

    return (
      <div className="space-y-4">
        <Link href="/academic/review" className="text-sm underline">
          {t("title")}
        </Link>
        <h1 className="text-xl font-semibold">{t("scoresAwaitingReview")}</h1>
        <p className="text-sm text-slate-600">
          {assessment?.title} · {data.raw_score}/{data.max_score} · {data.status}
        </p>
        {assessment ? (
          <Link
            href={`/classes/${assessment.class_id}/assessments/${data.assessment_id}`}
            className="text-sm underline"
          >
            {t("viewDetail")}
          </Link>
        ) : null}
        {(await can("assessment_result.review")) ? (
          <AcademicReviewActions entityType="assessment_result" recordId={id} canReview />
        ) : null}
      </div>
    );
  }

  if (type === "comments") {
    const { data } = await supabase
      .from("teacher_observation")
      .select("id, comment, review_status, translated_comment, class_id, teaching_session_id")
      .eq("id", id)
      .maybeSingle();
    if (!data) notFound();

    return (
      <div className="space-y-4">
        <Link href="/academic/review" className="text-sm underline">
          {t("title")}
        </Link>
        <h1 className="text-xl font-semibold">{t("commentsAwaitingReview")}</h1>
        <p className="text-sm text-slate-700">{data.comment}</p>
        {data.translated_comment ? (
          <p className="text-sm text-slate-600">{data.translated_comment}</p>
        ) : null}
        {data.teaching_session_id ? (
          <Link
            href={`/classes/${data.class_id}/teaching/sessions/${data.teaching_session_id}`}
            className="text-sm underline"
          >
            {t("viewDetail")}
          </Link>
        ) : null}
        {(await can("observation.review")) ? (
          <AcademicReviewActions
            entityType="teacher_observation"
            recordId={id}
            canReview
            canTranslate={!data.translated_comment}
            originalComment={data.comment}
          />
        ) : null}
      </div>
    );
  }

  notFound();
}
