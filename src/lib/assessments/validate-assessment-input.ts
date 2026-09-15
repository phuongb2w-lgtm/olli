import {
  ASSESSMENT_STATUSES,
  ASSESSMENT_TYPE_CODES,
  type AssessmentStatus,
  type AssessmentTypeCode,
} from "./constants";

export type AssessmentFieldErrors = {
  title?: "required";
  assessedOn?: "required" | "invalid";
  maxScore?: "required" | "invalid";
  assessmentTypeCode?: "invalid";
  status?: "invalid";
};

export function validateAssessmentInput(input: {
  title?: string;
  assessedOn?: string;
  maxScore?: string;
  assessmentTypeCode?: string;
  status?: string;
}): { ok: true; value: {
  title: string;
  assessedOn: string;
  maxScore: number;
  assessmentTypeCode: AssessmentTypeCode;
  status: AssessmentStatus;
} } | { ok: false; fieldErrors: AssessmentFieldErrors } {
  const fieldErrors: AssessmentFieldErrors = {};
  const title = (input.title ?? "").trim();
  const assessedOn = (input.assessedOn ?? "").trim();
  const maxScoreRaw = (input.maxScore ?? "").trim();
  const typeRaw = (input.assessmentTypeCode ?? "progress_test").trim();
  const statusRaw = (input.status ?? "open").trim();

  if (!title) fieldErrors.title = "required";
  if (!assessedOn) fieldErrors.assessedOn = "required";
  else if (!/^\d{4}-\d{2}-\d{2}$/.test(assessedOn)) fieldErrors.assessedOn = "invalid";

  const maxScore = Number(maxScoreRaw);
  if (!maxScoreRaw || Number.isNaN(maxScore)) fieldErrors.maxScore = "required";
  else if (maxScore <= 0) fieldErrors.maxScore = "invalid";

  if (!ASSESSMENT_TYPE_CODES.includes(typeRaw as AssessmentTypeCode)) {
    fieldErrors.assessmentTypeCode = "invalid";
  }
  if (!ASSESSMENT_STATUSES.includes(statusRaw as AssessmentStatus)) {
    fieldErrors.status = "invalid";
  }

  if (Object.keys(fieldErrors).length > 0) return { ok: false, fieldErrors };

  return {
    ok: true,
    value: {
      title,
      assessedOn,
      maxScore,
      assessmentTypeCode: typeRaw as AssessmentTypeCode,
      status: statusRaw as AssessmentStatus,
    },
  };
}

export function validateScoreInput(rawScoreRaw: string, maxScore: number): {
  ok: true;
  rawScore: number;
} | {
  ok: false;
  error: "required" | "invalid" | "exceeds_max";
} {
  const trimmed = rawScoreRaw.trim();
  if (!trimmed) return { ok: false, error: "required" };
  const rawScore = Number(trimmed);
  if (Number.isNaN(rawScore) || rawScore < 0) return { ok: false, error: "invalid" };
  if (rawScore > maxScore) return { ok: false, error: "exceeds_max" };
  return { ok: true, rawScore };
}
