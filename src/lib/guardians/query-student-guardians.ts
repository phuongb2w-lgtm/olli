import type { SupabaseClient } from "@supabase/supabase-js";
import type { RelationshipType } from "@/lib/guardians/constants";
import { formatPersonName } from "@/lib/students/format-person-name";

export type StudentGuardianLinkItem = {
  linkId: string;
  guardianId: string;
  guardianName: string;
  familyName: string;
  givenName: string;
  phone: string | null;
  email: string | null;
  guardianStatus: string;
  relationshipType: RelationshipType;
  isPrimaryContact: boolean;
  isBillingContact: boolean;
  linkStatus: string;
};

export type StudentGuardianList = {
  active: StudentGuardianLinkItem[];
  ended: StudentGuardianLinkItem[];
};

type LinkRow = {
  id: string;
  guardian_id: string;
  relationship_type: string;
  is_primary_contact: boolean;
  is_billing_contact: boolean;
  status: string;
};

type GuardianRow = {
  id: string;
  given_name: string;
  family_name: string;
  phone: string | null;
  email: string | null;
  status: string;
};

export async function queryStudentGuardians(
  supabase: SupabaseClient,
  studentId: string,
): Promise<StudentGuardianList> {
  const { data: links, error: linkError } = await supabase
    .from("student_guardian")
    .select("id, guardian_id, relationship_type, is_primary_contact, is_billing_contact, status")
    .eq("student_id", studentId)
    .order("status", { ascending: true })
    .order("created_at", { ascending: true });

  if (linkError) throw linkError;

  const linkRows = (links ?? []) as LinkRow[];
  const guardianIds = [...new Set(linkRows.map((link) => link.guardian_id))];

  const guardianById = new Map<string, GuardianRow>();
  if (guardianIds.length > 0) {
    const { data: guardians, error: guardianError } = await supabase
      .from("guardian")
      .select("id, given_name, family_name, phone, email, status")
      .in("id", guardianIds);

    if (guardianError) throw guardianError;

    for (const guardian of guardians ?? []) {
      guardianById.set(guardian.id, guardian as GuardianRow);
    }
  }

  const active: StudentGuardianLinkItem[] = [];
  const ended: StudentGuardianLinkItem[] = [];

  for (const link of linkRows) {
    const guardian = guardianById.get(link.guardian_id);
    if (!guardian) continue;

    const item: StudentGuardianLinkItem = {
      linkId: link.id,
      guardianId: guardian.id,
      guardianName: formatPersonName(guardian.family_name, guardian.given_name),
      familyName: guardian.family_name,
      givenName: guardian.given_name,
      phone: guardian.phone,
      email: guardian.email,
      guardianStatus: guardian.status,
      relationshipType: link.relationship_type as RelationshipType,
      isPrimaryContact: link.is_primary_contact,
      isBillingContact: link.is_billing_contact,
      linkStatus: link.status,
    };

    if (link.status === "active") {
      active.push(item);
    } else {
      ended.push(item);
    }
  }

  return { active, ended };
}
