import { getTranslations } from "next-intl/server";
import type { LeadStatus } from "@/lib/leads/constants";

type Props = {
  status: LeadStatus;
};

export async function LeadStatusBadge({ status }: Props) {
  const t = await getTranslations("status.lead");
  return (
    <span className="inline-flex rounded-full bg-slate-100 px-2.5 py-0.5 text-xs font-medium text-slate-800">
      {t(status)}
    </span>
  );
}
