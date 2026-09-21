-- =============================================================================
-- DEVELOPMENT / LOCAL TEST FIXTURES ONLY
-- NEVER deploy this seed to production.
-- Reference data lives in migration 20260914140100_reference_data.sql.
-- Requires local Supabase (auth.instances). Not used by generic Docker verify.
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

DO $$
DECLARE
  v_org_a uuid := 'a0000000-0000-4000-8000-000000000001';
  v_org_b uuid := 'b0000000-0000-4000-8000-000000000001';
  v_auth_a_admin uuid := 'a1111111-1111-4111-8111-111111111111';
  v_auth_a_staff uuid := 'a2222222-2222-4222-8222-222222222222';
  v_auth_b_admin uuid := 'b1111111-1111-4111-8111-111111111111';
  v_auth_b_staff uuid := 'b2222222-2222-4222-8222-222222222222';
  v_auth_unmapped uuid := 'c1111111-1111-4111-8111-111111111111';
  v_auth_disabled uuid := 'a3333333-3333-4333-8333-333333333333';
  v_auth_a_reader uuid := 'a4444444-4444-4444-8444-444444444444';
  v_auth_a_no_student uuid := 'a5555555-5555-4555-8555-555555555555';
  -- M6-T04 E2E role-denial fixtures (dev/test only; canonical non-Owner roles)
  v_auth_m6_acct uuid := 'a6660001-0000-4000-8000-000000000001';
  v_auth_m6_cons uuid := 'a6660002-0000-4000-8000-000000000002';
  v_auth_m6_acad uuid := 'a6660003-0000-4000-8000-000000000003';
  v_app_m6_acct uuid := 'a6661001-0000-4000-8000-000000000001';
  v_app_m6_cons uuid := 'a6661002-0000-4000-8000-000000000002';
  v_app_m6_acad uuid := 'a6661003-0000-4000-8000-000000000003';
  v_role_m6_acct uuid;
  v_role_m6_cons uuid;
  v_role_m6_acad uuid;
  v_app_a_admin uuid := 'a1000000-0000-4000-8000-000000000001';
  v_app_a_staff uuid := 'a2000000-0000-4000-8000-000000000001';
  v_app_a_reader uuid := 'a4000000-0000-4000-8000-000000000001';
  v_app_a_no_student uuid := 'a5000000-0000-4000-8000-000000000001';
  v_app_b_admin uuid := 'b1000000-0000-4000-8000-000000000001';
  v_app_b_staff uuid := 'b2000000-0000-4000-8000-000000000001';
  v_app_disabled uuid := 'a3000000-0000-4000-8000-000000000001';
  v_role_a_admin uuid;
  v_role_a_staff uuid;
  v_role_a_reader uuid;
  v_role_a_no_student uuid;
  v_role_a_fixture_readonly uuid;
  v_student_tran uuid := 'a5100000-0000-4000-8000-000000000001';
  v_student_nguyen uuid := 'a5100000-0000-4000-8000-000000000002';
  v_guardian_lan uuid := 'a5200000-0000-4000-8000-000000000001';
  v_guardian_quang uuid := 'a5200000-0000-4000-8000-000000000002';
  v_role_b_admin uuid;
  v_role_b_staff uuid;
  v_lead_a1 uuid := 'a6100000-0000-4000-8000-000000000001';
  v_lead_a2 uuid := 'a6100000-0000-4000-8000-000000000002';
  v_lead_b1 uuid := 'b6100000-0000-4000-8000-000000000001';
  v_src_walk_in_a uuid;
  v_src_walk_in_b uuid;
BEGIN
  IF EXISTS (SELECT 1 FROM organization WHERE id = v_org_a) THEN
    RETURN;
  END IF;

  -- Auth users are created via scripts/seed-auth-users.mjs (GoTrue admin API)
  -- so password sign-in works through the HTTP Auth boundary.

  INSERT INTO organization (id, name) VALUES
    (v_org_a, 'Olli Test Org A'),
    (v_org_b, 'Olli Test Org B');

  INSERT INTO app_user (id, organization_id, email, display_name, auth_user_id, status) VALUES
    (v_app_a_admin, v_org_a, 'org-a-admin@olli.local', 'Org A Admin', v_auth_a_admin, 'active'),
    (v_app_a_staff, v_org_a, 'org-a-staff@olli.local', 'Org A Staff', v_auth_a_staff, 'active'),
    (v_app_b_admin, v_org_b, 'org-b-admin@olli.local', 'Org B Admin', v_auth_b_admin, 'active'),
    (v_app_b_staff, v_org_b, 'org-b-staff@olli.local', 'Org B Staff', v_auth_b_staff, 'active'),
    (v_app_disabled, v_org_a, 'disabled@olli.local', 'Disabled User', v_auth_disabled, 'inactive'),
    (v_app_a_reader, v_org_a, 'org-a-reader@olli.local', 'Org A Reader', v_auth_a_reader, 'active'),
    (v_app_a_no_student, v_org_a, 'org-a-no-student@olli.local', 'Org A No Student', v_auth_a_no_student, 'active'),
    (v_app_m6_acct, v_org_b, 'm6-t04-accountant@olli.local', 'M6 Fixture Accountant', v_auth_m6_acct, 'active'),
    (v_app_m6_cons, v_org_b, 'm6-t04-consultant@olli.local', 'M6 Fixture Consultant', v_auth_m6_cons, 'active'),
    (v_app_m6_acad, v_org_b, 'm6-t04-academic-ops@olli.local', 'M6 Fixture Academic Ops', v_auth_m6_acad, 'active');

  -- Canonical roles are created by organization_initialize_access_foundation trigger.
  PERFORM public.set_primary_owner_for_organization(v_org_a, v_app_a_admin);
  PERFORM public.set_primary_owner_for_organization(v_org_b, v_app_b_admin);

  SELECT id INTO v_role_a_admin FROM role
    WHERE organization_id = v_org_a AND canonical_code = 'center_manager' LIMIT 1;
  SELECT id INTO v_role_b_admin FROM role
    WHERE organization_id = v_org_b AND canonical_code = 'center_manager' LIMIT 1;
  SELECT id INTO v_role_a_staff FROM role
    WHERE organization_id = v_org_a AND canonical_code = 'teacher' LIMIT 1;
  SELECT id INTO v_role_m6_acct FROM role
    WHERE organization_id = v_org_b AND canonical_code = 'accountant' LIMIT 1;
  SELECT id INTO v_role_m6_cons FROM role
    WHERE organization_id = v_org_b AND canonical_code = 'consultant' LIMIT 1;
  SELECT id INTO v_role_m6_acad FROM role
    WHERE organization_id = v_org_b AND canonical_code = 'academic_operations' LIMIT 1;
  SELECT id INTO v_role_b_staff FROM role
    WHERE organization_id = v_org_b AND canonical_code = 'teacher' LIMIT 1;

  INSERT INTO role (organization_id, code, is_canonical_template, status) VALUES
    (v_org_a, 'student_reader', false, 'active') RETURNING id INTO v_role_a_reader;
  INSERT INTO role (organization_id, code, is_canonical_template, status) VALUES
    (v_org_a, 'no_student', false, 'active') RETURNING id INTO v_role_a_no_student;
  INSERT INTO role (organization_id, code, is_canonical_template, status) VALUES
    (v_org_a, 'fixture_readonly', false, 'active') RETURNING id INTO v_role_a_fixture_readonly;

  INSERT INTO role_permission (role_id, permission_id)
  SELECT v_role_a_fixture_readonly, p.id FROM permission p
  WHERE p.code IN (
    'student.read', 'enrollment.read', 'charge.read', 'expense.read', 'asset.read', 'observation.read',
    'permission.read', 'role.read', 'organization.read', 'identity.read', 'assessment.read',
    'attendance.read', 'payment.read', 'guardian.read', 'teacher.read'
  );

  INSERT INTO role_permission (role_id, permission_id)
  SELECT v_role_a_reader, p.id FROM permission p
  WHERE p.code IN ('student.read', 'organization.read', 'identity.read');

  INSERT INTO role_permission (role_id, permission_id)
  SELECT v_role_a_no_student, p.id FROM permission p
  WHERE p.code IN ('organization.read');

  INSERT INTO user_role (organization_id, user_id, role_id, effective_from, status) VALUES
    (v_org_a, v_app_a_admin, v_role_a_admin, CURRENT_DATE, 'active'),
    (v_org_a, v_app_a_staff, v_role_a_staff, CURRENT_DATE, 'active'),
    (v_org_a, v_app_a_staff, v_role_a_fixture_readonly, CURRENT_DATE, 'active'),
    (v_org_a, v_app_a_reader, v_role_a_reader, CURRENT_DATE, 'active'),
    (v_org_a, v_app_a_no_student, v_role_a_no_student, CURRENT_DATE, 'active'),
    (v_org_b, v_app_b_admin, v_role_b_admin, CURRENT_DATE, 'active'),
    (v_org_b, v_app_b_staff, v_role_b_staff, CURRENT_DATE, 'active'),
    (v_org_b, v_app_m6_acct, v_role_m6_acct, CURRENT_DATE, 'active'),
    (v_org_b, v_app_m6_cons, v_role_m6_cons, CURRENT_DATE, 'active'),
    (v_org_b, v_app_m6_acad, v_role_m6_acad, CURRENT_DATE, 'active');

  INSERT INTO student (id, organization_id, given_name, family_name, student_code, status) VALUES
    (v_student_tran, v_org_a, 'Văn Phương', 'Trần', 'HV001', 'active'),
    (v_student_nguyen, v_org_a, 'Minh Anh', 'Nguyễn', 'HV002', 'prospect');
  INSERT INTO student (organization_id, given_name, family_name) VALUES
    (v_org_a, 'Student', 'A'),
    (v_org_a, 'Thị Hoa', 'Lê'),
    (v_org_b, 'Student', 'B');

  INSERT INTO course (organization_id, code, name) VALUES
    (v_org_a, 'EA1', 'English A'),
    (v_org_b, 'EB1', 'English B');

  INSERT INTO class (organization_id, course_id, name)
  SELECT v_org_a, c.id, 'Class A1' FROM course c WHERE c.organization_id = v_org_a AND c.code = 'EA1';
  INSERT INTO class (organization_id, course_id, name)
  SELECT v_org_b, c.id, 'Class B1' FROM course c WHERE c.organization_id = v_org_b AND c.code = 'EB1';

  INSERT INTO teacher (organization_id, given_name, family_name, status) VALUES
    (v_org_a, 'Mai', 'Nguyễn', 'active'),
    (v_org_b, 'John', 'Smith', 'active');

  INSERT INTO room (organization_id, code, name, capacity, status) VALUES
    (v_org_a, 'A101', 'Room A101', 20, 'active'),
    (v_org_b, 'B101', 'Room B101', 15, 'active');

  INSERT INTO enrollment (organization_id, student_id, class_id, start_date, status)
  SELECT v_org_a, v_student_tran, cl.id, CURRENT_DATE - 30, 'active'
  FROM class cl
  WHERE cl.organization_id = v_org_a AND cl.name = 'Class A1';

  INSERT INTO enrollment (organization_id, student_id, class_id, start_date, status)
  SELECT v_org_b, s.id, c.id, CURRENT_DATE, 'active'
  FROM student s
  JOIN class c ON c.organization_id = s.organization_id
  WHERE s.organization_id = v_org_b
  LIMIT 1;

  INSERT INTO guardian (id, organization_id, given_name, family_name, phone) VALUES
    (v_guardian_lan, v_org_a, 'Lan', 'Phạm', '0912345678'),
    (v_guardian_quang, v_org_a, 'Quang', 'Phạm', '0987654321');
  INSERT INTO guardian (organization_id, given_name, family_name) VALUES
    (v_org_a, 'Guardian', 'A'),
    (v_org_b, 'Guardian', 'B');

  INSERT INTO student_guardian (organization_id, student_id, guardian_id, relationship_type, is_primary_contact, is_billing_contact) VALUES
    (v_org_a, v_student_tran, v_guardian_lan, 'mother', true, true),
    (v_org_a, v_student_tran, v_guardian_quang, 'father', false, false);

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

  INSERT INTO expense_category (organization_id, cost_group_id, code, display_name)
  SELECT v_org_a, cg.id, 'dev_supplies', 'Dev Supplies' FROM cost_group cg
  WHERE cg.organization_id = v_org_a AND cg.cost_domain_code = 'operating_overhead';

  INSERT INTO expense (organization_id, expense_category_id, cost_group_id, amount, incurred_date)
  SELECT v_org_a, ec.id, ec.cost_group_id, 50000, CURRENT_DATE
  FROM expense_category ec
  WHERE ec.organization_id = v_org_a
  LIMIT 1;

  INSERT INTO class_teacher_assignment (organization_id, class_id, teacher_id, role_code, effective_from, status)
  SELECT v_org_a, cl.id, te.id, 'primary', CURRENT_DATE - 30, 'active'
  FROM class cl
  JOIN teacher te ON te.organization_id = cl.organization_id AND te.given_name = 'Mai'
  WHERE cl.organization_id = v_org_a AND cl.name = 'Class A1';

  INSERT INTO class_schedule (
    organization_id, class_id, weekday_code, start_time, end_time,
    effective_from, room_id, teacher_id, status
  )
  SELECT
    v_org_a, cl.id, 'tue', '18:00'::time, '19:30'::time,
    CURRENT_DATE - 30, r.id, te.id, 'active'
  FROM class cl
  JOIN teacher te ON te.organization_id = cl.organization_id AND te.given_name = 'Mai'
  JOIN room r ON r.organization_id = cl.organization_id AND r.code = 'A101'
  WHERE cl.organization_id = v_org_a AND cl.name = 'Class A1';

  SELECT id INTO v_src_walk_in_a FROM lead_source
  WHERE organization_id = v_org_a AND code = 'walk_in' LIMIT 1;
  SELECT id INTO v_src_walk_in_b FROM lead_source
  WHERE organization_id = v_org_b AND code = 'walk_in' LIMIT 1;

  INSERT INTO lead (id, organization_id, status, lead_source_id, notes_summary, created_by, updated_by)
  VALUES
    (v_lead_a1, v_org_a, 'new', v_src_walk_in_a, 'Sibling inquiry — CRM fixture', v_app_a_admin, v_app_a_admin),
    (v_lead_a2, v_org_a, 'qualified', v_src_walk_in_a, 'Ready for trial scheduling', v_app_a_admin, v_app_a_admin),
    (v_lead_b1, v_org_b, 'new', v_src_walk_in_b, 'Org B isolation fixture', v_app_b_admin, v_app_b_admin);

  INSERT INTO lead_candidate (organization_id, lead_id, given_name, family_name, is_primary_candidate, created_by, updated_by)
  VALUES
    (v_org_a, v_lead_a1, 'Tuấn', 'Phạm', true, v_app_a_admin, v_app_a_admin),
    (v_org_a, v_lead_a1, 'Linh', 'Phạm', false, v_app_a_admin, v_app_a_admin),
    (v_org_a, v_lead_a2, 'Hà', 'Lê', true, v_app_a_admin, v_app_a_admin),
    (v_org_b, v_lead_b1, 'Org B', 'Lead', true, v_app_b_admin, v_app_b_admin);

  INSERT INTO lead_contact (organization_id, lead_id, given_name, family_name, phone, is_primary_contact, is_billing_contact, created_by, updated_by)
  VALUES
    (v_org_a, v_lead_a1, 'Lan', 'Phạm', '0900111222', true, true, v_app_a_admin, v_app_a_admin),
    (v_org_a, v_lead_a2, 'Minh', 'Lê', '0900333444', true, true, v_app_a_admin, v_app_a_admin),
    (v_org_b, v_lead_b1, 'Contact', 'B', '0900555666', true, false, v_app_b_admin, v_app_b_admin);

  INSERT INTO teaching_session (
    organization_id, class_id, class_schedule_id, teacher_id, room_id,
    occurrence_date, scheduled_start_at, scheduled_end_at, status
  )
  SELECT
    v_org_a,
    cl.id,
    cs.id,
    te.id,
    r.id,
    CURRENT_DATE + 7,
    ((CURRENT_DATE + 7) + time '18:00') AT TIME ZONE 'Asia/Ho_Chi_Minh',
    ((CURRENT_DATE + 7) + time '19:30') AT TIME ZONE 'Asia/Ho_Chi_Minh',
    'scheduled'
  FROM class cl
  JOIN teacher te ON te.organization_id = cl.organization_id AND te.given_name = 'Mai'
  JOIN room r ON r.organization_id = cl.organization_id AND r.code = 'A101'
  JOIN class_schedule cs ON cs.class_id = cl.id AND cs.organization_id = cl.organization_id
  WHERE cl.organization_id = v_org_a AND cl.name = 'Class A1'
  LIMIT 1;

END $$;
