-- M1-T05: align Class lifecycle with product contract; add Course/Class audit FKs.

UPDATE class
SET status = 'closed'
WHERE status IN ('completed', 'cancelled');

ALTER TABLE class
  DROP CONSTRAINT class_status_check;

ALTER TABLE class
  ADD CONSTRAINT class_status_check
  CHECK (status IN ('planned', 'trial', 'active', 'closed'));

ALTER TABLE course
  ADD CONSTRAINT course_created_by_fk
  FOREIGN KEY (organization_id, created_by) REFERENCES app_user (organization_id, id),
  ADD CONSTRAINT course_updated_by_fk
  FOREIGN KEY (organization_id, updated_by) REFERENCES app_user (organization_id, id);

ALTER TABLE class
  ADD CONSTRAINT class_created_by_fk
  FOREIGN KEY (organization_id, created_by) REFERENCES app_user (organization_id, id),
  ADD CONSTRAINT class_updated_by_fk
  FOREIGN KEY (organization_id, updated_by) REFERENCES app_user (organization_id, id);
