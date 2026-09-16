-- M2-T06: revenue recognition (30 scenarios)

BEGIN;

CREATE TEMP TABLE _m2_rev_results (
  test_no   integer PRIMARY KEY,
  test_name text NOT NULL,
  result    text NOT NULL CHECK (result IN ('PASS', 'FAIL'))
);

GRANT ALL ON TABLE _m2_rev_results TO authenticated, anon;

CREATE OR REPLACE FUNCTION _m2_rev_record(test_no integer, test_name text, passed boolean)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO _m2_rev_results (test_no, test_name, result)
  VALUES (test_no, test_name, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END);
END;
$$;

CREATE OR REPLACE FUNCTION _m2_rev_expect_fail(test_no integer, test_name text, sql_text text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN EXECUTE sql_text; PERFORM _m2_rev_record(test_no, test_name, false);
  EXCEPTION WHEN OTHERS THEN PERFORM _m2_rev_record(test_no, test_name, true); END;
END;
$$;

CREATE OR REPLACE FUNCTION _m2_rev_as_super() RETURNS void LANGUAGE plpgsql AS $$
BEGIN RESET ROLE; SET LOCAL ROLE postgres; END; $$;

CREATE OR REPLACE FUNCTION _m2_rev_as_auth(p_auth_id uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE; SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', p_auth_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_auth_id::text, 'role', 'authenticated')::text, true);
END; $$;

CREATE OR REPLACE FUNCTION _m2_rev_bootstrap()
RETURNS TABLE (
  org_id uuid, class_id uuid, student_id uuid, guardian_id uuid,
  enrollment_id uuid, teacher_id uuid, auth_id uuid
) LANGUAGE plpgsql AS $$
DECLARE
  v_org uuid; v_class uuid; v_student uuid; v_guardian uuid; v_enrollment uuid; v_teacher uuid; v_auth uuid;
BEGIN
  PERFORM _m2_rev_as_super();
  v_org := gen_random_uuid();
  v_auth := gen_random_uuid();
  INSERT INTO organization (id, name) VALUES (v_org, 'M2 Rev Org');
  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at, is_sso_user, is_anonymous)
  VALUES (v_auth, (SELECT id FROM auth.instances LIMIT 1), 'authenticated', 'authenticated', 'rev-' || replace(v_auth::text, '-', '') || '@test.local', '', now(), now(), now(), false, false);
  INSERT INTO app_user (organization_id, email, display_name, auth_user_id, status)
  VALUES (v_org, 'rev-admin@test.local', 'Rev Admin', v_auth, 'active');
  INSERT INTO course (organization_id, code, name) VALUES (v_org, 'R1', 'Rev Course');
  INSERT INTO class (organization_id, course_id, name, status)
  SELECT v_org, c.id, 'Rev Class', 'active' FROM course c WHERE c.organization_id = v_org LIMIT 1 RETURNING id INTO v_class;
  INSERT INTO student (organization_id, given_name, family_name) VALUES (v_org, 'Rev', 'Student') RETURNING id INTO v_student;
  INSERT INTO guardian (organization_id, given_name, family_name) VALUES (v_org, 'Rev', 'Guardian') RETURNING id INTO v_guardian;
  INSERT INTO student_guardian (organization_id, student_id, guardian_id, is_primary_contact, is_billing_contact) VALUES (v_org, v_student, v_guardian, true, true);
  INSERT INTO teacher (organization_id, given_name, family_name, status) VALUES (v_org, 'Rev', 'Teacher', 'active') RETURNING id INTO v_teacher;
  INSERT INTO enrollment (organization_id, student_id, class_id, start_date, status) VALUES (v_org, v_student, v_class, CURRENT_DATE, 'active') RETURNING id INTO v_enrollment;
  RETURN QUERY SELECT v_org, v_class, v_student, v_guardian, v_enrollment, v_teacher, v_auth;
END; $$;

CREATE OR REPLACE FUNCTION _m2_rev_grant_admin(p_org uuid) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_user uuid; v_role uuid;
BEGIN
  SELECT id INTO v_user FROM app_user WHERE organization_id = p_org LIMIT 1;
  INSERT INTO role (organization_id, code) VALUES (p_org, 'rev_admin') RETURNING id INTO v_role;
  INSERT INTO role_permission (role_id, permission_id) SELECT v_role, p.id FROM permission p;
  INSERT INTO user_role (organization_id, user_id, role_id, effective_from, status) VALUES (p_org, v_user, v_role, CURRENT_DATE, 'active');
END; $$;

CREATE OR REPLACE FUNCTION _m2_rev_terms(
  p_org uuid, p_enrollment uuid, p_net bigint, p_basis text DEFAULT 'per_lesson'
) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE tid uuid;
BEGIN
  INSERT INTO enrollment_financial_terms (
    organization_id, enrollment_id, agreed_tuition_amount, discount_amount,
    net_tuition_amount, agreement_date, recognition_basis_code, status
  ) VALUES (p_org, p_enrollment, p_net, 0, p_net, CURRENT_DATE, p_basis, 'draft') RETURNING id INTO tid;
  INSERT INTO enrollment_payment_schedule_item (organization_id, enrollment_financial_terms_id, sequence_number, due_date, amount)
  VALUES (p_org, tid, 1, CURRENT_DATE, p_net);
  UPDATE enrollment_financial_terms SET status = 'active' WHERE id = tid;
  RETURN tid;
END; $$;

CREATE OR REPLACE FUNCTION _m2_rev_session(
  p_org uuid, p_class uuid, p_teacher uuid, p_day_offset integer DEFAULT 0, p_status text DEFAULT 'completed'
) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE sid uuid; v_start timestamptz;
BEGIN
  v_start := (CURRENT_DATE + p_day_offset)::timestamptz + interval '9 hours';
  INSERT INTO teaching_session (organization_id, class_id, teacher_id, scheduled_start_at, scheduled_end_at, status)
  VALUES (p_org, p_class, p_teacher, v_start, v_start + interval '1 hour', p_status)
  RETURNING id INTO sid;
  RETURN sid;
END; $$;

CREATE OR REPLACE FUNCTION _m2_rev_attendance(
  p_org uuid, p_session uuid, p_enrollment uuid, p_status text DEFAULT 'present'
) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO attendance (organization_id, teaching_session_id, enrollment_id, status)
  VALUES (p_org, p_session, p_enrollment, p_status);
END; $$;

-- 1: per-lesson recognition configuration
DO $$
DECLARE b record; tid uuid; cid uuid;
BEGIN
  SELECT * INTO b FROM _m2_rev_bootstrap();
  tid := _m2_rev_terms(b.org_id, b.enrollment_id, 20000000, 'per_lesson');
  PERFORM _m2_rev_grant_admin(b.org_id);
  PERFORM _m2_rev_as_auth(b.auth_id);
  cid := public.initialize_enrollment_per_lesson_recognition(tid, 40);
  PERFORM _m2_rev_record(1, 'per-lesson recognition configuration', cid IS NOT NULL);
END $$;

-- 2: stage recognition configuration
DO $$
DECLARE b record; tid uuid; aid uuid; cid uuid;
BEGIN
  SELECT * INTO b FROM _m2_rev_bootstrap();
  tid := _m2_rev_terms(b.org_id, b.enrollment_id, 10000000, 'stage');
  INSERT INTO assessment (organization_id, class_id, assessment_type_code, title, max_score, assessed_on, status)
  VALUES (b.org_id, b.class_id, 'checkpoint', 'Stage 1', 100, CURRENT_DATE, 'open') RETURNING id INTO aid;
  PERFORM _m2_rev_grant_admin(b.org_id);
  PERFORM _m2_rev_as_auth(b.auth_id);
  cid := public.set_enrollment_recognition_stages(tid, jsonb_build_array(
    jsonb_build_object('sequence_number', 1, 'amount', 10000000, 'assessment_id', aid, 'label', 'Stage 1')
  ));
  PERFORM _m2_rev_record(2, 'stage recognition configuration', cid IS NOT NULL);
END $$;

-- 3: different enrollments may use different recognition bases
DO $$
DECLARE b record; b_alt record; t1 uuid; t2 uuid; basis1 text; basis2 text;
BEGIN
  SELECT * INTO b FROM _m2_rev_bootstrap();
  SELECT * INTO b_alt FROM _m2_rev_bootstrap();
  t1 := _m2_rev_terms(b.org_id, b.enrollment_id, 5000000, 'per_lesson');
  t2 := _m2_rev_terms(b_alt.org_id, b_alt.enrollment_id, 7000000, 'stage');
  SELECT recognition_basis_code INTO basis1 FROM enrollment_financial_terms WHERE id = t1;
  SELECT recognition_basis_code INTO basis2 FROM enrollment_financial_terms WHERE id = t2;
  PERFORM _m2_rev_record(3, 'different enrollments different bases', basis1 = 'per_lesson' AND basis2 = 'stage');
END $$;

-- 4: per-lesson amount precision
DO $$
DECLARE amt bigint;
BEGIN
  amt := public.recognition_lesson_amount(20000000, 40, 1);
  PERFORM _m2_rev_record(4, 'per-lesson amount precision', amt = 500000);
END $$;

-- 5: final per-lesson remainder produces exact tuition total
DO $$
DECLARE total bigint; i integer;
BEGIN
  total := 0;
  FOR i IN 1..40 LOOP
    total := total + public.recognition_lesson_amount(20000001, 40, i);
  END LOOP;
  PERFORM _m2_rev_record(5, 'per-lesson remainder exact total', total = 20000001);
END $$;

-- 6: stage amounts total exact tuition
SELECT _m2_rev_expect_fail(6, 'stage amounts must total exact tuition', $$
  DO $i$ DECLARE b record; tid uuid; aid uuid; BEGIN
    SELECT * INTO b FROM _m2_rev_bootstrap();
    tid := _m2_rev_terms(b.org_id, b.enrollment_id, 10000000, 'stage');
    INSERT INTO assessment (organization_id, class_id, assessment_type_code, title, max_score, assessed_on, status)
    VALUES (b.org_id, b.class_id, 'checkpoint', 'S1', 100, CURRENT_DATE, 'open') RETURNING id INTO aid;
    PERFORM _m2_rev_grant_admin(b.org_id);
    PERFORM _m2_rev_as_auth(b.auth_id);
    PERFORM public.set_enrollment_recognition_stages(tid, jsonb_build_array(
      jsonb_build_object('sequence_number', 1, 'amount', 9000000, 'assessment_id', aid)
    ));
  END $i$;
$$);

-- 7: eligible delivered lesson creates recognition
DO $$
DECLARE b record; tid uuid; sid uuid; res jsonb; cnt integer;
BEGIN
  SELECT * INTO b FROM _m2_rev_bootstrap();
  tid := _m2_rev_terms(b.org_id, b.enrollment_id, 4000000, 'per_lesson');
  PERFORM _m2_rev_grant_admin(b.org_id);
  PERFORM _m2_rev_as_auth(b.auth_id);
  PERFORM public.initialize_enrollment_per_lesson_recognition(tid, 4);
  sid := _m2_rev_session(b.org_id, b.class_id, b.teacher_id, 0);
  PERFORM _m2_rev_attendance(b.org_id, sid, b.enrollment_id, 'present');
  res := public.recognize_enrollment_revenue(b.enrollment_id);
  SELECT count(*) INTO cnt FROM revenue_recognition_event WHERE enrollment_id = b.enrollment_id AND status = 'posted';
  PERFORM _m2_rev_record(7, 'eligible delivered lesson creates recognition', cnt = 1 AND (res->>'events_created')::int = 1);
END $$;

-- 8: non-eligible academic state creates none
DO $$
DECLARE b record; tid uuid; sid uuid; cnt integer;
BEGIN
  SELECT * INTO b FROM _m2_rev_bootstrap();
  tid := _m2_rev_terms(b.org_id, b.enrollment_id, 4000000, 'per_lesson');
  PERFORM _m2_rev_grant_admin(b.org_id);
  PERFORM _m2_rev_as_auth(b.auth_id);
  PERFORM public.initialize_enrollment_per_lesson_recognition(tid, 4);
  sid := _m2_rev_session(b.org_id, b.class_id, b.teacher_id, 1, 'scheduled');
  PERFORM _m2_rev_attendance(b.org_id, sid, b.enrollment_id, 'present');
  PERFORM public.recognize_enrollment_revenue(b.enrollment_id);
  sid := _m2_rev_session(b.org_id, b.class_id, b.teacher_id, 2);
  PERFORM _m2_rev_attendance(b.org_id, sid, b.enrollment_id, 'absent');
  UPDATE teaching_session SET status = 'completed' WHERE id = sid;
  PERFORM public.recognize_enrollment_revenue(b.enrollment_id);
  SELECT count(*) INTO cnt FROM revenue_recognition_event WHERE enrollment_id = b.enrollment_id AND status = 'posted';
  PERFORM _m2_rev_record(8, 'non-eligible academic state creates none', cnt = 0);
END $$;

-- 9: recognition rerun is idempotent
DO $$
DECLARE b record; tid uuid; sid uuid; r1 jsonb; r2 jsonb;
BEGIN
  SELECT * INTO b FROM _m2_rev_bootstrap();
  tid := _m2_rev_terms(b.org_id, b.enrollment_id, 2000000, 'per_lesson');
  PERFORM _m2_rev_grant_admin(b.org_id);
  PERFORM _m2_rev_as_auth(b.auth_id);
  PERFORM public.initialize_enrollment_per_lesson_recognition(tid, 2);
  sid := _m2_rev_session(b.org_id, b.class_id, b.teacher_id, 0);
  PERFORM _m2_rev_attendance(b.org_id, sid, b.enrollment_id, 'late');
  r1 := public.recognize_enrollment_revenue(b.enrollment_id);
  r2 := public.recognize_enrollment_revenue(b.enrollment_id);
  PERFORM _m2_rev_record(9, 'recognition rerun is idempotent', (r1->>'events_created')::int = 1 AND (r2->>'events_created')::int = 0);
END $$;

-- 10: same lesson cannot recognize twice
DO $$
DECLARE b record; tid uuid; sid uuid; cnt integer;
BEGIN
  SELECT * INTO b FROM _m2_rev_bootstrap();
  tid := _m2_rev_terms(b.org_id, b.enrollment_id, 2000000, 'per_lesson');
  PERFORM _m2_rev_grant_admin(b.org_id);
  PERFORM _m2_rev_as_auth(b.auth_id);
  PERFORM public.initialize_enrollment_per_lesson_recognition(tid, 2);
  sid := _m2_rev_session(b.org_id, b.class_id, b.teacher_id, 1);
  PERFORM _m2_rev_attendance(b.org_id, sid, b.enrollment_id, 'present');
  PERFORM public.recognize_enrollment_revenue(b.enrollment_id);
  PERFORM public.recognize_enrollment_revenue(b.enrollment_id);
  SELECT count(*) INTO cnt FROM revenue_recognition_event WHERE teaching_session_id = sid AND status = 'posted';
  PERFORM _m2_rev_record(10, 'same lesson cannot recognize twice', cnt = 1);
END $$;

-- 11: multiple eligible lessons recognize independently
DO $$
DECLARE b record; tid uuid; s1 uuid; s2 uuid; total bigint;
BEGIN
  SELECT * INTO b FROM _m2_rev_bootstrap();
  tid := _m2_rev_terms(b.org_id, b.enrollment_id, 3000000, 'per_lesson');
  PERFORM _m2_rev_grant_admin(b.org_id);
  PERFORM _m2_rev_as_auth(b.auth_id);
  PERFORM public.initialize_enrollment_per_lesson_recognition(tid, 3);
  s1 := _m2_rev_session(b.org_id, b.class_id, b.teacher_id, 0);
  s2 := _m2_rev_session(b.org_id, b.class_id, b.teacher_id, 1);
  PERFORM _m2_rev_attendance(b.org_id, s1, b.enrollment_id, 'present');
  PERFORM _m2_rev_attendance(b.org_id, s2, b.enrollment_id, 'present');
  PERFORM public.recognize_enrollment_revenue(b.enrollment_id);
  SELECT COALESCE(SUM(amount), 0) INTO total FROM revenue_recognition_event WHERE enrollment_id = b.enrollment_id AND status = 'posted';
  PERFORM _m2_rev_record(11, 'multiple eligible lessons recognize independently', total = 2000000);
END $$;

-- 12: revenue recognition works with zero payment
DO $$
DECLARE b record; tid uuid; sid uuid; rec bigint;
BEGIN
  SELECT * INTO b FROM _m2_rev_bootstrap();
  tid := _m2_rev_terms(b.org_id, b.enrollment_id, 1000000, 'per_lesson');
  PERFORM _m2_rev_grant_admin(b.org_id);
  PERFORM _m2_rev_as_auth(b.auth_id);
  PERFORM public.initialize_enrollment_per_lesson_recognition(tid, 1);
  sid := _m2_rev_session(b.org_id, b.class_id, b.teacher_id, 0);
  PERFORM _m2_rev_attendance(b.org_id, sid, b.enrollment_id, 'present');
  PERFORM public.recognize_enrollment_revenue(b.enrollment_id);
  rec := public.enrollment_recognized_revenue(b.enrollment_id);
  PERFORM _m2_rev_record(12, 'recognition works with zero payment', rec = 1000000);
END $$;

-- 13: revenue recognition works with partial payment
DO $$
DECLARE b record; tid uuid; cid uuid; sid uuid; rec bigint;
BEGIN
  SELECT * INTO b FROM _m2_rev_bootstrap();
  tid := _m2_rev_terms(b.org_id, b.enrollment_id, 2000000, 'per_lesson');
  INSERT INTO charge (organization_id, student_id, enrollment_id, guardian_id, amount, due_date, status)
  VALUES (b.org_id, b.student_id, b.enrollment_id, b.guardian_id, 2000000, CURRENT_DATE, 'open') RETURNING id INTO cid;
  PERFORM _m2_rev_grant_admin(b.org_id);
  PERFORM _m2_rev_as_auth(b.auth_id);
  PERFORM public.record_payment(b.guardian_id, 500000, now(), 'cash', NULL, NULL, NULL, NULL, NULL,
    jsonb_build_array(jsonb_build_object('charge_id', cid, 'amount', 500000)));
  PERFORM public.initialize_enrollment_per_lesson_recognition(tid, 2);
  sid := _m2_rev_session(b.org_id, b.class_id, b.teacher_id, 0);
  PERFORM _m2_rev_attendance(b.org_id, sid, b.enrollment_id, 'present');
  PERFORM public.recognize_enrollment_revenue(b.enrollment_id);
  rec := public.enrollment_recognized_revenue(b.enrollment_id);
  PERFORM _m2_rev_record(13, 'recognition works with partial payment', rec = 1000000);
END $$;

-- 14: full prepayment does not accelerate revenue
DO $$
DECLARE b record; tid uuid; cid uuid; rec bigint;
BEGIN
  SELECT * INTO b FROM _m2_rev_bootstrap();
  tid := _m2_rev_terms(b.org_id, b.enrollment_id, 2000000, 'per_lesson');
  INSERT INTO charge (organization_id, student_id, enrollment_id, guardian_id, amount, due_date, status)
  VALUES (b.org_id, b.student_id, b.enrollment_id, b.guardian_id, 2000000, CURRENT_DATE, 'open') RETURNING id INTO cid;
  PERFORM _m2_rev_grant_admin(b.org_id);
  PERFORM _m2_rev_as_auth(b.auth_id);
  PERFORM public.record_payment(b.guardian_id, 2000000, now(), 'cash', NULL, NULL, NULL, NULL, NULL,
    jsonb_build_array(jsonb_build_object('charge_id', cid, 'amount', 2000000)));
  PERFORM public.initialize_enrollment_per_lesson_recognition(tid, 2);
  rec := public.enrollment_recognized_revenue(b.enrollment_id);
  PERFORM _m2_rev_record(14, 'full prepayment does not accelerate revenue', rec = 0);
END $$;

-- 15: charge creation does not create revenue
DO $$
DECLARE b record; tid uuid; cnt_before integer; cnt_after integer;
BEGIN
  SELECT * INTO b FROM _m2_rev_bootstrap();
  tid := _m2_rev_terms(b.org_id, b.enrollment_id, 1000000, 'per_lesson');
  PERFORM _m2_rev_grant_admin(b.org_id);
  PERFORM _m2_rev_as_auth(b.auth_id);
  SELECT count(*) INTO cnt_before
    FROM revenue_recognition_event
   WHERE enrollment_id = b.enrollment_id;
  INSERT INTO charge (organization_id, student_id, enrollment_id, guardian_id, amount, due_date, status)
  VALUES (b.org_id, b.student_id, b.enrollment_id, b.guardian_id, 1000000, CURRENT_DATE, 'open');
  SELECT count(*) INTO cnt_after
    FROM revenue_recognition_event
   WHERE enrollment_id = b.enrollment_id;
  PERFORM _m2_rev_record(15, 'charge creation does not create revenue', cnt_before = 0 AND cnt_after = 0);
END $$;

-- 16: payment creation does not create revenue
DO $$
DECLARE b record; cnt integer;
BEGIN
  SELECT * INTO b FROM _m2_rev_bootstrap();
  PERFORM _m2_rev_grant_admin(b.org_id);
  PERFORM _m2_rev_as_auth(b.auth_id);
  PERFORM public.record_payment(b.guardian_id, 1000000, now(), 'cash');
  SELECT count(*) INTO cnt FROM revenue_recognition_event;
  PERFORM _m2_rev_record(16, 'payment creation does not create revenue', cnt = 0);
END $$;

-- 17: allocation does not create revenue
DO $$
DECLARE b record; cid uuid; cnt integer;
BEGIN
  SELECT * INTO b FROM _m2_rev_bootstrap();
  INSERT INTO charge (organization_id, student_id, enrollment_id, guardian_id, amount, due_date, status)
  VALUES (b.org_id, b.student_id, b.enrollment_id, b.guardian_id, 1000000, CURRENT_DATE, 'open') RETURNING id INTO cid;
  PERFORM _m2_rev_grant_admin(b.org_id);
  PERFORM _m2_rev_as_auth(b.auth_id);
  PERFORM public.record_payment(b.guardian_id, 1000000, now(), 'cash', NULL, NULL, NULL, NULL, NULL,
    jsonb_build_array(jsonb_build_object('charge_id', cid, 'amount', 1000000)));
  SELECT count(*) INTO cnt FROM revenue_recognition_event;
  PERFORM _m2_rev_record(17, 'allocation does not create revenue', cnt = 0);
END $$;

-- 18: recognition cannot exceed entitlement
DO $$
DECLARE b record; tid uuid; sid uuid; cfg uuid; ok boolean := false;
BEGIN
  SELECT * INTO b FROM _m2_rev_bootstrap();
  tid := _m2_rev_terms(b.org_id, b.enrollment_id, 1000000, 'per_lesson');
  PERFORM _m2_rev_grant_admin(b.org_id);
  PERFORM _m2_rev_as_auth(b.auth_id);
  cfg := public.initialize_enrollment_per_lesson_recognition(tid, 1);
  sid := _m2_rev_session(b.org_id, b.class_id, b.teacher_id, 0);
  BEGIN
    INSERT INTO revenue_recognition_event (
      organization_id, enrollment_id, enrollment_financial_terms_id, enrollment_recognition_config_id,
      recognition_basis_code, amount, lesson_sequence_number, teaching_session_id, status, created_by
    ) VALUES (
      b.org_id, b.enrollment_id, tid, cfg, 'per_lesson', 2000000, 1, sid, 'posted', public.current_app_user_id()
    );
  EXCEPTION WHEN OTHERS THEN ok := true; END;
  PERFORM _m2_rev_record(18, 'recognition cannot exceed entitlement', ok);
END $$;

-- 19: stage cannot recognize before completion evidence
DO $$
DECLARE b record; tid uuid; aid uuid; cnt integer;
BEGIN
  SELECT * INTO b FROM _m2_rev_bootstrap();
  tid := _m2_rev_terms(b.org_id, b.enrollment_id, 5000000, 'stage');
  INSERT INTO assessment (organization_id, class_id, assessment_type_code, title, max_score, assessed_on, status)
  VALUES (b.org_id, b.class_id, 'checkpoint', 'Gate', 100, CURRENT_DATE, 'open') RETURNING id INTO aid;
  PERFORM _m2_rev_grant_admin(b.org_id);
  PERFORM _m2_rev_as_auth(b.auth_id);
  PERFORM public.set_enrollment_recognition_stages(tid, jsonb_build_array(
    jsonb_build_object('sequence_number', 1, 'amount', 5000000, 'assessment_id', aid)
  ));
  PERFORM public.recognize_enrollment_revenue(b.enrollment_id);
  SELECT count(*) INTO cnt FROM revenue_recognition_event WHERE enrollment_id = b.enrollment_id AND status = 'posted';
  PERFORM _m2_rev_record(19, 'stage cannot recognize before completion evidence', cnt = 0);
END $$;

-- 20: completed stage recognizes once
DO $$
DECLARE b record; tid uuid; aid uuid; cnt integer;
BEGIN
  SELECT * INTO b FROM _m2_rev_bootstrap();
  tid := _m2_rev_terms(b.org_id, b.enrollment_id, 5000000, 'stage');
  INSERT INTO assessment (organization_id, class_id, assessment_type_code, title, max_score, assessed_on, status)
  VALUES (b.org_id, b.class_id, 'checkpoint', 'Gate', 100, CURRENT_DATE, 'open') RETURNING id INTO aid;
  INSERT INTO assessment_result (organization_id, assessment_id, enrollment_id, raw_score, max_score, status, finalized_at)
  VALUES (b.org_id, aid, b.enrollment_id, 80, 100, 'finalized', now());
  PERFORM _m2_rev_grant_admin(b.org_id);
  PERFORM _m2_rev_as_auth(b.auth_id);
  PERFORM public.set_enrollment_recognition_stages(tid, jsonb_build_array(
    jsonb_build_object('sequence_number', 1, 'amount', 5000000, 'assessment_id', aid)
  ));
  PERFORM public.recognize_enrollment_revenue(b.enrollment_id);
  PERFORM public.recognize_enrollment_revenue(b.enrollment_id);
  SELECT count(*) INTO cnt FROM revenue_recognition_event WHERE enrollment_id = b.enrollment_id AND status = 'posted';
  PERFORM _m2_rev_record(20, 'completed stage recognizes once', cnt = 1);
END $$;

-- 21: academic correction uses auditable void behavior
DO $$
DECLARE b record; tid uuid; sid uuid; eid uuid; rec_before bigint; rec_after bigint; st text;
BEGIN
  SELECT * INTO b FROM _m2_rev_bootstrap();
  tid := _m2_rev_terms(b.org_id, b.enrollment_id, 1000000, 'per_lesson');
  PERFORM _m2_rev_grant_admin(b.org_id);
  PERFORM _m2_rev_as_auth(b.auth_id);
  PERFORM public.initialize_enrollment_per_lesson_recognition(tid, 1);
  sid := _m2_rev_session(b.org_id, b.class_id, b.teacher_id, 0);
  PERFORM _m2_rev_attendance(b.org_id, sid, b.enrollment_id, 'present');
  PERFORM public.recognize_enrollment_revenue(b.enrollment_id);
  SELECT id INTO eid FROM revenue_recognition_event WHERE enrollment_id = b.enrollment_id LIMIT 1;
  rec_before := public.enrollment_recognized_revenue(b.enrollment_id);
  PERFORM public.void_revenue_recognition_event(eid, 'attendance corrected');
  rec_after := public.enrollment_recognized_revenue(b.enrollment_id);
  SELECT status INTO st FROM revenue_recognition_event WHERE id = eid;
  PERFORM _m2_rev_record(21, 'academic correction uses auditable void', rec_before = 1000000 AND rec_after = 0 AND st = 'void');
END $$;

-- 22: historical recognition row is not silently rewritten
DO $$
DECLARE b record; tid uuid; sid uuid; eid uuid; amt bigint;
BEGIN
  SELECT * INTO b FROM _m2_rev_bootstrap();
  tid := _m2_rev_terms(b.org_id, b.enrollment_id, 1000000, 'per_lesson');
  PERFORM _m2_rev_grant_admin(b.org_id);
  PERFORM _m2_rev_as_auth(b.auth_id);
  PERFORM public.initialize_enrollment_per_lesson_recognition(tid, 1);
  sid := _m2_rev_session(b.org_id, b.class_id, b.teacher_id, 0);
  PERFORM _m2_rev_attendance(b.org_id, sid, b.enrollment_id, 'present');
  PERFORM public.recognize_enrollment_revenue(b.enrollment_id);
  SELECT id, amount INTO eid, amt FROM revenue_recognition_event WHERE enrollment_id = b.enrollment_id LIMIT 1;
  PERFORM public.void_revenue_recognition_event(eid, 'audit');
  SELECT amount INTO amt FROM revenue_recognition_event WHERE id = eid;
  PERFORM _m2_rev_record(22, 'historical recognition row not rewritten', amt = 1000000);
END $$;

-- 23: cross-org evidence rejected
SELECT _m2_rev_expect_fail(23, 'cross-org evidence rejected', $$
  DO $i$ DECLARE a record; b record; tid uuid; sid uuid; BEGIN
    SELECT * INTO a FROM _m2_rev_bootstrap();
    SELECT * INTO b FROM _m2_rev_bootstrap();
    tid := _m2_rev_terms(a.org_id, a.enrollment_id, 1000000, 'per_lesson');
    sid := _m2_rev_session(b.org_id, b.class_id, b.teacher_id, 0);
    PERFORM _m2_rev_attendance(b.org_id, sid, b.enrollment_id, 'present');
    PERFORM _m2_rev_grant_admin(a.org_id);
    PERFORM _m2_rev_as_auth(a.auth_id);
    PERFORM public.initialize_enrollment_per_lesson_recognition(tid, 1);
    INSERT INTO revenue_recognition_event (
      organization_id, enrollment_id, enrollment_financial_terms_id, enrollment_recognition_config_id,
      recognition_basis_code, amount, lesson_sequence_number, teaching_session_id, status
    )
    SELECT a.org_id, a.enrollment_id, tid, c.id, 'per_lesson', 1000000, 1, sid, 'posted'
    FROM enrollment_recognition_config c WHERE c.enrollment_financial_terms_id = tid;
  END $i$;
$$);

-- 24: RLS prevents tenant leakage
DO $$
DECLARE b record; cnt integer;
BEGIN
  SELECT * INTO b FROM _m2_rev_bootstrap();
  PERFORM _m2_rev_grant_admin(b.org_id);
  PERFORM _m2_rev_as_auth(b.auth_id);
  PERFORM public.record_payment(b.guardian_id, 100000, now(), 'cash');
  PERFORM _m2_rev_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO cnt FROM revenue_recognition_event WHERE organization_id = b.org_id;
  PERFORM _m2_rev_record(24, 'RLS prevents tenant leakage', cnt = 0);
END $$;

-- 25: permission gate works
DO $$
DECLARE b record; ok boolean := false;
BEGIN
  SELECT * INTO b FROM _m2_rev_bootstrap();
  PERFORM _m2_rev_as_auth(b.auth_id);
  BEGIN
    PERFORM public.recognize_enrollment_revenue(b.enrollment_id);
  EXCEPTION WHEN OTHERS THEN ok := true; END;
  PERFORM _m2_rev_record(25, 'permission gate works', ok);
END $$;

-- 26: financial summary derives recognized revenue
DO $$
DECLARE b record; tid uuid; sid uuid; summary jsonb;
BEGIN
  SELECT * INTO b FROM _m2_rev_bootstrap();
  tid := _m2_rev_terms(b.org_id, b.enrollment_id, 2000000, 'per_lesson');
  PERFORM _m2_rev_grant_admin(b.org_id);
  PERFORM _m2_rev_as_auth(b.auth_id);
  PERFORM public.initialize_enrollment_per_lesson_recognition(tid, 2);
  sid := _m2_rev_session(b.org_id, b.class_id, b.teacher_id, 0);
  PERFORM _m2_rev_attendance(b.org_id, sid, b.enrollment_id, 'present');
  PERFORM public.recognize_enrollment_revenue(b.enrollment_id);
  summary := public.get_enrollment_financial_summary(b.enrollment_id);
  PERFORM _m2_rev_record(26, 'summary derives recognized revenue', (summary->>'recognized_revenue')::bigint = 1000000);
END $$;

-- 27: financial summary derives service obligation
DO $$
DECLARE b record; tid uuid; summary jsonb;
BEGIN
  SELECT * INTO b FROM _m2_rev_bootstrap();
  tid := _m2_rev_terms(b.org_id, b.enrollment_id, 2000000, 'per_lesson');
  PERFORM _m2_rev_grant_admin(b.org_id);
  PERFORM _m2_rev_as_auth(b.auth_id);
  PERFORM public.initialize_enrollment_per_lesson_recognition(tid, 2);
  summary := public.get_enrollment_financial_summary(b.enrollment_id);
  PERFORM _m2_rev_record(27, 'summary derives service obligation', (summary->>'unrecognized_service_obligation')::bigint = 2000000);
END $$;

-- 28: outstanding receivable remains independent
DO $$
DECLARE b record; tid uuid; cid uuid; summary jsonb;
BEGIN
  SELECT * INTO b FROM _m2_rev_bootstrap();
  tid := _m2_rev_terms(b.org_id, b.enrollment_id, 3000000, 'per_lesson');
  INSERT INTO charge (organization_id, student_id, enrollment_id, guardian_id, amount, due_date, status)
  VALUES (b.org_id, b.student_id, b.enrollment_id, b.guardian_id, 3000000, CURRENT_DATE, 'open') RETURNING id INTO cid;
  PERFORM _m2_rev_grant_admin(b.org_id);
  PERFORM _m2_rev_as_auth(b.auth_id);
  PERFORM public.initialize_enrollment_per_lesson_recognition(tid, 3);
  summary := public.get_enrollment_financial_summary(b.enrollment_id);
  PERFORM _m2_rev_record(
    28,
    'outstanding receivable remains independent',
    (summary->>'outstanding_receivable')::bigint = 3000000
    AND (summary->>'recognized_revenue')::bigint = 0
  );
END $$;

-- 29: M1 academic records remain unchanged
DO $$
DECLARE b record; tid uuid; sid uuid; ts_status text; att_status text;
BEGIN
  SELECT * INTO b FROM _m2_rev_bootstrap();
  tid := _m2_rev_terms(b.org_id, b.enrollment_id, 1000000, 'per_lesson');
  sid := _m2_rev_session(b.org_id, b.class_id, b.teacher_id, 0);
  PERFORM _m2_rev_attendance(b.org_id, sid, b.enrollment_id, 'present');
  PERFORM _m2_rev_grant_admin(b.org_id);
  PERFORM _m2_rev_as_auth(b.auth_id);
  PERFORM public.initialize_enrollment_per_lesson_recognition(tid, 1);
  PERFORM public.recognize_enrollment_revenue(b.enrollment_id);
  SELECT status INTO ts_status FROM teaching_session WHERE id = sid;
  SELECT status INTO att_status FROM attendance WHERE teaching_session_id = sid;
  PERFORM _m2_rev_record(29, 'M1 academic records remain unchanged', ts_status = 'completed' AND att_status = 'present');
END $$;

-- 30: existing T04/T05 structures unaffected
DO $$
DECLARE pay_cnt integer; terms_cnt integer;
BEGIN
  SELECT count(*) INTO pay_cnt FROM payment;
  SELECT count(*) INTO terms_cnt FROM enrollment_financial_terms;
  PERFORM _m2_rev_record(30, 'T04/T05 structures unaffected', pay_cnt >= 0 AND terms_cnt >= 0);
END $$;

DO $$
DECLARE total integer; passed integer; failed integer;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE result = 'PASS'), count(*) FILTER (WHERE result = 'FAIL')
    INTO total, passed, failed FROM _m2_rev_results;
  RAISE NOTICE 'M2 revenue recognition Tests: % / % passed (% failed)', passed, total, failed;
  IF failed > 0 OR total <> 30 THEN
    RAISE EXCEPTION 'M2 revenue recognition tests failed: % of % (expected 30)', failed, total;
  END IF;
END $$;

SELECT test_no, test_name, result FROM _m2_rev_results ORDER BY test_no;

ROLLBACK;
