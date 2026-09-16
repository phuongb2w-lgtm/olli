export type RecognitionStageInput = {
  sequenceNumber: number;
  amount: number;
  assessmentId?: string | null;
  label?: string | null;
};

export type SetRecognitionStagesInput = {
  termsId: string;
  stages: RecognitionStageInput[];
};

type ValidationFailure = { ok: false; fieldErrors: Record<string, string> };

export type SetRecognitionStagesValidationResult =
  | { ok: true; data: { termsId: string; stages: RecognitionStageInput[] } }
  | ValidationFailure;

function parseUuid(value: unknown): string | null {
  const s = String(value ?? "").trim();
  if (!/^[0-9a-f-]{36}$/i.test(s)) return null;
  return s;
}

function parsePositiveInt(value: unknown): number | null {
  const n = typeof value === "number" ? value : Number(String(value ?? "").trim());
  if (!Number.isFinite(n) || !Number.isInteger(n) || n <= 0) return null;
  return n;
}

export function validateSetRecognitionStagesInput(
  input: SetRecognitionStagesInput,
): SetRecognitionStagesValidationResult {
  const fieldErrors: Record<string, string> = {};
  const termsId = parseUuid(input.termsId);
  if (!termsId) fieldErrors.termsId = "invalid";

  if (!Array.isArray(input.stages) || input.stages.length === 0) {
    fieldErrors.stages = "invalid";
  } else {
    for (const stage of input.stages) {
      if (parsePositiveInt(stage.sequenceNumber) == null || parsePositiveInt(stage.amount) == null) {
        fieldErrors.stages = "invalid";
        break;
      }
      if (stage.assessmentId && !parseUuid(stage.assessmentId)) {
        fieldErrors.stages = "invalid";
        break;
      }
    }
  }

  if (Object.keys(fieldErrors).length > 0) {
    return { ok: false, fieldErrors };
  }

  return { ok: true, data: { termsId: termsId!, stages: input.stages } };
}

export function validateLessonCount(value: unknown): number | null {
  return parsePositiveInt(value);
}
