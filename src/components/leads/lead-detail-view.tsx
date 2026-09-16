import { getTranslations } from "next-intl/server";
import { LeadAssignmentPanel } from "@/components/leads/lead-assignment-panel";
import { LeadDetailActions } from "@/components/leads/lead-detail-actions";
import { LeadStatusBadge } from "@/components/leads/lead-status-badge";
import type { EligibleAssignee } from "@/lib/leads/query-eligible-assignees";
import type { LeadDetail } from "@/lib/leads/query-lead-detail";

type Props = {
  detail: LeadDetail;
  canUpdate: boolean;
  canAssign: boolean;
  assignees: EligibleAssignee[];
};

function formatDateTime(value: string | null): string {
  if (!value) return "—";
  return new Date(value).toLocaleString();
}

export async function LeadDetailView({ detail, canUpdate, canAssign, assignees }: Props) {
  const t = await getTranslations("crm.detail");
  const tActivity = await getTranslations("activity.lead");
  const tStatus = await getTranslations("status.lead");
  const tAssignment = await getTranslations("crm.assignment");
  const tFollowUp = await getTranslations("crm.followUp");

  const pendingFollowUps = detail.followUps
    .filter((f) => f.status === "pending")
    .map((f) => ({ id: f.id, dueAt: f.dueAt, note: f.note }));

  return (
    <div className="space-y-6">
      <section className="rounded-lg border border-slate-200 bg-white p-4">
        <div className="flex flex-wrap items-center gap-3">
          <h1 className="text-xl font-semibold text-slate-900">{t("title")}</h1>
          <LeadStatusBadge status={detail.status} />
        </div>
        <dl className="mt-4 grid gap-3 text-sm sm:grid-cols-2">
          <div>
            <dt className="font-medium text-slate-600">{t("source")}</dt>
            <dd className="text-slate-900">{detail.sourceLabel ?? "—"}</dd>
          </div>
          <div>
            <dt className="font-medium text-slate-600">{t("campaign")}</dt>
            <dd className="text-slate-900">{detail.campaignName ?? "—"}</dd>
          </div>
          <div>
            <dt className="font-medium text-slate-600">{t("assignedUser")}</dt>
            <dd className="text-slate-900">
              {detail.assignedUserName ?? tAssignment("unassignedLabel")}
            </dd>
          </div>
          <div>
            <dt className="font-medium text-slate-600">{t("createdAt")}</dt>
            <dd className="text-slate-900">{formatDateTime(detail.createdAt)}</dd>
          </div>
          {detail.lostReasonLabel ? (
            <>
              <div>
                <dt className="font-medium text-slate-600">{t("lastLostReason")}</dt>
                <dd className="text-slate-900">{detail.lostReasonLabel}</dd>
              </div>
              <div>
                <dt className="font-medium text-slate-600">{t("lastLostAt")}</dt>
                <dd className="text-slate-900">{formatDateTime(detail.lostAt)}</dd>
              </div>
            </>
          ) : null}
        </dl>
        {detail.notesSummary ? (
          <p className="mt-4 text-sm text-slate-700">{detail.notesSummary}</p>
        ) : null}
      </section>

      <div className="grid gap-6 lg:grid-cols-2">
        <section className="rounded-lg border border-slate-200 bg-white p-4">
          <h2 className="text-base font-semibold text-slate-900">{t("candidates")}</h2>
          <ul className="mt-3 space-y-2 text-sm">
            {detail.candidates.map((c) => (
              <li key={c.id} className="text-slate-800">
                {c.displayName}
                {c.isPrimaryCandidate ? ` (${t("primary")})` : ""}
              </li>
            ))}
            {detail.candidates.length === 0 ? (
              <li className="text-slate-500">{t("emptyCandidates")}</li>
            ) : null}
          </ul>
        </section>

        <section className="rounded-lg border border-slate-200 bg-white p-4">
          <h2 className="text-base font-semibold text-slate-900">{t("contacts")}</h2>
          <ul className="mt-3 space-y-2 text-sm">
            {detail.contacts.map((c) => (
              <li key={c.id} className="text-slate-800">
                <div>{c.displayName}</div>
                <div className="text-slate-600">
                  {[c.phone, c.email].filter(Boolean).join(" · ") || "—"}
                </div>
              </li>
            ))}
            {detail.contacts.length === 0 ? (
              <li className="text-slate-500">{t("emptyContacts")}</li>
            ) : null}
          </ul>
        </section>
      </div>

      <LeadAssignmentPanel
        leadId={detail.id}
        assignedUserId={detail.assignedUserId}
        assignedUserName={detail.assignedUserName}
        assignees={assignees}
        assignmentHistory={detail.assignmentHistory}
        canAssign={canAssign}
      />

      <LeadDetailActions
        leadId={detail.id}
        status={detail.status}
        lostReasons={detail.lostReasons}
        pendingFollowUps={pendingFollowUps}
        canUpdate={canUpdate}
      />

      <section className="rounded-lg border border-slate-200 bg-white p-4">
        <h2 className="text-base font-semibold text-slate-900">{t("timeline")}</h2>
        {detail.timeline.length === 0 ? (
          <p className="mt-3 text-sm text-slate-500">{t("emptyTimeline")}</p>
        ) : (
          <ol className="mt-4 space-y-4">
            {detail.timeline.map((entry) => (
              <li
                key={`${entry.kind}-${
                  entry.kind === "activity"
                    ? entry.activity.id
                    : entry.kind === "status"
                      ? entry.status.id
                      : entry.assignment.id
                }`}
                className="border-l-2 border-slate-200 pl-4"
              >
                <p className="text-xs text-slate-500">{formatDateTime(entry.occurredAt)}</p>
                {entry.kind === "activity" ? (
                  <p className="text-sm text-slate-900">
                    <span className="font-medium">{tActivity(entry.activity.activityType)}</span>
                    {entry.activity.content ? `: ${entry.activity.content}` : ""}
                  </p>
                ) : entry.kind === "status" ? (
                  <p className="text-sm text-slate-900">
                    {entry.status.fromStatus
                      ? `${tStatus(entry.status.fromStatus)} → ${tStatus(entry.status.toStatus)}`
                      : tStatus(entry.status.toStatus)}
                    {entry.status.notes ? ` — ${entry.status.notes}` : ""}
                  </p>
                ) : (
                  <p className="text-sm text-slate-900">
                    {tAssignment("historyEntry", {
                      from: entry.assignment.previousAssigneeName ?? tAssignment("unassignedLabel"),
                      to: entry.assignment.newAssigneeName ?? tAssignment("unassignedLabel"),
                    })}
                    {entry.assignment.note ? ` — ${entry.assignment.note}` : ""}
                  </p>
                )}
              </li>
            ))}
          </ol>
        )}
      </section>

      <section className="rounded-lg border border-slate-200 bg-white p-4">
        <h2 className="text-base font-semibold text-slate-900">{t("followUps")}</h2>
        <ul className="mt-3 space-y-2 text-sm">
          {detail.followUps.map((f) => (
            <li key={f.id} className="text-slate-800">
              {formatDateTime(f.dueAt)} — {tFollowUp(f.status)}
              {f.note ? `: ${f.note}` : ""}
              {f.assignedUserName ? ` (${tAssignment("followUpOwner", { name: f.assignedUserName })})` : ""}
            </li>
          ))}
          {detail.followUps.length === 0 ? (
            <li className="text-slate-500">{t("emptyFollowUps")}</li>
          ) : null}
        </ul>
      </section>
    </div>
  );
}
