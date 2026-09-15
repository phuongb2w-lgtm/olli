-- M1-T08: Attendance audit columns, enrollment-date validation, observation session uniqueness.

ALTER TABLE attendance
  ADD COLUMN updated_by uuid;

ALTER TABLE attendance
  ADD CONSTRAINT attendance_recorded_by_fk
  FOREIGN KEY (organization_id, recorded_by) REFERENCES app_user (organization_id, id),
  ADD CONSTRAINT attendance_updated_by_fk
  FOREIGN KEY (organization_id, updated_by) REFERENCES app_user (organization_id, id);

ALTER TABLE teacher_observation
  ADD COLUMN updated_by uuid;

ALTER TABLE teacher_observation
  ADD CONSTRAINT teacher_observation_created_by_fk
  FOREIGN KEY (organization_id, created_by) REFERENCES app_user (organization_id, id),
  ADD CONSTRAINT teacher_observation_updated_by_fk
  FOREIGN KEY (organization_id, updated_by) REFERENCES app_user (organization_id, id);

CREATE UNIQUE INDEX teacher_observation_session_enrollment_unique
  ON teacher_observation (organization_id, enrollment_id, teaching_session_id)
  WHERE teaching_session_id IS NOT NULL AND status <> 'void';

CREATE OR REPLACE FUNCTION validate_attendance_enrollment_eligibility()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  enr_start date;
  enr_end date;
  enr_status text;
  session_date date;
BEGIN
  SELECT e.start_date, e.end_date, e.status
    INTO enr_start, enr_end, enr_status
  FROM enrollment e
  WHERE e.id = NEW.enrollment_id;

  SELECT COALESCE(
    ts.occurrence_date,
    (ts.scheduled_start_at AT TIME ZONE o.timezone)::date
  )
    INTO session_date
  FROM teaching_session ts
  JOIN organization o ON o.id = ts.organization_id
  WHERE ts.id = NEW.teaching_session_id;

  IF enr_start IS NULL OR session_date IS NULL THEN
    RAISE EXCEPTION 'invalid_attendance_context';
  END IF;

  IF enr_start > session_date OR (enr_end IS NOT NULL AND enr_end < session_date) THEN
    RAISE EXCEPTION 'enrollment_not_eligible_on_session_date';
  END IF;

  IF enr_status = 'pending' THEN
    RAISE EXCEPTION 'pending_enrollment_not_attendable';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER attendance_validate_enrollment_eligibility
  BEFORE INSERT OR UPDATE ON attendance
  FOR EACH ROW EXECUTE FUNCTION validate_attendance_enrollment_eligibility();

CREATE OR REPLACE FUNCTION validate_observation_context()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  enr_class_id uuid;
  enr_org_id uuid;
  ses_class_id uuid;
  ses_org_id uuid;
BEGIN
  SELECT e.class_id, e.organization_id
    INTO enr_class_id, enr_org_id
  FROM enrollment e WHERE e.id = NEW.enrollment_id;

  IF NEW.teaching_session_id IS NOT NULL THEN
    SELECT ts.class_id, ts.organization_id
      INTO ses_class_id, ses_org_id
    FROM teaching_session ts WHERE ts.id = NEW.teaching_session_id;

    IF ses_class_id IS NULL THEN
      RAISE EXCEPTION 'invalid_teaching_session_reference';
    END IF;

    IF enr_class_id <> ses_class_id OR NEW.class_id <> ses_class_id THEN
      RAISE EXCEPTION 'observation_class_mismatch';
    END IF;

    IF enr_org_id <> ses_org_id OR NEW.organization_id <> enr_org_id THEN
      RAISE EXCEPTION 'cross_organization_observation_rejected';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER teacher_observation_validate_context
  BEFORE INSERT OR UPDATE ON teacher_observation
  FOR EACH ROW EXECUTE FUNCTION validate_observation_context();
