import { getTranslations } from "next-intl/server";
import { AcademicReviewQueuePanel } from "@/components/academic/academic-review-queue-panel";
import { can } from "@/lib/permissions/can";
import {
  fetchAcademicReviewBacklog,
  fetchAcademicReviewQueue,
} from "@/lib/reporting/academic-read-model";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

export default async function AcademicReviewPage() {
  const t = await getTranslations("academic.review");

  const hasReview =
    (await can("attendance.review")) ||
    (await can("assessment_result.review")) ||
    (await can("observation.review"));

  if (!hasReview) {
    return (
      <div className="space-y-4">
        <h1 className="text-xl font-semibold">{t("title")}</h1>
        <section className="rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-600">
          <p>{t("denied")}</p>
        </section>
      </div>
    );
  }

  const supabase = await createClient();
  const { backlog } = await fetchAcademicReviewBacklog(supabase);

  const queues = await Promise.all([
    (await can("attendance.review"))
      ? fetchAcademicReviewQueue(supabase, "attendance_pending", 10)
      : Promise.resolve({ items: [], error: null }),
    (await can("assessment_result.review"))
      ? fetchAcademicReviewQueue(supabase, "scores_pending", 10)
      : Promise.resolve({ items: [], error: null }),
    (await can("observation.review"))
      ? fetchAcademicReviewQueue(supabase, "comments_pending", 10)
      : Promise.resolve({ items: [], error: null }),
    (await can("observation.review"))
      ? fetchAcademicReviewQueue(supabase, "translation_pending", 10)
      : Promise.resolve({ items: [], error: null }),
    fetchAcademicReviewQueue(supabase, "incomplete_sessions", 10),
  ]);

  const [
    attendancePending,
    scoresPending,
    commentsPending,
    translationPending,
    incompleteSessions,
  ] = queues;

  return (
    <div className="space-y-6">
      <h1 className="text-xl font-semibold">{t("title")}</h1>
      <p className="text-sm text-slate-600">{t("description")}</p>

      {backlog ? (
        <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
          <div className="rounded-lg border border-slate-200 bg-white p-3 text-sm">
            <p className="text-slate-600">{t("attendancePending")}</p>
            <p className="text-lg font-semibold">{backlog.attendancePending}</p>
          </div>
          <div className="rounded-lg border border-slate-200 bg-white p-3 text-sm">
            <p className="text-slate-600">{t("scoresPending")}</p>
            <p className="text-lg font-semibold">{backlog.scoresPending}</p>
          </div>
          <div className="rounded-lg border border-slate-200 bg-white p-3 text-sm">
            <p className="text-slate-600">{t("commentsPending")}</p>
            <p className="text-lg font-semibold">{backlog.commentsPending}</p>
          </div>
          <div className="rounded-lg border border-slate-200 bg-white p-3 text-sm">
            <p className="text-slate-600">{t("translationPending")}</p>
            <p className="text-lg font-semibold">{backlog.translationPending}</p>
          </div>
        </div>
      ) : null}

      <div className="grid gap-4 lg:grid-cols-2">
        {(await can("attendance.review")) ? (
          <AcademicReviewQueuePanel
            title={t("attendanceAwaitingReview")}
            items={attendancePending.items}
            emptyLabel={t("queueEmpty")}
            viewLabel={t("viewDetail")}
          />
        ) : null}
        {(await can("assessment_result.review")) ? (
          <AcademicReviewQueuePanel
            title={t("scoresAwaitingReview")}
            items={scoresPending.items}
            emptyLabel={t("queueEmpty")}
            viewLabel={t("viewDetail")}
          />
        ) : null}
        {(await can("observation.review")) ? (
          <AcademicReviewQueuePanel
            title={t("commentsAwaitingReview")}
            items={commentsPending.items}
            emptyLabel={t("queueEmpty")}
            viewLabel={t("viewDetail")}
          />
        ) : null}
        {(await can("observation.review")) ? (
          <AcademicReviewQueuePanel
            title={t("commentsAwaitingTranslation")}
            items={translationPending.items}
            emptyLabel={t("queueEmpty")}
            viewLabel={t("viewDetail")}
          />
        ) : null}
        <AcademicReviewQueuePanel
          title={t("incompleteSessionRecords")}
          items={incompleteSessions.items}
          emptyLabel={t("queueEmpty")}
          viewLabel={t("viewDetail")}
        />
      </div>
    </div>
  );
}
