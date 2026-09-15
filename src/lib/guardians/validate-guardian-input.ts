import {
  GUARDIAN_EMAIL_MAX_LENGTH,
  GUARDIAN_PHONE_MAX_LENGTH,
  GUARDIAN_STATUSES,
  RELATIONSHIP_TYPES,
  type GuardianStatus,
  type RelationshipType,
} from "@/lib/guardians/constants";
import { normalizeGuardianEmail, normalizeOptionalText } from "@/lib/guardians/normalize-guardian-fields";

export type GuardianFieldErrors = Partial<
  Record<"familyName" | "givenName" | "phone" | "email" | "status" | "relationshipType", string>
>;

export type ValidatedGuardianInput = {
  familyName: string;
  givenName: string;
  phone: string | null;
  email: string | null;
  status: GuardianStatus;
};

export type ValidatedLinkInput = {
  relationshipType: RelationshipType;
  isPrimaryContact: boolean;
  isBillingContact: boolean;
};

export type GuardianValidationResult =
  | { ok: true; data: ValidatedGuardianInput }
  | { ok: false; fieldErrors: GuardianFieldErrors };

export type LinkValidationResult =
  | { ok: true; data: ValidatedLinkInput }
  | { ok: false; fieldErrors: GuardianFieldErrors };

function trimName(value: string): string {
  return value.trim();
}

function isValidEmail(value: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value);
}

export function validateGuardianInput(input: {
  familyName: string;
  givenName: string;
  phone?: string | null;
  email?: string | null;
  status?: string | null;
}): GuardianValidationResult {
  const fieldErrors: GuardianFieldErrors = {};

  const familyName = trimName(input.familyName ?? "");
  const givenName = trimName(input.givenName ?? "");

  if (!familyName) fieldErrors.familyName = "required";
  if (!givenName) fieldErrors.givenName = "required";

  const phone = normalizeOptionalText(input.phone ?? null);
  if (phone && phone.length > GUARDIAN_PHONE_MAX_LENGTH) {
    fieldErrors.phone = "tooLong";
  }

  const email = normalizeGuardianEmail(input.email ?? null);
  if (email) {
    if (email.length > GUARDIAN_EMAIL_MAX_LENGTH || !isValidEmail(email)) {
      fieldErrors.email = "invalid";
    }
  }

  const rawStatus = (input.status ?? "active").trim();
  const status = rawStatus as GuardianStatus;
  if (!GUARDIAN_STATUSES.includes(status)) {
    fieldErrors.status = "invalid";
  }

  if (Object.keys(fieldErrors).length > 0) {
    return { ok: false, fieldErrors };
  }

  return {
    ok: true,
    data: { familyName, givenName, phone, email, status },
  };
}

export function validateLinkInput(input: {
  relationshipType: string;
  isPrimaryContact?: boolean;
  isBillingContact?: boolean;
}): LinkValidationResult {
  const fieldErrors: GuardianFieldErrors = {};
  const relationshipType = input.relationshipType.trim() as RelationshipType;

  if (!RELATIONSHIP_TYPES.includes(relationshipType)) {
    fieldErrors.relationshipType = "invalid";
  }

  if (Object.keys(fieldErrors).length > 0) {
    return { ok: false, fieldErrors };
  }

  return {
    ok: true,
    data: {
      relationshipType,
      isPrimaryContact: Boolean(input.isPrimaryContact),
      isBillingContact: Boolean(input.isBillingContact),
    },
  };
}
