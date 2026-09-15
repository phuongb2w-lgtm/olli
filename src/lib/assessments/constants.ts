export const ASSESSMENT_STATUSES = ["draft", "open", "closed"] as const;
export type AssessmentStatus = (typeof ASSESSMENT_STATUSES)[number];

export const ASSESSMENT_TYPE_CODES = ["progress_test", "checkpoint", "end_of_course"] as const;
export type AssessmentTypeCode = (typeof ASSESSMENT_TYPE_CODES)[number];

export const RESULT_STATUSES = ["draft", "finalized", "corrected"] as const;
export type ResultStatus = (typeof RESULT_STATUSES)[number];
