-- =============================================================================
-- DEVELOPMENT / LOCAL TEST FIXTURES ONLY
-- NEVER deploy this seed to production.
-- Reference data lives in migration 20260914140100_reference_data.sql.
-- Requires local Supabase (auth.instances). Not used by generic Docker verify.
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

DO $$
DECLARE
  v_instance_id uuid;
  v_org_a uuid := 'a0000000-0000-4000-8000-000000000001';
  v_org_b uuid := 'b0000000-0000-4000-8000-000000000001';
  v_auth_a_admin uuid := 'a1111111-1111-4111-8111-111111111111';
  v_auth_a_staff uuid := 'a2222222-2222-4222-8222-222222222222';
  v_auth_b_admin uuid := 'b1111111-1111-4111-8111-111111111111';
  v_auth_b_staff uuid := 'b2222222-2222-4222-8222-222222222222';
  v_auth_unmapped uuid := 'c1111111-1111-4111-8111-111111111111';
  v_auth_disabled uuid := 'a3333333-3333-4333-8333-333333333333';
  v_app_a_admin uuid := 'a1000000-0000-4000-8000-000000000001';
  v_app_a_staff uuid := 'a2000000-0000-4000-8000-000000000001';
  v_app_b_admin uuid := 'b1000000-0000-4000-8000-000000000001';
  v_app_b_staff uuid := 'b2000000-0000-4000-8000-000000000001';
  v_app_disabled uuid := 'a3000000-0000-4000-8000-000000000001';
  v_role_a_admin uuid;
  v_role_a_staff uuid;
  v_role_b_admin uuid;
  v_role_b_staff uuid;
BEGIN
  IF EXISTS (SELECT 1 FROM organization WHERE id = v_org_a) THEN
    RETURN;
  END IF;

  -- Local Supabase may start with empty auth.instances; bootstrap dev instance row.
  INSERT INTO auth.instances (id, uuid, raw_base_config, created_at, updated_at)
  VALUES (
    '00000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000001',
    '{}',
    now(),
    now()
  ) ON CONFLICT (id) DO NOTHING;

  SELECT id INTO v_instance_id FROM auth.instances LIMIT 1;
  IF v_instance_id IS NULL THEN
    RAISE EXCEPTION 'auth.instances not available — seed requires local Supabase stack';
  END IF;

  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
  ) VALUES
    (v_auth_a_admin, v_instance_id, 'authenticated', 'authenticated', 'org-a-admin@olli.local', crypt('testpass123', gen_salt('bf')), now(), '{}', '{}', now(), now()),
    (v_auth_a_staff, v_instance_id, 'authenticated', 'authenticated', 'org-a-staff@olli.local', crypt('testpass123', gen_salt('bf')), now(), '{}', '{}', now(), now()),
    (v_auth_b_admin, v_instance_id, 'authenticated', 'authenticated', 'org-b-admin@olli.local', crypt('testpass123', gen_salt('bf')), now(), '{}', '{}', now(), now()),
    (v_auth_b_staff, v_instance_id, 'authenticated', 'authenticated', 'org-b-staff@olli.local', crypt('testpass123', gen_salt('bf')), now(), '{}', '{}', now(), now()),
    (v_auth_unmapped, v_instance_id, 'authenticated', 'authenticated', 'unmapped@olli.local', crypt('testpass123', gen_salt('bf')), now(), '{}', '{}', now(), now()),
    (v_auth_disabled, v_instance_id, 'authenticated', 'authenticated', 'disabled@olli.local', crypt('testpass123', gen_salt('bf')), now(), '{}', '{}', now(), now());

  INSERT INTO auth.identities (id, user_id, identity_data, provider, provider_id, last_sign_in_at, created_at, updated_at)
  VALUES
    (v_auth_a_admin, v_auth_a_admin, jsonb_build_object('sub', v_auth_a_admin::text, 'email', 'org-a-admin@olli.local'), 'email', v_auth_a_admin::text, now(), now(), now()),
    (v_auth_a_staff, v_auth_a_staff, jsonb_build_object('sub', v_auth_a_staff::text, 'email', 'org-a-staff@olli.local'), 'email', v_auth_a_staff::text, now(), now(), now()),
    (v_auth_b_admin, v_auth_b_admin, jsonb_build_object('sub', v_auth_b_admin::text, 'email', 'org-b-admin@olli.local'), 'email', v_auth_b_admin::text, now(), now(), now()),
    (v_auth_b_staff, v_auth_b_staff, jsonb_build_object('sub', v_auth_b_staff::text, 'email', 'org-b-staff@olli.local'), 'email', v_auth_b_staff::text, now(), now(), now()),
    (v_auth_unmapped, v_auth_unmapped, jsonb_build_object('sub', v_auth_unmapped::text, 'email', 'unmapped@olli.local'), 'email', v_auth_unmapped::text, now(), now(), now()),
    (v_auth_disabled, v_auth_disabled, jsonb_build_object('sub', v_auth_disabled::text, 'email', 'disabled@olli.local'), 'email', v_auth_disabled::text, now(), now(), now());

  INSERT INTO organization (id, name) VALUES
    (v_org_a, 'Olli Test Org A'),
    (v_org_b, 'Olli Test Org B');

  INSERT INTO app_user (id, organization_id, email, display_name, auth_user_id, status) VALUES
    (v_app_a_admin, v_org_a, 'org-a-admin@olli.local', 'Org A Admin', v_auth_a_admin, 'active'),
    (v_app_a_staff, v_org_a, 'org-a-staff@olli.local', 'Org A Staff', v_auth_a_staff, 'active'),
    (v_app_b_admin, v_org_b, 'org-b-admin@olli.local', 'Org B Admin', v_auth_b_admin, 'active'),
    (v_app_b_staff, v_org_b, 'org-b-staff@olli.local', 'Org B Staff', v_auth_b_staff, 'active'),
    (v_app_disabled, v_org_a, 'disabled@olli.local', 'Disabled User', v_auth_disabled, 'inactive');

  INSERT INTO role (organization_id, code) VALUES (v_org_a, 'admin') RETURNING id INTO v_role_a_admin;
  INSERT INTO role (organization_id, code) VALUES (v_org_a, 'staff') RETURNING id INTO v_role_a_staff;
  INSERT INTO role (organization_id, code) VALUES (v_org_b, 'admin') RETURNING id INTO v_role_b_admin;
  INSERT INTO role (organization_id, code) VALUES (v_org_b, 'staff') RETURNING id INTO v_role_b_staff;

  INSERT INTO role_permission (role_id, permission_id)
  SELECT v_role_a_admin, p.id FROM permission p;
  INSERT INTO role_permission (role_id, permission_id)
  SELECT v_role_b_admin, p.id FROM permission p;

  INSERT INTO role_permission (role_id, permission_id)
  SELECT v_role_a_staff, p.id FROM permission p
  WHERE p.code IN (
    'student.read', 'enrollment.read', 'charge.read', 'expense.read', 'observation.read',
    'permission.read', 'role.read', 'organization.read', 'user.read', 'assessment.read',
    'attendance.read', 'payment.read', 'guardian.read', 'teacher.read'
  );
  INSERT INTO role_permission (role_id, permission_id)
  SELECT v_role_b_staff, p.id FROM permission p
  WHERE p.code IN (
    'student.read', 'enrollment.read', 'charge.read', 'expense.read', 'observation.read',
    'permission.read', 'role.read', 'organization.read', 'user.read', 'assessment.read',
    'attendance.read', 'payment.read', 'guardian.read', 'teacher.read'
  );

  INSERT INTO user_role (organization_id, user_id, role_id, effective_from, status) VALUES
    (v_org_a, v_app_a_admin, v_role_a_admin, CURRENT_DATE, 'active'),
    (v_org_a, v_app_a_staff, v_role_a_staff, CURRENT_DATE, 'active'),
    (v_org_b, v_app_b_admin, v_role_b_admin, CURRENT_DATE, 'active'),
    (v_org_b, v_app_b_staff, v_role_b_staff, CURRENT_DATE, 'active');

  INSERT INTO student (organization_id, given_name, family_name) VALUES
    (v_org_a, 'Student', 'A'),
    (v_org_b, 'Student', 'B');

  INSERT INTO course (organization_id, code, name) VALUES
    (v_org_a, 'EA1', 'English A'),
    (v_org_b, 'EB1', 'English B');

  INSERT INTO class (organization_id, course_id, name)
  SELECT v_org_a, c.id, 'Class A1' FROM course c WHERE c.organization_id = v_org_a AND c.code = 'EA1';
  INSERT INTO class (organization_id, course_id, name)
  SELECT v_org_b, c.id, 'Class B1' FROM course c WHERE c.organization_id = v_org_b AND c.code = 'EB1';

  INSERT INTO enrollment (organization_id, student_id, class_id, start_date, status)
  SELECT v_org_a, s.id, c.id, CURRENT_DATE, 'active'
  FROM student s
  JOIN class c ON c.organization_id = s.organization_id
  WHERE s.organization_id = v_org_a
  LIMIT 1;

  INSERT INTO enrollment (organization_id, student_id, class_id, start_date, status)
  SELECT v_org_b, s.id, c.id, CURRENT_DATE, 'active'
  FROM student s
  JOIN class c ON c.organization_id = s.organization_id
  WHERE s.organization_id = v_org_b
  LIMIT 1;

  INSERT INTO guardian (organization_id, given_name, family_name) VALUES
    (v_org_a, 'Guardian', 'A'),
    (v_org_b, 'Guardian', 'B');

  INSERT INTO charge (organization_id, student_id, guardian_id, amount)
  SELECT s.organization_id, s.id, g.id, 100000
  FROM student s
  JOIN guardian g ON g.organization_id = s.organization_id
  WHERE s.organization_id = v_org_a AND s.given_name = 'Student'
  LIMIT 1;

  INSERT INTO charge (organization_id, student_id, guardian_id, amount)
  SELECT s.organization_id, s.id, g.id, 100000
  FROM student s
  JOIN guardian g ON g.organization_id = s.organization_id
  WHERE s.organization_id = v_org_b AND s.given_name = 'Student'
  LIMIT 1;

  INSERT INTO expense_category (organization_id, cost_group_id, display_name)
  SELECT v_org_a, cg.id, 'Dev Supplies' FROM cost_group cg
  WHERE cg.organization_id = v_org_a AND cg.group_slot = 1;

  INSERT INTO expense (organization_id, expense_category_id, cost_group_id, amount, incurred_date)
  SELECT v_org_a, ec.id, ec.cost_group_id, 50000, CURRENT_DATE
  FROM expense_category ec
  WHERE ec.organization_id = v_org_a
  LIMIT 1;

END $$;
