-- M1-T03: normalized partial unique index on student_code per organization.
-- Uniqueness is case-insensitive and whitespace-normalized via lower(btrim(...)).

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM (
      SELECT organization_id, lower(btrim(student_code)) AS normalized_code, count(*) AS cnt
      FROM student
      WHERE student_code IS NOT NULL
        AND btrim(student_code) <> ''
      GROUP BY organization_id, lower(btrim(student_code))
      HAVING count(*) > 1
    ) conflicts
  ) THEN
    RAISE EXCEPTION
      'M1-T03 migration blocked: duplicate normalized student_code values exist within an organization';
  END IF;
END $$;

CREATE UNIQUE INDEX idx_student_code_normalized_unique
  ON student (organization_id, lower(btrim(student_code)))
  WHERE student_code IS NOT NULL
    AND btrim(student_code) <> '';
