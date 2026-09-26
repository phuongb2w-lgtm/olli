-- M8-T10 synthetic DR fixture (local/disposable only — never production).
-- Idempotent marker org with cross-domain rows for post-restore semantic checks.

DO $$
DECLARE
  v_org uuid := 'd0100000-0000-4000-8000-000000000001';
  v_owner_auth uuid := 'd0111111-1111-4111-8111-111111111111';
  v_staff_auth uuid := 'd0222222-2222-4222-8222-222222222222';
  v_owner_app uuid := 'd0100001-0000-4000-8000-000000000001';
  v_staff_app uuid := 'd0100002-0000-4000-8000-000000000002';
  v_student uuid := 'd0100100-0000-4000-8000-000000000001';
  v_guardian uuid := 'd0100200-0000-4000-8000-000000000001';
  v_lead uuid := 'd0100300-0000-4000-8000-000000000001';
  v_role_mgr uuid;
  v_role_teacher uuid;
  v_src uuid;
  v_course uuid;
  v_class uuid;
  v_teacher uuid;
  v_room uuid;
  v_schedule uuid;
  v_session uuid;
BEGIN
  IF EXISTS (SELECT 1 FROM organization WHERE id = v_org) THEN
    RETURN;
  END IF;

  INSERT INTO organization (id, name, setup_completed_at, default_locale)
  VALUES (v_org, 'M8-T10 DR Fixture Org', now(), 'vi');

  PERFORM public._m7_initialize_organization_subscription(v_org, 'active');

  INSERT INTO app_user (
    id, organization_id, email, display_name, auth_user_id, status, membership_status
  ) VALUES
    (v_owner_app, v_org, 'm8-t10-dr-owner@olli.local', 'DR Fixture Owner', NULL, 'active', 'member'),
    (v_staff_app, v_org, 'm8-t10-dr-staff@olli.local', 'DR Fixture Staff', NULL, 'active', 'member');

  PERFORM public.set_primary_owner_for_organization(v_org, v_owner_app);

  SELECT id INTO v_role_mgr FROM role
  WHERE organization_id = v_org AND canonical_code = 'center_manager' LIMIT 1;
  SELECT id INTO v_role_teacher FROM role
  WHERE organization_id = v_org AND canonical_code = 'teacher' LIMIT 1;

  INSERT INTO user_role (organization_id, user_id, role_id, effective_from, status) VALUES
    (v_org, v_owner_app, v_role_mgr, CURRENT_DATE, 'active'),
    (v_org, v_staff_app, v_role_teacher, CURRENT_DATE, 'active');

  INSERT INTO student (id, organization_id, given_name, family_name, student_code, status) VALUES
    (v_student, v_org, 'DR', 'Student', 'DR-T10-001', 'active');

  INSERT INTO guardian (id, organization_id, given_name, family_name, phone) VALUES
    (v_guardian, v_org, 'DR', 'Guardian', '0900123456');

  INSERT INTO student_guardian (
    organization_id, student_id, guardian_id, relationship_type, is_primary_contact, is_billing_contact
  ) VALUES (v_org, v_student, v_guardian, 'mother', true, true);

  INSERT INTO course (organization_id, code, name) VALUES
    (v_org, 'DR10', 'DR Fixture Course')
  RETURNING id INTO v_course;

  INSERT INTO class (organization_id, course_id, name) VALUES
    (v_org, v_course, 'DR Fixture Class')
  RETURNING id INTO v_class;

  INSERT INTO teacher (organization_id, given_name, family_name, status) VALUES
    (v_org, 'DR', 'Teacher', 'active')
  RETURNING id INTO v_teacher;

  INSERT INTO room (organization_id, code, name, capacity, status) VALUES
    (v_org, 'DR101', 'DR Room', 12, 'active')
  RETURNING id INTO v_room;

  INSERT INTO enrollment (organization_id, student_id, class_id, start_date, status) VALUES
    (v_org, v_student, v_class, CURRENT_DATE - 14, 'active');

  INSERT INTO charge (organization_id, student_id, guardian_id, amount) VALUES
    (v_org, v_student, v_guardian, 250000);

  SELECT id INTO v_src FROM lead_source
  WHERE organization_id = v_org AND code = 'walk_in' LIMIT 1;

  INSERT INTO lead (id, organization_id, status, lead_source_id, notes_summary, created_by, updated_by) VALUES
    (v_lead, v_org, 'qualified', v_src, 'M8-T10 DR CRM marker', v_owner_app, v_owner_app);

  INSERT INTO lead_candidate (organization_id, lead_id, given_name, family_name, is_primary_candidate, created_by, updated_by) VALUES
    (v_org, v_lead, 'DR', 'Candidate', true, v_owner_app, v_owner_app);

  INSERT INTO class_teacher_assignment (organization_id, class_id, teacher_id, role_code, effective_from, status) VALUES
    (v_org, v_class, v_teacher, 'primary', CURRENT_DATE - 14, 'active');

  INSERT INTO class_schedule (
    organization_id, class_id, weekday_code, start_time, end_time,
    effective_from, room_id, teacher_id, status
  ) VALUES (
    v_org, v_class, 'wed', '17:00'::time, '18:30'::time,
    CURRENT_DATE - 14, v_room, v_teacher, 'active'
  ) RETURNING id INTO v_schedule;

  INSERT INTO teaching_session (
    organization_id, class_id, class_schedule_id, teacher_id, room_id,
    occurrence_date, scheduled_start_at, scheduled_end_at, status
  ) VALUES (
    v_org, v_class, v_schedule, v_teacher, v_room,
    CURRENT_DATE + 3,
    ((CURRENT_DATE + 3) + time '17:00') AT TIME ZONE 'Asia/Ho_Chi_Minh',
    ((CURRENT_DATE + 3) + time '18:30') AT TIME ZONE 'Asia/Ho_Chi_Minh',
    'scheduled'
  ) RETURNING id INTO v_session;

  INSERT INTO public.app_rate_limit_bucket (bucket_key, window_started_at, attempt_count, updated_at)
  VALUES ('m8-t10-dr-ephemeral-marker', now(), 1, now())
  ON CONFLICT (bucket_key) DO NOTHING;

  PERFORM 1;
END $$;
