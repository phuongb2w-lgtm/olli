-- M5-T03.1: Preserve M1 finalized → corrected score edit path.

CREATE OR REPLACE FUNCTION protect_reviewed_assessment_result()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF current_setting('olli.academic_review_mutation', true) = 'true' THEN
    RETURN NEW;
  END IF;

  -- M1 semantic: explicit correction transition may change scores.
  IF TG_OP = 'UPDATE'
     AND OLD.status = 'finalized'
     AND NEW.status IN ('corrected', 'returned') THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE'
     AND OLD.status IN ('submitted', 'finalized')
     AND NEW.status IN ('submitted', 'finalized')
     AND (
       OLD.raw_score IS DISTINCT FROM NEW.raw_score
       OR OLD.max_score IS DISTINCT FROM NEW.max_score
     ) THEN
    RAISE EXCEPTION 'assessment_result_not_editable' USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION protect_reviewed_assessment_result() IS
  'Blocks teacher edits on submitted/finalized scores. M1 corrected transition remains explicit and auditable.';
