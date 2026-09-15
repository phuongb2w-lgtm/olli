import { getTranslations } from "next-intl/server";
import type { ObservationIndicator } from "@/lib/session-execution/query-session-execution";

type Props = {
  comment: string | null;
  ratings: Record<string, string>;
  indicators: ObservationIndicator[];
};

export async function ObservationSummary({ comment, ratings, indicators }: Props) {
  const t = await getTranslations("sessionExecution");
  const tIndicator = await getTranslations("observationIndicators");
  const tRating = await getTranslations("observationRatings");

  const hasContent =
    Boolean(comment?.trim()) || Object.keys(ratings).length > 0;
  if (!hasContent) {
    return <span className="text-slate-500">{t("noObservation")}</span>;
  }

  return (
    <div className="space-y-1 text-sm text-slate-700">
      {indicators.map((indicator) =>
        ratings[indicator.code] ? (
          <p key={indicator.code}>
            {tIndicator(indicator.code)}: {tRating(ratings[indicator.code])}
          </p>
        ) : null,
      )}
      {comment?.trim() ? (
        <p className="text-slate-600">{comment}</p>
      ) : null}
    </div>
  );
}
