-- CW2-T13 E2E fixture (dev/test only): deterministic personal-column state for Org C role users.
DO $$
DECLARE
  v_org uuid := 'c0000000-0000-4000-8000-000000000001';
  v_class uuid := 'c0000000-0000-4000-8000-0000000000c1';
  v_student uuid := 'c5130000-0000-4000-8000-000000000001';
  v_users uuid[];
BEGIN
  IF NOT EXISTS (SELECT 1 FROM organization WHERE id = v_org) THEN
    RETURN;
  END IF;

  INSERT INTO student (id, organization_id, given_name, family_name, status)
  VALUES (v_student, v_org, 'Ghi Chu', 'T13', 'active')
  ON CONFLICT (id) DO NOTHING;

  IF EXISTS (SELECT 1 FROM class WHERE id = v_class AND organization_id = v_org)
     AND NOT EXISTS (
       SELECT 1 FROM enrollment e WHERE e.organization_id = v_org AND e.student_id = v_student
     ) THEN
    INSERT INTO enrollment (organization_id, student_id, class_id, start_date, status)
    VALUES (v_org, v_student, v_class, CURRENT_DATE, 'active');
  END IF;

  UPDATE app_user
  SET consultant_operational_code = '02'
  WHERE organization_id = v_org
    AND email = 'm6-t04-consultant@olli.local'
    AND consultant_operational_code IS NULL
    AND NOT EXISTS (
      SELECT 1 FROM app_user o WHERE o.organization_id = v_org AND o.consultant_operational_code = '02'
    );

  SELECT array_agg(id) INTO v_users
  FROM app_user
  WHERE organization_id = v_org
    AND email IN (
      'm6-t04-consultant@olli.local',
      'm6-t04-academic-ops@olli.local',
      'm6-t04-accountant@olli.local',
      'm6-t04-org-c-owner@olli.local'
    );

  DELETE FROM consultant_custom_field_value v
  USING consultant_custom_field_definition d
  WHERE v.field_definition_id = d.id
    AND d.organization_id = v_org
    AND d.owner_app_user_id = ANY (v_users);
  DELETE FROM consultant_custom_field_definition
  WHERE organization_id = v_org AND owner_app_user_id = ANY (v_users);
  DELETE FROM personal_grid_preference
  WHERE organization_id = v_org AND app_user_id = ANY (v_users);
  DELETE FROM consultant_workspace_preference
  WHERE organization_id = v_org AND app_user_id = ANY (v_users);
END $$;
