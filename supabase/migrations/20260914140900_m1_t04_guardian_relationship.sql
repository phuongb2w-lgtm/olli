-- M1-T04: student_guardian audit columns + one active primary contact per student.

ALTER TABLE student_guardian
  ADD COLUMN IF NOT EXISTS created_by uuid,
  ADD COLUMN IF NOT EXISTS updated_by uuid;

ALTER TABLE student_guardian
  DROP CONSTRAINT IF EXISTS student_guardian_created_by_fk;

ALTER TABLE student_guardian
  DROP CONSTRAINT IF EXISTS student_guardian_updated_by_fk;

ALTER TABLE student_guardian
  ADD CONSTRAINT student_guardian_created_by_fk
  FOREIGN KEY (organization_id, created_by) REFERENCES app_user (organization_id, id),
  ADD CONSTRAINT student_guardian_updated_by_fk
  FOREIGN KEY (organization_id, updated_by) REFERENCES app_user (organization_id, id);

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM (
      SELECT organization_id, student_id, count(*) AS cnt
      FROM student_guardian
      WHERE status = 'active'
        AND is_primary_contact = true
      GROUP BY organization_id, student_id
      HAVING count(*) > 1
    ) conflicts
  ) THEN
    RAISE EXCEPTION
      'M1-T04 migration blocked: multiple active primary contacts exist for one student';
  END IF;
END $$;

CREATE UNIQUE INDEX idx_student_guardian_primary_unique
  ON student_guardian (organization_id, student_id)
  WHERE status = 'active'
    AND is_primary_contact = true;
