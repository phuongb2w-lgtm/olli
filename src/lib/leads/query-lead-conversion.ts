import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "@/types/database";

type DbClient = SupabaseClient<Database>;

export type LeadConversionCandidate = {
  leadCandidateId: string;
  studentId: string;
  resolutionMode: string;
  wasCreated: boolean;
  studentName: string | null;
};

export type LeadConversionContact = {
  leadContactId: string;
  guardianId: string;
  resolutionMode: string;
  wasCreated: boolean;
  guardianName: string | null;
};

export type LeadConversionRelationship = {
  leadCandidateId: string;
  leadContactId: string;
  studentId: string;
  guardianId: string;
  studentGuardianId: string;
  relationshipType: string;
  isPrimaryContact: boolean;
  isBillingContact: boolean;
};

export type LeadConversionEnrollment = {
  leadCandidateId: string;
  enrollmentId: string;
  classId: string;
  className: string | null;
};

export type LeadConversionDetail = {
  id: string;
  convertedAt: string;
  convertedByName: string | null;
  candidates: LeadConversionCandidate[];
  contacts: LeadConversionContact[];
  relationships: LeadConversionRelationship[];
  enrollments: LeadConversionEnrollment[];
};

export async function queryLeadConversion(
  supabase: DbClient,
  leadId: string,
): Promise<{ conversion: LeadConversionDetail | null; error: boolean }> {
  const { data: conversion, error } = await supabase
    .from("lead_conversion")
    .select("id, converted_at, converted_by")
    .eq("lead_id", leadId)
    .maybeSingle();

  if (error) {
    return { conversion: null, error: true };
  }
  if (!conversion) {
    return { conversion: null, error: false };
  }

  const [candidates, contacts, relationships, enrollments, actor] = await Promise.all([
    supabase
      .from("lead_conversion_candidate")
      .select("lead_candidate_id, student_id, resolution_mode, was_created")
      .eq("lead_conversion_id", conversion.id),
    supabase
      .from("lead_conversion_contact")
      .select("lead_contact_id, guardian_id, resolution_mode, was_created")
      .eq("lead_conversion_id", conversion.id),
    supabase
      .from("lead_conversion_student_guardian")
      .select(
        "lead_candidate_id, lead_contact_id, student_id, guardian_id, student_guardian_id, relationship_type, is_primary_contact, is_billing_contact",
      )
      .eq("lead_conversion_id", conversion.id),
    supabase
      .from("lead_conversion_enrollment")
      .select("lead_candidate_id, enrollment_id, class_id")
      .eq("lead_conversion_id", conversion.id),
    supabase.from("app_user").select("display_name").eq("id", conversion.converted_by).maybeSingle(),
  ]);

  const studentIds = (candidates.data ?? []).map((c) => c.student_id);
  const guardianIds = (contacts.data ?? []).map((c) => c.guardian_id);
  const classIds = (enrollments.data ?? []).map((e) => e.class_id);

  const [students, guardians, classes] = await Promise.all([
    studentIds.length
      ? supabase.from("student").select("id, given_name, family_name").in("id", studentIds)
      : Promise.resolve({ data: [] as { id: string; given_name: string; family_name: string }[] }),
    guardianIds.length
      ? supabase.from("guardian").select("id, given_name, family_name").in("id", guardianIds)
      : Promise.resolve({ data: [] as { id: string; given_name: string; family_name: string }[] }),
    classIds.length
      ? supabase.from("class").select("id, name").in("id", classIds)
      : Promise.resolve({ data: [] as { id: string; name: string }[] }),
  ]);

  const studentMap = new Map(
    (students.data ?? []).map((s) => [s.id, `${s.given_name} ${s.family_name}`]),
  );
  const guardianMap = new Map(
    (guardians.data ?? []).map((g) => [g.id, `${g.given_name} ${g.family_name}`]),
  );
  const classMap = new Map((classes.data ?? []).map((c) => [c.id, c.name]));

  return {
    conversion: {
      id: conversion.id,
      convertedAt: conversion.converted_at,
      convertedByName: actor.data?.display_name ?? null,
      candidates: (candidates.data ?? []).map((c) => ({
        leadCandidateId: c.lead_candidate_id,
        studentId: c.student_id,
        resolutionMode: c.resolution_mode,
        wasCreated: c.was_created,
        studentName: studentMap.get(c.student_id) ?? null,
      })),
      contacts: (contacts.data ?? []).map((c) => ({
        leadContactId: c.lead_contact_id,
        guardianId: c.guardian_id,
        resolutionMode: c.resolution_mode,
        wasCreated: c.was_created,
        guardianName: guardianMap.get(c.guardian_id) ?? null,
      })),
      relationships: (relationships.data ?? []).map((r) => ({
        leadCandidateId: r.lead_candidate_id,
        leadContactId: r.lead_contact_id,
        studentId: r.student_id,
        guardianId: r.guardian_id,
        studentGuardianId: r.student_guardian_id,
        relationshipType: r.relationship_type,
        isPrimaryContact: r.is_primary_contact,
        isBillingContact: r.is_billing_contact,
      })),
      enrollments: (enrollments.data ?? []).map((e) => ({
        leadCandidateId: e.lead_candidate_id,
        enrollmentId: e.enrollment_id,
        classId: e.class_id,
        className: classMap.get(e.class_id) ?? null,
      })),
    },
    error: false,
  };
}
