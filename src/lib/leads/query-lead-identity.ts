import type { SupabaseClient } from "@supabase/supabase-js";
import { fetchAppUserIdentityLabels } from "@/lib/identity/fetch-app-user-identity-labels";
import { formatPersonName } from "@/lib/leads/format-person-name";
import type { Database } from "@/types/database";

type DbClient = SupabaseClient<Database>;

export type IdentityMatchConfidence = "strong" | "possible";

export type StudentIdentityMatch = {
  studentId: string;
  displayName: string;
  dateOfBirth: string | null;
  studentCode: string | null;
  status: string;
  confidence: IdentityMatchConfidence;
  matchReasons: string[];
};

export type GuardianIdentityMatch = {
  guardianId: string;
  displayName: string;
  phone: string | null;
  email: string | null;
  status: string;
  confidence: IdentityMatchConfidence;
  matchReasons: string[];
};

export type CandidateIdentityResolution = {
  resolutionMode: "use_existing" | "create_new" | null;
  studentId: string | null;
  studentDisplayName: string | null;
  isStale: boolean;
  strongMatchAcknowledged: boolean;
};

export type ContactIdentityResolution = {
  resolutionMode: "use_existing" | "create_new" | null;
  guardianId: string | null;
  guardianDisplayName: string | null;
  isStale: boolean;
  strongMatchAcknowledged: boolean;
};

export type IdentityResolutionEventDetail = {
  id: string;
  subjectType: "candidate" | "contact";
  subjectId: string;
  previousResolutionMode: string | null;
  newResolutionMode: string | null;
  changedAt: string;
  changedByName: string | null;
  note: string | null;
};

export type LeadIdentityBundle = {
  readiness: {
    ready: boolean;
    unresolvedCandidates: number;
    unresolvedContacts: number;
    staleCount: number;
    ineligibleTargetCount: number;
  };
  candidateMatches: Record<string, StudentIdentityMatch[]>;
  contactMatches: Record<string, GuardianIdentityMatch[]>;
  candidateResolutions: Record<string, CandidateIdentityResolution>;
  contactResolutions: Record<string, ContactIdentityResolution>;
  events: IdentityResolutionEventDetail[];
};

type StudentMatchRow = {
  student_id: string;
  given_name: string;
  family_name: string;
  date_of_birth: string | null;
  student_code: string | null;
  status: string;
  match_confidence: string;
  match_reasons: string[];
};

type GuardianMatchRow = {
  guardian_id: string;
  given_name: string;
  family_name: string;
  phone: string | null;
  email: string | null;
  status: string;
  match_confidence: string;
  match_reasons: string[];
};

function mapStudentMatch(m: StudentMatchRow): StudentIdentityMatch {
  return {
    studentId: m.student_id,
    displayName: formatPersonName(m.given_name, m.family_name),
    dateOfBirth: m.date_of_birth,
    studentCode: m.student_code,
    status: m.status,
    confidence: m.match_confidence as IdentityMatchConfidence,
    matchReasons: m.match_reasons ?? [],
  };
}

function mapGuardianMatch(m: GuardianMatchRow): GuardianIdentityMatch {
  return {
    guardianId: m.guardian_id,
    displayName: formatPersonName(m.given_name, m.family_name),
    phone: m.phone,
    email: m.email,
    status: m.status,
    confidence: m.match_confidence as IdentityMatchConfidence,
    matchReasons: m.match_reasons ?? [],
  };
}

export async function queryLeadIdentity(
  supabase: DbClient,
  leadId: string,
  candidateIds: string[],
  contactIds: string[],
): Promise<{ bundle: LeadIdentityBundle | null; error: boolean }> {
  const [statusResult, candidateResolutionRows, contactResolutionRows] = await Promise.all([
    supabase.rpc("get_lead_identity_resolution_status", { p_lead_id: leadId }),
    candidateIds.length
      ? supabase
          .from("lead_candidate_identity_resolution")
          .select(
            "lead_candidate_id, resolution_mode, student_id, is_stale, strong_match_acknowledged",
          )
          .in("lead_candidate_id", candidateIds)
      : Promise.resolve({ data: [], error: null }),
    contactIds.length
      ? supabase
          .from("lead_contact_identity_resolution")
          .select(
            "lead_contact_id, resolution_mode, guardian_id, is_stale, strong_match_acknowledged",
          )
          .in("lead_contact_id", contactIds)
      : Promise.resolve({ data: [], error: null }),
  ]);

  if (statusResult.error || candidateResolutionRows.error || contactResolutionRows.error) {
    return { bundle: null, error: true };
  }

  const candidateMatches: Record<string, StudentIdentityMatch[]> = {};
  for (const id of candidateIds) {
    const { data, error } = await supabase.rpc("find_student_matches_for_lead_candidate", {
      p_lead_candidate_id: id,
    });
    if (error) return { bundle: null, error: true };
    candidateMatches[id] = ((data ?? []) as StudentMatchRow[]).map(mapStudentMatch);
  }

  const contactMatches: Record<string, GuardianIdentityMatch[]> = {};
  for (const id of contactIds) {
    const { data, error } = await supabase.rpc("find_guardian_matches_for_lead_contact", {
      p_lead_contact_id: id,
    });
    if (error) return { bundle: null, error: true };
    contactMatches[id] = ((data ?? []) as GuardianMatchRow[]).map(mapGuardianMatch);
  }

  const candidateResolutions: Record<string, CandidateIdentityResolution> = {};
  for (const row of candidateResolutionRows.data ?? []) {
    const match = candidateMatches[row.lead_candidate_id]?.find(
      (m) => m.studentId === row.student_id,
    );
    candidateResolutions[row.lead_candidate_id] = {
      resolutionMode: row.resolution_mode as "use_existing" | "create_new",
      studentId: row.student_id,
      studentDisplayName: match?.displayName ?? null,
      isStale: row.is_stale,
      strongMatchAcknowledged: row.strong_match_acknowledged,
    };
  }

  const contactResolutions: Record<string, ContactIdentityResolution> = {};
  for (const row of contactResolutionRows.data ?? []) {
    const match = contactMatches[row.lead_contact_id]?.find(
      (m) => m.guardianId === row.guardian_id,
    );
    contactResolutions[row.lead_contact_id] = {
      resolutionMode: row.resolution_mode as "use_existing" | "create_new",
      guardianId: row.guardian_id,
      guardianDisplayName: match?.displayName ?? null,
      isStale: row.is_stale,
      strongMatchAcknowledged: row.strong_match_acknowledged,
    };
  }

  let events: IdentityResolutionEventDetail[] = [];
  const subjectIds = [...candidateIds, ...contactIds];
  if (subjectIds.length) {
    const { data: eventRows, error: eventsError } = await supabase
      .from("lead_identity_resolution_event")
      .select(
        "id, subject_type, subject_id, previous_resolution_mode, new_resolution_mode, changed_at, changed_by, note",
      )
      .in("subject_id", subjectIds)
      .order("changed_at", { ascending: false });

    if (eventsError) {
      return { bundle: null, error: true };
    }

    const actorIds = new Set(
      (eventRows ?? []).map((e) => e.changed_by).filter(Boolean) as string[],
    );
    const actorLabels = actorIds.size
      ? await fetchAppUserIdentityLabels(supabase, [...actorIds])
      : new Map();
    const actorMap = new Map([...actorLabels.entries()].map(([id, a]) => [id, a.displayName]));

    events = (eventRows ?? []).map((e) => ({
      id: e.id,
      subjectType: e.subject_type as "candidate" | "contact",
      subjectId: e.subject_id,
      previousResolutionMode: e.previous_resolution_mode,
      newResolutionMode: e.new_resolution_mode,
      changedAt: e.changed_at,
      changedByName: actorMap.get(e.changed_by) ?? null,
      note: e.note,
    }));
  }

  const status = statusResult.data as {
    ready: boolean;
    unresolved_candidates: number;
    unresolved_contacts: number;
    stale_count: number;
    ineligible_target_count: number;
  };

  return {
    bundle: {
      readiness: {
        ready: status.ready,
        unresolvedCandidates: status.unresolved_candidates,
        unresolvedContacts: status.unresolved_contacts,
        staleCount: status.stale_count,
        ineligibleTargetCount: status.ineligible_target_count,
      },
      candidateMatches,
      contactMatches,
      candidateResolutions,
      contactResolutions,
      events,
    },
    error: false,
  };
}
