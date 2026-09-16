-- M2-T11: cross-domain milestone acceptance (5 scenarios)

BEGIN;

CREATE TEMP TABLE _m2_acc_results (
  test_no   integer PRIMARY KEY,
  test_name text NOT NULL,
  result    text NOT NULL CHECK (result IN ('PASS', 'FAIL'))
);

GRANT ALL ON TABLE _m2_acc_results TO authenticated, anon;

CREATE OR REPLACE FUNCTION _m2_acc_record(test_no integer, test_name text, passed boolean)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO _m2_acc_results (test_no, test_name, result)
  VALUES (test_no, test_name, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END);
END;
$$;

CREATE OR REPLACE FUNCTION _m2_acc_as_super() RETURNS void LANGUAGE plpgsql AS $$
BEGIN RESET ROLE; SET LOCAL ROLE postgres; END; $$;

CREATE OR REPLACE FUNCTION _m2_acc_as_auth(p_auth_id uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE; SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', p_auth_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_auth_id::text, 'role', 'authenticated')::text, true);
END; $$;

CREATE OR REPLACE FUNCTION _m2_acc_grant_admin(p_org uuid) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_user uuid; v_role uuid;
BEGIN
  PERFORM public.ensure_default_allocation_rules(p_org);
  SELECT id INTO v_user FROM app_user WHERE organization_id = p_org LIMIT 1;
  INSERT INTO role (organization_id, code) VALUES (p_org, 'acc_admin') RETURNING id INTO v_role;
  INSERT INTO role_permission (role_id, permission_id) SELECT v_role, p.id FROM permission p;
  INSERT INTO user_role (organization_id, user_id, role_id, effective_from, status) VALUES (p_org, v_user, v_role, CURRENT_DATE, 'active');
END; $$;

CREATE OR REPLACE FUNCTION _m2_acc_bootstrap()
RETURNS TABLE (
  org_id uuid, class_id uuid, student_id uuid, guardian_id uuid,
  enrollment_id uuid, teacher_id uuid, staff_user_id uuid, auth_id uuid
) LANGUAGE plpgsql AS $$
DECLARE
  v_org uuid; v_class uuid; v_student uuid; v_guardian uuid; v_enrollment uuid;
  v_teacher uuid; v_staff uuid; v_auth uuid; v_staff_auth uuid; v_course uuid;
BEGIN
  PERFORM _m2_acc_as_super();
  v_org := gen_random_uuid();
  v_auth := gen_random_uuid();
  v_staff_auth := gen_random_uuid();
  INSERT INTO organization (id, name) VALUES (v_org, 'M2 Acceptance Org');
  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at, is_sso_user, is_anonymous)
  VALUES
    (v_auth, (SELECT id FROM auth.instances LIMIT 1), 'authenticated', 'authenticated', 'acc-' || replace(v_auth::text, '-', '') || '@test.local', '', now(), now(), now(), false, false),
    (v_staff_auth, (SELECT id FROM auth.instances LIMIT 1), 'authenticated', 'authenticated', 'acc-staff-' || replace(v_staff_auth::text, '-', '') || '@test.local', '', now(), now(), now(), false, false);
  INSERT INTO app_user (organization_id, email, display_name, auth_user_id, status)
  VALUES (v_org, 'acc-admin@test.local', 'Acc Admin', v_auth, 'active');
  INSERT INTO app_user (organization_id, email, display_name, auth_user_id, status)
  VALUES (v_org, 'acc-staff@test.local', 'Acc Staff', v_staff_auth, 'active') RETURNING id INTO v_staff;
  INSERT INTO course (organization_id, code, name) VALUES (v_org, 'ACC1', 'Acceptance Course') RETURNING id INTO v_course;
  INSERT INTO class (organization_id, course_id, name, status)
  VALUES (v_org, v_course, 'Acceptance Class', 'active') RETURNING id INTO v_class;
  INSERT INTO student (organization_id, given_name, family_name) VALUES (v_org, 'Acc', 'Student') RETURNING id INTO v_student;
  INSERT INTO guardian (organization_id, given_name, family_name, email) VALUES (v_org, 'Acc', 'Guardian', 'acc-guardian@test.local') RETURNING id INTO v_guardian;
  INSERT INTO student_guardian (organization_id, student_id, guardian_id, is_primary_contact, is_billing_contact)
  VALUES (v_org, v_student, v_guardian, true, true);
  INSERT INTO enrollment (organization_id, student_id, class_id, start_date, status)
  VALUES (v_org, v_student, v_class, CURRENT_DATE, 'active') RETURNING id INTO v_enrollment;
  INSERT INTO teacher (organization_id, user_id, given_name, family_name, status)
  VALUES (v_org, v_staff, 'Acc', 'Teacher', 'active') RETURNING id INTO v_teacher;
  RETURN QUERY SELECT v_org, v_class, v_student, v_guardian, v_enrollment, v_teacher, v_staff, v_auth;
END; $$;

CREATE OR REPLACE FUNCTION _m2_acc_terms(
  p_org uuid, p_enrollment uuid, p_net bigint, p_basis text DEFAULT 'per_lesson'
) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE tid uuid;
BEGIN
  INSERT INTO enrollment_financial_terms (
    organization_id, enrollment_id, agreed_tuition_amount, discount_amount,
    net_tuition_amount, agreement_date, recognition_basis_code, status
  ) VALUES (p_org, p_enrollment, p_net, 0, p_net, CURRENT_DATE, p_basis, 'draft') RETURNING id INTO tid;
  INSERT INTO enrollment_payment_schedule_item (organization_id, enrollment_financial_terms_id, sequence_number, due_date, amount)
  VALUES (p_org, tid, 1, CURRENT_DATE, p_net / 2),
         (p_org, tid, 2, CURRENT_DATE + 30, p_net - (p_net / 2));
  UPDATE enrollment_financial_terms SET status = 'active' WHERE id = tid;
  RETURN tid;
END; $$;

CREATE OR REPLACE FUNCTION _m2_acc_generate_charges(p_terms uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM public.generate_enrollment_charges(p_terms);
END; $$;

CREATE OR REPLACE FUNCTION _m2_acc_session(
  p_org uuid, p_class uuid, p_teacher uuid, p_session_date date DEFAULT CURRENT_DATE
) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE sid uuid; v_start timestamptz;
BEGIN
  v_start := p_session_date::timestamptz + interval '9 hours';
  INSERT INTO teaching_session (organization_id, class_id, teacher_id, scheduled_start_at, scheduled_end_at, status)
  VALUES (p_org, p_class, p_teacher, v_start, v_start + interval '1 hour', 'completed')
  RETURNING id INTO sid;
  RETURN sid;
END; $$;

-- Case 1: enrollment lifecycle (terms → schedule → charges → partial pay → delivery → recognition)
DO $$
DECLARE
  b record; tid uuid; sid uuid; cid uuid; summary jsonb;
BEGIN
  SELECT * INTO b FROM _m2_acc_bootstrap();
  tid := _m2_acc_terms(b.org_id, b.enrollment_id, 12000000, 'per_lesson');
  PERFORM _m2_acc_grant_admin(b.org_id);
  PERFORM _m2_acc_as_auth(b.auth_id);
  PERFORM _m2_acc_generate_charges(tid);
  PERFORM public.initialize_enrollment_per_lesson_recognition(tid, 12);
  SELECT id INTO cid
  FROM charge
  WHERE enrollment_id = b.enrollment_id
  ORDER BY due_date, id
  LIMIT 1;
  PERFORM public.record_payment(
    b.guardian_id, 6000000, now(), 'cash', NULL, NULL, b.student_id, NULL, NULL,
    jsonb_build_array(jsonb_build_object('charge_id', cid, 'amount', 6000000))
  );
  sid := _m2_acc_session(b.org_id, b.class_id, b.teacher_id, CURRENT_DATE);
  INSERT INTO attendance (organization_id, teaching_session_id, enrollment_id, status)
  VALUES (b.org_id, sid, b.enrollment_id, 'present');
  PERFORM public.recognize_enrollment_revenue(b.enrollment_id);
  summary := public.get_enrollment_financial_summary(b.enrollment_id);
  PERFORM _m2_acc_record(
    1,
    'enrollment lifecycle cross-domain',
    (summary->>'net_tuition')::bigint = 12000000
      AND (summary->>'charged_amount')::bigint = 12000000
      AND (summary->>'allocated_amount')::bigint = 6000000
      AND (summary->>'outstanding_receivable')::bigint = 6000000
      AND (summary->>'recognized_revenue')::bigint = 1000000
      AND (summary->>'unrecognized_service_obligation')::bigint = 11000000
  );
END $$;

-- Case 2: fully prepaid but partially delivered
DO $$
DECLARE b record; tid uuid; sid uuid; summary jsonb; allocs jsonb;
BEGIN
  SELECT * INTO b FROM _m2_acc_bootstrap();
  tid := _m2_acc_terms(b.org_id, b.enrollment_id, 12000000, 'per_lesson');
  PERFORM _m2_acc_grant_admin(b.org_id);
  PERFORM _m2_acc_as_auth(b.auth_id);
  PERFORM _m2_acc_generate_charges(tid);
  PERFORM public.initialize_enrollment_per_lesson_recognition(tid, 12);
  SELECT COALESCE(jsonb_agg(jsonb_build_object('charge_id', c.id, 'amount', c.amount)), '[]'::jsonb)
  INTO allocs
  FROM charge c
  WHERE c.enrollment_id = b.enrollment_id AND c.status <> 'void';
  PERFORM public.record_payment(
    b.guardian_id, 12000000, now(), 'cash', NULL, NULL, b.student_id, NULL, NULL, allocs
  );
  sid := _m2_acc_session(b.org_id, b.class_id, b.teacher_id, CURRENT_DATE);
  INSERT INTO attendance (organization_id, teaching_session_id, enrollment_id, status)
  VALUES (b.org_id, sid, b.enrollment_id, 'present');
  PERFORM public.recognize_enrollment_revenue(b.enrollment_id);
  summary := public.get_enrollment_financial_summary(b.enrollment_id);
  PERFORM _m2_acc_record(
    2,
    'prepaid partial delivery cash-revenue independence',
    (summary->>'outstanding_receivable')::bigint = 0
      AND (summary->>'allocated_amount')::bigint = 12000000
      AND (summary->>'recognized_revenue')::bigint = 1000000
      AND (summary->>'recognized_revenue')::bigint < 12000000
      AND (summary->>'unrecognized_service_obligation')::bigint > 0
  );
END $$;

-- Case 3: delivered but unpaid
DO $$
DECLARE b record; tid uuid; sid uuid; summary jsonb;
BEGIN
  SELECT * INTO b FROM _m2_acc_bootstrap();
  tid := _m2_acc_terms(b.org_id, b.enrollment_id, 12000000, 'per_lesson');
  PERFORM _m2_acc_grant_admin(b.org_id);
  PERFORM _m2_acc_as_auth(b.auth_id);
  PERFORM _m2_acc_generate_charges(tid);
  PERFORM public.initialize_enrollment_per_lesson_recognition(tid, 12);
  sid := _m2_acc_session(b.org_id, b.class_id, b.teacher_id, CURRENT_DATE);
  INSERT INTO attendance (organization_id, teaching_session_id, enrollment_id, status)
  VALUES (b.org_id, sid, b.enrollment_id, 'present');
  PERFORM public.recognize_enrollment_revenue(b.enrollment_id);
  summary := public.get_enrollment_financial_summary(b.enrollment_id);
  PERFORM _m2_acc_record(
    3,
    'delivered unpaid revenue-cash independence',
    (summary->>'allocated_amount')::bigint = 0
      AND (summary->>'outstanding_receivable')::bigint = 12000000
      AND (summary->>'recognized_revenue')::bigint = 1000000
      AND (summary->>'recognized_revenue')::bigint > 0
  );
END $$;

-- Case 4: class economics reconciliation
DO $$
DECLARE
  b record; tid uuid; sid uuid; econ jsonb; period date := CURRENT_DATE;
BEGIN
  SELECT * INTO b FROM _m2_acc_bootstrap();
  PERFORM _m2_acc_grant_admin(b.org_id);
  PERFORM _m2_acc_as_auth(b.auth_id);
  tid := _m2_acc_terms(b.org_id, b.enrollment_id, 2000000, 'per_lesson');
  PERFORM public.initialize_enrollment_per_lesson_recognition(tid, 2);
  sid := _m2_acc_session(b.org_id, b.class_id, b.teacher_id, period);
  INSERT INTO attendance (organization_id, teaching_session_id, enrollment_id, status)
  VALUES (b.org_id, sid, b.enrollment_id, 'present');
  PERFORM public.recognize_enrollment_revenue(b.enrollment_id);
  PERFORM public.create_staff_compensation_rule(b.staff_user_id, 'personnel', 'per_session', 250000, period - 30);
  PERFORM public.generate_teaching_session_personnel_cost(sid);
  INSERT INTO expense (organization_id, expense_category_id, cost_group_id, amount, incurred_date, status)
  SELECT b.org_id, ec.id, cg.id, 600000, period, 'posted'
  FROM cost_group cg
  JOIN expense_category ec ON ec.cost_group_id = cg.id AND ec.organization_id = b.org_id
  WHERE cg.organization_id = b.org_id AND cg.cost_domain_code = 'operating_overhead'
  LIMIT 1;
  PERFORM public.run_class_cost_allocation(period);
  econ := public.get_class_economics(b.class_id, period, period);
  PERFORM _m2_acc_record(
    4,
    'class economics contribution reconciliation',
    (econ->>'recognized_revenue')::bigint = 1000000
      AND (econ->>'direct_personnel_cost')::bigint = 250000
      AND (econ->>'total_cost')::bigint
        = (econ->>'direct_personnel_cost')::bigint
          + (econ->>'allocated_personnel_cost')::bigint
          + (econ->>'allocated_operating_overhead')::bigint
          + (econ->>'allocated_marketing_sales')::bigint
          + (econ->>'allocated_depreciation')::bigint
      AND (econ->>'contribution')::bigint
        = (econ->>'recognized_revenue')::bigint - (econ->>'total_cost')::bigint
  );
END $$;

-- Case 5: simulation isolation from accounting facts
DO $$
DECLARE
  b record; sid uuid; c0 integer; p0 integer; r0 integer; pc0 integer; a0 integer;
  c1 integer; p1 integer; r1 integer; pc1 integer; a1 integer; proj jsonb; st text;
BEGIN
  SELECT * INTO b FROM _m2_acc_bootstrap();
  PERFORM _m2_acc_grant_admin(b.org_id);
  PERFORM _m2_acc_as_auth(b.auth_id);
  SELECT count(*) INTO c0 FROM charge;
  SELECT count(*) INTO p0 FROM payment;
  SELECT count(*) INTO r0 FROM revenue_recognition_event;
  SELECT count(*) INTO pc0 FROM personnel_cost_entry;
  SELECT count(*) INTO a0 FROM class_cost_allocation;
  sid := public.create_class_financial_scenario('Acceptance', 10, 5000000, 6, 24, b.class_id, 200000);
  proj := public.finalize_class_financial_scenario(sid);
  SELECT status INTO st FROM class_financial_scenario WHERE id = sid;
  SELECT count(*) INTO c1 FROM charge;
  SELECT count(*) INTO p1 FROM payment;
  SELECT count(*) INTO r1 FROM revenue_recognition_event;
  SELECT count(*) INTO pc1 FROM personnel_cost_entry;
  SELECT count(*) INTO a1 FROM class_cost_allocation;
  PERFORM _m2_acc_record(
    5,
    'simulation isolation from accounting',
    c1 = c0 AND p1 = p0 AND r1 = r0 AND pc1 = pc0 AND a1 = a0
      AND (proj->>'projected_revenue')::bigint = 50000000
      AND st = 'finalized'
      AND proj ? 'projected_contribution'
  );
END $$;

DO $$
DECLARE total integer; passed integer; failed integer;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE result = 'PASS'), count(*) FILTER (WHERE result = 'FAIL')
    INTO total, passed, failed FROM _m2_acc_results;
  RAISE NOTICE 'M2 milestone acceptance Tests: % / % passed (% failed)', passed, total, failed;
  IF failed > 0 OR total <> 5 THEN
    RAISE EXCEPTION 'M2 milestone acceptance tests failed: % of % (expected 5)', failed, total;
  END IF;
END $$;

ROLLBACK;
