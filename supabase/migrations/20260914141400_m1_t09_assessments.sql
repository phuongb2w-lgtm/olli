-- M1-T09: Assessment result integrity, audit columns, correction workflow.

ALTER TABLE assessment
  ADD COLUMN updated_by uuid;

ALTER TABLE assessment
  ADD CONSTRAINT assessment_created_by_fk
  FOREIGN KEY (organization_id, created_by) REFERENCES app_user (organization_id, id),
  ADD CONSTRAINT assessment_updated_by_fk
  FOREIGN KEY (organization_id, updated_by) REFERENCES app_user (organization_id, id);

ALTER TABLE assessment_result
  ADD COLUMN updated_by uuid;

ALTER TABLE assessment_result
  ADD CONSTRAINT assessment_result_recorded_by_fk
  FOREIGN KEY (organization_id, recorded_by) REFERENCES app_user (organization_id, id),
  ADD CONSTRAINT assessment_result_updated_by_fk
  FOREIGN KEY (organization_id, updated_by) REFERENCES app_user (organization_id, id);

CREATE OR REPLACE FUNCTION protect_finalized_assessment_result()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF OLD.status = 'finalized'
     AND NEW.status = 'finalized'
     AND (
       OLD.raw_score IS DISTINCT FROM NEW.raw_score
       OR OLD.max_score IS DISTINCT FROM NEW.max_score
     ) THEN
    RAISE EXCEPTION 'Cannot modify scores on a finalized assessment result';
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION validate_assessment_result_context()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  asm_class_id uuid;
  asm_org_id uuid;
  asm_date date;
  enr_class_id uuid;
  enr_start date;
  enr_end date;
  enr_status text;
BEGIN
  SELECT a.class_id, a.organization_id, a.assessed_on
    INTO asm_class_id, asm_org_id, asm_date
  FROM assessment a
  WHERE a.id = NEW.assessment_id;

  IF asm_class_id IS NULL THEN
    RAISE EXCEPTION 'invalid_assessment_reference';
  END IF;

  IF NEW.organization_id IS DISTINCT FROM asm_org_id THEN
    RAISE EXCEPTION 'assessment_org_mismatch';
  END IF;

  SELECT e.class_id, e.start_date, e.end_date, e.status
    INTO enr_class_id, enr_start, enr_end, enr_status
  FROM enrollment e
  WHERE e.id = NEW.enrollment_id;

  IF enr_class_id IS NULL THEN
    RAISE EXCEPTION 'invalid_enrollment_reference';
  END IF;

  IF enr_class_id IS DISTINCT FROM asm_class_id THEN
    RAISE EXCEPTION 'assessment_class_mismatch';
  END IF;

  IF enr_start > asm_date THEN
    RAISE EXCEPTION 'enrollment_not_eligible';
  END IF;

  IF enr_end IS NOT NULL AND enr_end < asm_date THEN
    RAISE EXCEPTION 'enrollment_not_eligible';
  END IF;

  IF enr_status = 'pending' THEN
    RAISE EXCEPTION 'pending_enrollment';
  END IF;

  IF NEW.max_score <= 0 THEN
    RAISE EXCEPTION 'invalid_max_score';
  END IF;

  IF NEW.raw_score < 0 OR NEW.raw_score > NEW.max_score THEN
    RAISE EXCEPTION 'invalid_raw_score';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER assessment_result_validate_context
  BEFORE INSERT OR UPDATE ON assessment_result
  FOR EACH ROW EXECUTE FUNCTION validate_assessment_result_context();
