-- M0-T03 seed: stable foundation reference data only.
-- No guessed Cost B business names. No fake production finance/people data.

-- =============================================================================
-- GLOBAL PERMISSIONS
-- =============================================================================
INSERT INTO permission (code) VALUES
  ('organization.read'),
  ('organization.update'),
  ('student.create'),
  ('student.read'),
  ('student.update'),
  ('guardian.create'),
  ('guardian.read'),
  ('guardian.update'),
  ('teacher.create'),
  ('teacher.read'),
  ('teacher.update'),
  ('enrollment.create'),
  ('enrollment.read'),
  ('enrollment.update'),
  ('attendance.record'),
  ('attendance.read'),
  ('assessment.create'),
  ('assessment.read'),
  ('assessment_result.record'),
  ('observation.record'),
  ('observation.read'),
  ('progress_evaluation.record'),
  ('charge.create'),
  ('charge.read'),
  ('payment.record'),
  ('payment.read'),
  ('expense.create'),
  ('expense.read'),
  ('report.read')
ON CONFLICT (code) DO NOTHING;

-- =============================================================================
-- OBSERVATION INDICATORS (controlled domain codes)
-- =============================================================================
INSERT INTO observation_indicator (code) VALUES
  ('concentration'),
  ('engagement'),
  ('participation')
ON CONFLICT (code) DO NOTHING;

-- =============================================================================
-- LOCAL VERIFICATION FIXTURE (dev/test organization)
-- Applied only when no organizations exist.
-- =============================================================================
DO $$
DECLARE
  org_id uuid;
  admin_role_id uuid;
  perm_id uuid;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM organization) THEN
    INSERT INTO organization (name, default_locale, timezone, currency_code)
    VALUES ('Olli Dev Center', 'vi', 'Asia/Ho_Chi_Minh', 'VND')
    RETURNING id INTO org_id;

    -- Cost groups auto-created by trigger (slots 1 and 2, no business codes)

    INSERT INTO role (organization_id, code)
    VALUES (org_id, 'admin')
    RETURNING id INTO admin_role_id;

    FOR perm_id IN SELECT id FROM permission LOOP
      INSERT INTO role_permission (role_id, permission_id)
      VALUES (admin_role_id, perm_id)
      ON CONFLICT DO NOTHING;
    END LOOP;

    INSERT INTO role (organization_id, code)
    VALUES (org_id, 'teacher')
    ON CONFLICT DO NOTHING;

    INSERT INTO role (organization_id, code)
    VALUES (org_id, 'accountant')
    ON CONFLICT DO NOTHING;
  END IF;
END $$;
