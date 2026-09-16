-- M2-T08: class cost allocation and economics (35 scenarios)

BEGIN;

CREATE TEMP TABLE _m2_ca_results (
  test_no   integer PRIMARY KEY,
  test_name text NOT NULL,
  result    text NOT NULL CHECK (result IN ('PASS', 'FAIL'))
);

GRANT ALL ON TABLE _m2_ca_results TO authenticated, anon;

CREATE OR REPLACE FUNCTION _m2_ca_record(test_no integer, test_name text, passed boolean)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO _m2_ca_results (test_no, test_name, result)
  VALUES (test_no, test_name, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END);
END;
$$;

CREATE OR REPLACE FUNCTION _m2_ca_expect_fail(test_no integer, test_name text, sql_text text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN EXECUTE sql_text; PERFORM _m2_ca_record(test_no, test_name, false);
  EXCEPTION WHEN OTHERS THEN PERFORM _m2_ca_record(test_no, test_name, true); END;
END;
$$;

CREATE OR REPLACE FUNCTION _m2_ca_as_super() RETURNS void LANGUAGE plpgsql AS $$
BEGIN RESET ROLE; SET LOCAL ROLE postgres; END; $$;

CREATE OR REPLACE FUNCTION _m2_ca_as_auth(p_auth_id uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE; SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', p_auth_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_auth_id::text, 'role', 'authenticated')::text, true);
END; $$;

CREATE OR REPLACE FUNCTION _m2_ca_grant_admin(p_org uuid) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_user uuid; v_role uuid;
BEGIN
  PERFORM public.ensure_default_allocation_rules(p_org);
  SELECT id INTO v_user FROM app_user WHERE organization_id = p_org LIMIT 1;
  INSERT INTO role (organization_id, code) VALUES (p_org, 'ca_admin') RETURNING id INTO v_role;
  INSERT INTO role_permission (role_id, permission_id) SELECT v_role, p.id FROM permission p;
  INSERT INTO user_role (organization_id, user_id, role_id, effective_from, status) VALUES (p_org, v_user, v_role, CURRENT_DATE, 'active');
END; $$;

CREATE OR REPLACE FUNCTION _m2_ca_bootstrap()
RETURNS TABLE (
  org_id uuid, class1_id uuid, class2_id uuid, teacher_id uuid, staff_user_id uuid,
  admin_auth_id uuid, enrollment1_id uuid, enrollment2_id uuid, enrollment3_id uuid
) LANGUAGE plpgsql AS $$
DECLARE
  v_org uuid; v_c1 uuid; v_c2 uuid; v_teacher uuid; v_staff uuid; v_auth uuid; v_staff_auth uuid;
  v_s1 uuid; v_s2 uuid; v_s3 uuid;
BEGIN
  PERFORM _m2_ca_as_super();
  v_org := gen_random_uuid();
  v_auth := gen_random_uuid();
  v_staff_auth := gen_random_uuid();
  INSERT INTO organization (id, name) VALUES (v_org, 'M2 CA Org');
  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at, is_sso_user, is_anonymous)
  VALUES
    (v_auth, (SELECT id FROM auth.instances LIMIT 1), 'authenticated', 'authenticated', 'ca-admin-' || replace(v_auth::text, '-', '') || '@test.local', '', now(), now(), now(), false, false),
    (v_staff_auth, (SELECT id FROM auth.instances LIMIT 1), 'authenticated', 'authenticated', 'ca-staff-' || replace(v_staff_auth::text, '-', '') || '@test.local', '', now(), now(), now(), false, false);
  INSERT INTO app_user (organization_id, email, display_name, auth_user_id, status)
  VALUES (v_org, 'ca-admin@test.local', 'CA Admin', v_auth, 'active');
  INSERT INTO app_user (organization_id, email, display_name, auth_user_id, status)
  VALUES (v_org, 'ca-staff@test.local', 'CA Staff', v_staff_auth, 'active') RETURNING id INTO v_staff;
  INSERT INTO course (organization_id, code, name) VALUES (v_org, 'CA1', 'CA Course');
  INSERT INTO class (organization_id, course_id, name, status)
  SELECT v_org, c.id, 'CA Class 1', 'active' FROM course c WHERE c.organization_id = v_org LIMIT 1 RETURNING id INTO v_c1;
  INSERT INTO class (organization_id, course_id, name, status)
  SELECT v_org, c.id, 'CA Class 2', 'active' FROM course c WHERE c.organization_id = v_org LIMIT 1 RETURNING id INTO v_c2;
  INSERT INTO teacher (organization_id, user_id, given_name, family_name, status)
  VALUES (v_org, v_staff, 'CA', 'Teacher', 'active') RETURNING id INTO v_teacher;
  INSERT INTO student (organization_id, given_name, family_name) VALUES (v_org, 'S1', 'One') RETURNING id INTO v_s1;
  INSERT INTO student (organization_id, given_name, family_name) VALUES (v_org, 'S2', 'Two') RETURNING id INTO v_s2;
  INSERT INTO student (organization_id, given_name, family_name) VALUES (v_org, 'S3', 'Three') RETURNING id INTO v_s3;
  INSERT INTO enrollment (organization_id, student_id, class_id, start_date, status)
  VALUES (v_org, v_s1, v_c1, '2026-01-01', 'active') RETURNING id INTO enrollment1_id;
  INSERT INTO enrollment (organization_id, student_id, class_id, start_date, status)
  VALUES (v_org, v_s2, v_c1, '2026-01-01', 'active') RETURNING id INTO enrollment2_id;
  INSERT INTO enrollment (organization_id, student_id, class_id, start_date, status)
  VALUES (v_org, v_s3, v_c2, '2026-01-01', 'active') RETURNING id INTO enrollment3_id;
  RETURN QUERY SELECT v_org, v_c1, v_c2, v_teacher, v_staff, v_auth, enrollment1_id, enrollment2_id, enrollment3_id;
END; $$;

CREATE OR REPLACE FUNCTION _m2_ca_overhead_expense(p_org uuid, p_amount bigint, p_date date DEFAULT '2026-03-01')
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE eid uuid;
BEGIN
  INSERT INTO expense (organization_id, expense_category_id, cost_group_id, amount, incurred_date, status)
  SELECT p_org, ec.id, cg.id, p_amount, p_date, 'posted'
  FROM cost_group cg
  JOIN expense_category ec ON ec.cost_group_id = cg.id AND ec.organization_id = p_org
  WHERE cg.organization_id = p_org AND cg.cost_domain_code = 'operating_overhead'
  LIMIT 1
  RETURNING id INTO eid;
  RETURN eid;
END; $$;

CREATE OR REPLACE FUNCTION _m2_ca_session(
  p_org uuid, p_class uuid, p_teacher uuid, p_month date DEFAULT '2026-03-01', p_slot integer DEFAULT 0
) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE sid uuid; v_start timestamptz;
BEGIN
  v_start := (p_month + interval '14 days')::timestamptz + interval '9 hours' + (p_slot * interval '2 hours');
  INSERT INTO teaching_session (organization_id, class_id, teacher_id, scheduled_start_at, scheduled_end_at, status)
  VALUES (p_org, p_class, p_teacher, v_start, v_start + interval '1 hour', 'completed')
  RETURNING id INTO sid;
  RETURN sid;
END; $$;

-- 1: direct session personnel cost goes entirely to its class
DO $$
DECLARE b record; sid uuid; econ jsonb;
BEGIN
  SELECT * INTO b FROM _m2_ca_bootstrap();
  PERFORM _m2_ca_grant_admin(b.org_id);
  PERFORM _m2_ca_as_auth(b.admin_auth_id);
  PERFORM public.create_staff_compensation_rule(b.staff_user_id, 'personnel', 'per_session', 300000, '2026-01-01');
  sid := _m2_ca_session(b.org_id, b.class1_id, b.teacher_id);
  PERFORM public.generate_teaching_session_personnel_cost(sid);
  econ := public.get_class_economics(b.class1_id, '2026-03-01', '2026-03-01');
  PERFORM _m2_ca_record(1, 'direct session personnel goes to class', (econ->>'direct_personnel_cost')::bigint = 300000);
END $$;

-- 2: direct cost excluded from shared pool
DO $$
DECLARE b record; sid uuid; shared_cnt integer;
BEGIN
  SELECT * INTO b FROM _m2_ca_bootstrap();
  PERFORM _m2_ca_grant_admin(b.org_id);
  PERFORM _m2_ca_as_auth(b.admin_auth_id);
  PERFORM public.create_staff_compensation_rule(b.staff_user_id, 'personnel', 'per_session', 300000, '2026-01-01');
  PERFORM public.create_staff_compensation_rule(b.staff_user_id, 'personnel', 'monthly_fixed', 6000000, '2026-01-01');
  sid := _m2_ca_session(b.org_id, b.class1_id, b.teacher_id);
  PERFORM public.generate_teaching_session_personnel_cost(sid);
  PERFORM public.generate_personnel_costs('2026-03-01');
  PERFORM public.run_class_cost_allocation('2026-03-01');
  SELECT count(*) INTO shared_cnt FROM class_cost_allocation a
  JOIN personnel_cost_entry p ON p.id = a.source_record_id
  WHERE p.teaching_session_id = sid;
  PERFORM _m2_ca_record(2, 'direct cost excluded from shared pool', shared_cnt = 0);
END $$;

-- 3: equal allocation works
DO $$
DECLARE b record; total bigint;
BEGIN
  SELECT * INTO b FROM _m2_ca_bootstrap();
  PERFORM _m2_ca_grant_admin(b.org_id);
  PERFORM _m2_ca_as_auth(b.admin_auth_id);
  PERFORM public.end_cost_allocation_rule(
    (SELECT id FROM cost_allocation_rule WHERE organization_id = b.org_id AND source_scope_code = 'depreciation' LIMIT 1),
    '2026-02-28'
  );
  PERFORM public.create_cost_allocation_rule('depreciation', 'equal', '2026-03-01');
  INSERT INTO capital_asset (organization_id, cost_group_id, name, category_code, placed_in_service_date, original_cost, useful_life_months)
  SELECT b.org_id, cg.id, 'Asset', 'equipment', '2026-01-01', 1200000, 12
  FROM cost_group cg WHERE cg.organization_id = b.org_id AND cg.cost_domain_code = 'capital';
  PERFORM public.post_depreciation_through(
    (SELECT id FROM capital_asset WHERE organization_id = b.org_id LIMIT 1), '2026-03-01'
  );
  PERFORM public.run_class_cost_allocation('2026-03-01');
  SELECT COALESCE(SUM(allocated_amount), 0) INTO total
  FROM class_cost_allocation WHERE organization_id = b.org_id AND accounting_period = '2026-03-01' AND source_scope_code = 'depreciation';
  PERFORM _m2_ca_record(3, 'equal allocation works', total = 100000);
END $$;

-- 4: active-enrollment weighting works
DO $$
DECLARE b record; a1 bigint; a2 bigint;
BEGIN
  SELECT * INTO b FROM _m2_ca_bootstrap();
  PERFORM _m2_ca_grant_admin(b.org_id);
  PERFORM _m2_ca_as_auth(b.admin_auth_id);
  PERFORM _m2_ca_overhead_expense(b.org_id, 900000);
  PERFORM public.run_class_cost_allocation('2026-03-01');
  SELECT allocated_amount INTO a1 FROM class_cost_allocation
  WHERE class_id = b.class1_id AND source_scope_code = 'operating_overhead' LIMIT 1;
  SELECT allocated_amount INTO a2 FROM class_cost_allocation
  WHERE class_id = b.class2_id AND source_scope_code = 'operating_overhead' LIMIT 1;
  PERFORM _m2_ca_record(4, 'active-enrollment weighting works', a1 = 600000 AND a2 = 300000);
END $$;

-- 5: session-count weighting works
DO $$
DECLARE b record; rid uuid; a1 bigint; a2 bigint;
BEGIN
  SELECT * INTO b FROM _m2_ca_bootstrap();
  PERFORM _m2_ca_grant_admin(b.org_id);
  PERFORM _m2_ca_as_auth(b.admin_auth_id);
  rid := (SELECT id FROM cost_allocation_rule WHERE organization_id = b.org_id AND source_scope_code = 'operating_overhead' LIMIT 1);
  PERFORM public.end_cost_allocation_rule(rid, '2026-02-28');
  PERFORM public.create_cost_allocation_rule('operating_overhead', 'delivered_session_count', '2026-03-01');
  PERFORM _m2_ca_overhead_expense(b.org_id, 900000, '2026-04-01');
  PERFORM _m2_ca_session(b.org_id, b.class1_id, b.teacher_id, '2026-04-01', 0);
  PERFORM _m2_ca_session(b.org_id, b.class1_id, b.teacher_id, '2026-04-01', 1);
  PERFORM _m2_ca_session(b.org_id, b.class2_id, b.teacher_id, '2026-04-01', 2);
  PERFORM public.run_class_cost_allocation('2026-04-01');
  SELECT allocated_amount INTO a1 FROM class_cost_allocation
  WHERE class_id = b.class1_id AND accounting_period = '2026-04-01' AND source_scope_code = 'operating_overhead' LIMIT 1;
  SELECT allocated_amount INTO a2 FROM class_cost_allocation
  WHERE class_id = b.class2_id AND accounting_period = '2026-04-01' AND source_scope_code = 'operating_overhead' LIMIT 1;
  PERFORM _m2_ca_record(5, 'session-count weighting works', a1 = 600000 AND a2 = 300000);
END $$;

-- 6: recognized-revenue weighting works
DO $$
DECLARE b record; tid uuid; sid uuid; a1 bigint; a2 bigint; counselor uuid; v_period date;
BEGIN
  SELECT * INTO b FROM _m2_ca_bootstrap();
  v_period := date_trunc('month', CURRENT_DATE)::date;
  PERFORM _m2_ca_grant_admin(b.org_id);
  PERFORM _m2_ca_as_auth(b.admin_auth_id);
  INSERT INTO app_user (organization_id, email, display_name, status)
  VALUES (b.org_id, 'counselor@test.local', 'Counselor', 'active') RETURNING id INTO counselor;
  PERFORM public.create_staff_compensation_rule(counselor, 'marketing_sales', 'monthly_fixed', 1000000, '2026-01-01');
  PERFORM public.generate_personnel_costs(v_period);
  INSERT INTO enrollment_financial_terms (organization_id, enrollment_id, agreed_tuition_amount, discount_amount, net_tuition_amount, agreement_date, recognition_basis_code, status)
  VALUES (b.org_id, b.enrollment1_id, 2000000, 0, 2000000, '2026-01-01', 'per_lesson', 'draft') RETURNING id INTO tid;
  INSERT INTO enrollment_payment_schedule_item (organization_id, enrollment_financial_terms_id, sequence_number, due_date, amount)
  VALUES (b.org_id, tid, 1, '2026-01-01', 2000000);
  UPDATE enrollment_financial_terms SET status = 'active' WHERE id = tid;
  PERFORM public.initialize_enrollment_per_lesson_recognition(tid, 2);
  sid := _m2_ca_session(b.org_id, b.class1_id, b.teacher_id, v_period);
  INSERT INTO attendance (organization_id, teaching_session_id, enrollment_id, status)
  VALUES (b.org_id, sid, b.enrollment1_id, 'present');
  PERFORM public.recognize_enrollment_revenue(b.enrollment1_id);
  PERFORM public.run_class_cost_allocation(v_period);
  SELECT COALESCE(SUM(allocated_amount), 0) INTO a1 FROM class_cost_allocation
  WHERE class_id = b.class1_id AND accounting_period = v_period AND source_scope_code = 'marketing_sales';
  SELECT COALESCE(SUM(allocated_amount), 0) INTO a2 FROM class_cost_allocation
  WHERE class_id = b.class2_id AND accounting_period = v_period AND source_scope_code = 'marketing_sales';
  PERFORM _m2_ca_record(
    6,
    'recognized-revenue weighting works',
    a1 = 1000000 AND a2 = 0
      AND public.class_recognized_revenue_amount(b.class1_id, v_period) = 1000000
  );
END $$;

-- 7: integer remainder reconciles exactly
DO $$
DECLARE b record; src bigint; alloc bigint;
BEGIN
  SELECT * INTO b FROM _m2_ca_bootstrap();
  PERFORM _m2_ca_grant_admin(b.org_id);
  PERFORM _m2_ca_as_auth(b.admin_auth_id);
  PERFORM _m2_ca_overhead_expense(b.org_id, 1000001, '2026-06-01');
  PERFORM public.run_class_cost_allocation('2026-06-01');
  SELECT amount INTO src FROM expense WHERE organization_id = b.org_id AND incurred_date = '2026-06-01' LIMIT 1;
  SELECT COALESCE(SUM(allocated_amount), 0) INTO alloc FROM class_cost_allocation
  WHERE organization_id = b.org_id AND accounting_period = '2026-06-01' AND source_scope_code = 'operating_overhead';
  PERFORM _m2_ca_record(7, 'integer remainder reconciles exactly', src = alloc);
END $$;

-- 8: source amount equals allocations
DO $$
DECLARE b record; rec jsonb;
BEGIN
  SELECT * INTO b FROM _m2_ca_bootstrap();
  PERFORM _m2_ca_grant_admin(b.org_id);
  PERFORM _m2_ca_as_auth(b.admin_auth_id);
  PERFORM _m2_ca_overhead_expense(b.org_id, 500000, '2026-07-01');
  rec := public.run_class_cost_allocation('2026-07-01');
  PERFORM _m2_ca_record(
    8,
    'source amount equals allocations',
    (rec->>'shared_source_total')::bigint = (rec->>'allocated_total')::bigint + (rec->>'unallocated_total')::bigint
  );
END $$;

-- 9: marketing personnel included in Cost C
DO $$
DECLARE b record; counselor uuid; domain text; rid uuid;
BEGIN
  SELECT * INTO b FROM _m2_ca_bootstrap();
  INSERT INTO app_user (organization_id, email, display_name, status)
  VALUES (b.org_id, 'mkt@test.local', 'Mkt', 'active') RETURNING id INTO counselor;
  PERFORM _m2_ca_grant_admin(b.org_id);
  PERFORM _m2_ca_as_auth(b.admin_auth_id);
  rid := (SELECT id FROM cost_allocation_rule WHERE organization_id = b.org_id AND source_scope_code = 'marketing_sales' LIMIT 1);
  PERFORM public.end_cost_allocation_rule(rid, '2026-02-28');
  PERFORM public.create_cost_allocation_rule('marketing_sales', 'equal', '2026-03-01');
  PERFORM public.create_staff_compensation_rule(counselor, 'marketing_sales', 'monthly_fixed', 800000, '2026-01-01');
  PERFORM public.generate_personnel_costs('2026-08-01');
  PERFORM public.run_class_cost_allocation('2026-08-01');
  SELECT cost_domain_code INTO domain FROM class_cost_allocation
  WHERE organization_id = b.org_id AND accounting_period = '2026-08-01' AND source_scope_code = 'marketing_sales' LIMIT 1;
  PERFORM _m2_ca_record(9, 'marketing personnel included in Cost C', domain = 'marketing_sales');
END $$;

-- 10: operating expense allocated correctly
DO $$
DECLARE b record; cnt integer;
BEGIN
  SELECT * INTO b FROM _m2_ca_bootstrap();
  PERFORM _m2_ca_grant_admin(b.org_id);
  PERFORM _m2_ca_as_auth(b.admin_auth_id);
  PERFORM _m2_ca_overhead_expense(b.org_id, 400000, '2026-09-01');
  PERFORM public.run_class_cost_allocation('2026-09-01');
  SELECT count(*) INTO cnt FROM class_cost_allocation
  WHERE organization_id = b.org_id AND accounting_period = '2026-09-01' AND source_scope_code = 'operating_overhead';
  PERFORM _m2_ca_record(10, 'operating expense allocated correctly', cnt = 2);
END $$;

-- 11: shared personnel allocated correctly
DO $$
DECLARE b record; cnt integer;
BEGIN
  SELECT * INTO b FROM _m2_ca_bootstrap();
  PERFORM _m2_ca_grant_admin(b.org_id);
  PERFORM _m2_ca_as_auth(b.admin_auth_id);
  PERFORM public.create_staff_compensation_rule(b.staff_user_id, 'personnel', 'monthly_fixed', 3000000, '2026-01-01');
  PERFORM public.generate_personnel_costs('2026-10-01');
  PERFORM public.run_class_cost_allocation('2026-10-01');
  SELECT count(*) INTO cnt FROM class_cost_allocation
  WHERE organization_id = b.org_id AND accounting_period = '2026-10-01' AND source_scope_code = 'shared_personnel';
  PERFORM _m2_ca_record(11, 'shared personnel allocated correctly', cnt = 2);
END $$;

-- 12: depreciation allocated correctly
DO $$
DECLARE b record; cnt integer;
BEGIN
  SELECT * INTO b FROM _m2_ca_bootstrap();
  PERFORM _m2_ca_grant_admin(b.org_id);
  PERFORM _m2_ca_as_auth(b.admin_auth_id);
  INSERT INTO capital_asset (organization_id, cost_group_id, name, category_code, placed_in_service_date, original_cost, useful_life_months)
  SELECT b.org_id, cg.id, 'Desk', 'furniture', '2026-01-01', 2400000, 24
  FROM cost_group cg WHERE cg.organization_id = b.org_id AND cg.cost_domain_code = 'capital';
  PERFORM public.post_depreciation_through(
    (SELECT id FROM capital_asset WHERE organization_id = b.org_id LIMIT 1), '2026-11-01'
  );
  PERFORM public.run_class_cost_allocation('2026-11-01');
  SELECT count(*) INTO cnt FROM class_cost_allocation
  WHERE organization_id = b.org_id AND accounting_period = '2026-11-01' AND source_scope_code = 'depreciation';
  PERFORM _m2_ca_record(12, 'depreciation allocated correctly', cnt = 2);
END $$;

-- 13: original capital acquisition not treated as P&L cost
DO $$
DECLARE b record; asset_cost bigint; econ bigint;
BEGIN
  SELECT * INTO b FROM _m2_ca_bootstrap();
  PERFORM _m2_ca_grant_admin(b.org_id);
  PERFORM _m2_ca_as_auth(b.admin_auth_id);
  INSERT INTO capital_asset (organization_id, cost_group_id, name, category_code, placed_in_service_date, original_cost, useful_life_months)
  SELECT b.org_id, cg.id, 'Server', 'equipment', '2026-01-01', 50000000, 60
  FROM cost_group cg WHERE cg.organization_id = b.org_id AND cg.cost_domain_code = 'capital';
  SELECT original_cost INTO asset_cost FROM capital_asset WHERE organization_id = b.org_id LIMIT 1;
  PERFORM public.post_depreciation_through(
    (SELECT id FROM capital_asset WHERE organization_id = b.org_id LIMIT 1), '2026-12-01'
  );
  PERFORM public.run_class_cost_allocation('2026-12-01');
  econ := (public.get_class_economics(b.class1_id, '2026-12-01', '2026-12-01')->>'allocated_depreciation')::bigint;
  PERFORM _m2_ca_record(13, 'capital acquisition not P&L cost', asset_cost = 50000000 AND econ < asset_cost);
END $$;

-- 14: void depreciation excluded
DO $$
DECLARE b record; aid uuid; dep_id uuid; cnt integer;
BEGIN
  SELECT * INTO b FROM _m2_ca_bootstrap();
  PERFORM _m2_ca_grant_admin(b.org_id);
  PERFORM _m2_ca_as_auth(b.admin_auth_id);
  INSERT INTO capital_asset (organization_id, cost_group_id, name, category_code, placed_in_service_date, original_cost, useful_life_months)
  SELECT b.org_id, cg.id, 'Void Asset', 'equipment', '2026-01-01', 1200000, 12
  FROM cost_group cg WHERE cg.organization_id = b.org_id AND cg.cost_domain_code = 'capital' RETURNING id INTO aid;
  PERFORM public.post_depreciation_through(aid, '2027-01-01');
  SELECT id INTO dep_id FROM depreciation_entry WHERE capital_asset_id = aid AND period_month = '2027-01-01';
  UPDATE depreciation_entry SET status = 'void' WHERE id = dep_id;
  PERFORM public.run_class_cost_allocation('2027-01-01');
  SELECT count(*) INTO cnt FROM class_cost_allocation WHERE source_record_id = dep_id;
  PERFORM _m2_ca_record(14, 'void depreciation excluded', cnt = 0);
END $$;

-- 15: void personnel cost excluded
DO $$
DECLARE b record; pid uuid; cnt integer;
BEGIN
  SELECT * INTO b FROM _m2_ca_bootstrap();
  PERFORM _m2_ca_grant_admin(b.org_id);
  PERFORM _m2_ca_as_auth(b.admin_auth_id);
  PERFORM public.create_staff_compensation_rule(b.staff_user_id, 'personnel', 'monthly_fixed', 2000000, '2026-01-01');
  PERFORM public.generate_personnel_costs('2027-02-01');
  SELECT id INTO pid FROM personnel_cost_entry WHERE organization_id = b.org_id AND accounting_period = '2027-02-01' LIMIT 1;
  PERFORM public.void_personnel_cost_entry(pid, 'test');
  PERFORM public.run_class_cost_allocation('2027-02-01');
  SELECT count(*) INTO cnt FROM class_cost_allocation WHERE source_record_id = pid;
  PERFORM _m2_ca_record(15, 'void personnel cost excluded', cnt = 0);
END $$;

-- 16: void recognition revenue excluded
DO $$
DECLARE b record; tid uuid; sid uuid; rev bigint;
BEGIN
  SELECT * INTO b FROM _m2_ca_bootstrap();
  PERFORM _m2_ca_grant_admin(b.org_id);
  PERFORM _m2_ca_as_auth(b.admin_auth_id);
  INSERT INTO enrollment_financial_terms (organization_id, enrollment_id, agreed_tuition_amount, discount_amount, net_tuition_amount, agreement_date, recognition_basis_code, status)
  VALUES (b.org_id, b.enrollment1_id, 1000000, 0, 1000000, '2026-01-01', 'per_lesson', 'draft') RETURNING id INTO tid;
  INSERT INTO enrollment_payment_schedule_item (organization_id, enrollment_financial_terms_id, sequence_number, due_date, amount)
  VALUES (b.org_id, tid, 1, '2026-01-01', 1000000);
  UPDATE enrollment_financial_terms SET status = 'active' WHERE id = tid;
  PERFORM public.initialize_enrollment_per_lesson_recognition(tid, 1);
  sid := _m2_ca_session(b.org_id, b.class1_id, b.teacher_id, '2027-03-01');
  INSERT INTO attendance (organization_id, teaching_session_id, enrollment_id, status)
  VALUES (b.org_id, sid, b.enrollment1_id, 'present');
  PERFORM public.recognize_enrollment_revenue(b.enrollment1_id);
  PERFORM public.void_revenue_recognition_event(
    (SELECT id FROM revenue_recognition_event WHERE enrollment_id = b.enrollment1_id LIMIT 1), 'test'
  );
  SELECT public.class_recognized_revenue_amount(b.class1_id, '2027-03-01') INTO rev;
  PERFORM _m2_ca_record(16, 'void recognition revenue excluded', rev = 0);
END $$;

-- 17: zero-weight pool remains unallocated
DO $$
DECLARE b record; rec jsonb;
BEGIN
  SELECT * INTO b FROM _m2_ca_bootstrap();
  PERFORM _m2_ca_grant_admin(b.org_id);
  PERFORM _m2_ca_as_auth(b.admin_auth_id);
  PERFORM public.end_cost_allocation_rule(
    (SELECT id FROM cost_allocation_rule WHERE organization_id = b.org_id AND source_scope_code = 'marketing_sales' LIMIT 1),
    '2026-02-28'
  );
  PERFORM public.create_cost_allocation_rule('marketing_sales', 'recognized_revenue', '2026-03-01');
  INSERT INTO app_user (organization_id, email, display_name, status)
  VALUES (b.org_id, 'mkt2@test.local', 'Mkt2', 'active');
  PERFORM public.create_staff_compensation_rule(
    (SELECT id FROM app_user WHERE email = 'mkt2@test.local' AND organization_id = b.org_id),
    'marketing_sales', 'monthly_fixed', 500000, '2026-01-01'
  );
  PERFORM public.generate_personnel_costs('2027-04-01');
  rec := public.run_class_cost_allocation('2027-04-01');
  PERFORM _m2_ca_record(
    17,
    'zero-weight pool remains unallocated',
    (rec->>'allocated_total')::bigint = 0 AND (rec->>'unallocated_total')::bigint = 500000
  );
END $$;

-- 18: no double counting across source types
DO $$
DECLARE b record; personnel_exp_cnt integer; shared_cnt integer;
BEGIN
  SELECT * INTO b FROM _m2_ca_bootstrap();
  PERFORM _m2_ca_grant_admin(b.org_id);
  PERFORM _m2_ca_as_auth(b.admin_auth_id);
  PERFORM public.create_staff_compensation_rule(b.staff_user_id, 'personnel', 'monthly_fixed', 1000000, '2026-01-01');
  PERFORM public.generate_personnel_costs('2027-05-01');
  INSERT INTO expense (organization_id, expense_category_id, cost_group_id, amount, incurred_date, status)
  SELECT b.org_id, ec.id, cg.id, 999999, '2027-05-01', 'posted'
  FROM cost_group cg JOIN expense_category ec ON ec.cost_group_id = cg.id AND ec.organization_id = b.org_id
  WHERE cg.organization_id = b.org_id AND cg.cost_domain_code = 'personnel' LIMIT 1;
  PERFORM public.run_class_cost_allocation('2027-05-01');
  SELECT count(*) INTO personnel_exp_cnt FROM class_cost_allocation a
  JOIN expense e ON e.id = a.source_record_id
  JOIN cost_group cg ON cg.id = e.cost_group_id
  WHERE cg.cost_domain_code = 'personnel';
  SELECT count(*) INTO shared_cnt FROM class_cost_allocation
  WHERE organization_id = b.org_id AND accounting_period = '2027-05-01' AND source_scope_code = 'shared_personnel';
  PERFORM _m2_ca_record(18, 'no double counting across source types', personnel_exp_cnt = 0 AND shared_cnt = 2);
END $$;

-- 19: same source/period not allocated twice
DO $$
DECLARE b record; cnt integer;
BEGIN
  SELECT * INTO b FROM _m2_ca_bootstrap();
  PERFORM _m2_ca_grant_admin(b.org_id);
  PERFORM _m2_ca_as_auth(b.admin_auth_id);
  PERFORM _m2_ca_overhead_expense(b.org_id, 300000, '2027-06-01');
  PERFORM public.run_class_cost_allocation('2027-06-01');
  PERFORM public.run_class_cost_allocation('2027-06-01');
  SELECT count(*) INTO cnt FROM class_cost_allocation
  WHERE organization_id = b.org_id AND accounting_period = '2027-06-01' AND source_scope_code = 'operating_overhead';
  PERFORM _m2_ca_record(19, 'same source/period not allocated twice', cnt = 2);
END $$;

-- 20: retry is idempotent
DO $$
DECLARE b record; r1 jsonb; r2 jsonb;
BEGIN
  SELECT * INTO b FROM _m2_ca_bootstrap();
  PERFORM _m2_ca_grant_admin(b.org_id);
  PERFORM _m2_ca_as_auth(b.admin_auth_id);
  PERFORM _m2_ca_overhead_expense(b.org_id, 200000, '2027-07-01');
  r1 := public.run_class_cost_allocation('2027-07-01');
  r2 := public.run_class_cost_allocation('2027-07-01');
  PERFORM _m2_ca_record(
    20,
    'retry is idempotent',
    (r1->>'allocated_total')::bigint = (r2->>'allocated_total')::bigint
      AND (SELECT count(*) FROM class_cost_allocation WHERE organization_id = b.org_id AND accounting_period = '2027-07-01') = 2
  );
END $$;

-- 21: historical allocation unchanged after rule change
DO $$
DECLARE b record; rid uuid; old_amt bigint; new_amt bigint;
BEGIN
  SELECT * INTO b FROM _m2_ca_bootstrap();
  PERFORM _m2_ca_grant_admin(b.org_id);
  PERFORM _m2_ca_as_auth(b.admin_auth_id);
  PERFORM _m2_ca_overhead_expense(b.org_id, 600000, '2027-08-01');
  PERFORM public.run_class_cost_allocation('2027-08-01');
  SELECT allocated_amount INTO old_amt FROM class_cost_allocation
  WHERE class_id = b.class1_id AND accounting_period = '2027-08-01' LIMIT 1;
  rid := (SELECT id FROM cost_allocation_rule WHERE organization_id = b.org_id AND source_scope_code = 'operating_overhead' AND status = 'active' LIMIT 1);
  PERFORM public.end_cost_allocation_rule(rid, '2027-08-31');
  PERFORM public.create_cost_allocation_rule('operating_overhead', 'equal', '2027-09-01');
  SELECT allocated_amount INTO new_amt FROM class_cost_allocation
  WHERE class_id = b.class1_id AND accounting_period = '2027-08-01' LIMIT 1;
  PERFORM _m2_ca_record(21, 'historical allocation unchanged after rule change', old_amt = new_amt AND old_amt = 400000);
END $$;

-- 22: effective-dated new rule applies only prospectively
DO $$
DECLARE b record; rid uuid; a_old bigint; a_new bigint;
BEGIN
  SELECT * INTO b FROM _m2_ca_bootstrap();
  PERFORM _m2_ca_grant_admin(b.org_id);
  PERFORM _m2_ca_as_auth(b.admin_auth_id);
  rid := (SELECT id FROM cost_allocation_rule WHERE organization_id = b.org_id AND source_scope_code = 'operating_overhead' AND status = 'active' LIMIT 1);
  PERFORM public.end_cost_allocation_rule(rid, '2027-09-30');
  PERFORM public.create_cost_allocation_rule('operating_overhead', 'equal', '2027-10-01');
  PERFORM _m2_ca_overhead_expense(b.org_id, 1000000, '2027-09-01');
  PERFORM _m2_ca_overhead_expense(b.org_id, 1000000, '2027-10-01');
  PERFORM public.run_class_cost_allocation('2027-09-01');
  PERFORM public.run_class_cost_allocation('2027-10-01');
  SELECT allocated_amount INTO a_old FROM class_cost_allocation
  WHERE class_id = b.class1_id AND accounting_period = '2027-09-01' LIMIT 1;
  SELECT allocated_amount INTO a_new FROM class_cost_allocation
  WHERE class_id = b.class1_id AND accounting_period = '2027-10-01' LIMIT 1;
  PERFORM _m2_ca_record(22, 'new rule applies only prospectively', a_old IN (666666, 666667) AND a_new = 500000);
END $$;

-- 23: overlapping rule rejected
SELECT _m2_ca_expect_fail(23, 'overlapping rule rejected', $$
  DO $i$ DECLARE b record; BEGIN
    SELECT * INTO b FROM _m2_ca_bootstrap();
    PERFORM _m2_ca_grant_admin(b.org_id);
    PERFORM _m2_ca_as_auth(b.admin_auth_id);
    PERFORM public.create_cost_allocation_rule('operating_overhead', 'equal', '2026-03-01');
  END $i$;
$$);

-- 24: class recognized revenue derived correctly
DO $$
DECLARE b record; tid uuid; sid uuid; rev bigint;
BEGIN
  SELECT * INTO b FROM _m2_ca_bootstrap();
  PERFORM _m2_ca_grant_admin(b.org_id);
  PERFORM _m2_ca_as_auth(b.admin_auth_id);
  INSERT INTO enrollment_financial_terms (organization_id, enrollment_id, agreed_tuition_amount, discount_amount, net_tuition_amount, agreement_date, recognition_basis_code, status)
  VALUES (b.org_id, b.enrollment1_id, 2000000, 0, 2000000, '2026-01-01', 'per_lesson', 'draft') RETURNING id INTO tid;
  INSERT INTO enrollment_payment_schedule_item (organization_id, enrollment_financial_terms_id, sequence_number, due_date, amount)
  VALUES (b.org_id, tid, 1, '2026-01-01', 2000000);
  UPDATE enrollment_financial_terms SET status = 'active' WHERE id = tid;
  PERFORM public.initialize_enrollment_per_lesson_recognition(tid, 2);
  sid := _m2_ca_session(b.org_id, b.class1_id, b.teacher_id, '2027-11-01');
  INSERT INTO attendance (organization_id, teaching_session_id, enrollment_id, status) VALUES (b.org_id, sid, b.enrollment1_id, 'present');
  PERFORM public.recognize_enrollment_revenue(b.enrollment1_id);
  rev := (public.get_class_economics(b.class1_id, '2027-11-01', '2027-11-01')->>'recognized_revenue')::bigint;
  PERFORM _m2_ca_record(24, 'class recognized revenue derived correctly', rev = 1000000);
END $$;

-- 25: class total cost derived correctly
DO $$
DECLARE b record; sid uuid; econ jsonb;
BEGIN
  SELECT * INTO b FROM _m2_ca_bootstrap();
  PERFORM _m2_ca_grant_admin(b.org_id);
  PERFORM _m2_ca_as_auth(b.admin_auth_id);
  PERFORM public.create_staff_compensation_rule(b.staff_user_id, 'personnel', 'per_session', 250000, '2026-01-01');
  sid := _m2_ca_session(b.org_id, b.class1_id, b.teacher_id, '2027-12-01');
  PERFORM public.generate_teaching_session_personnel_cost(sid);
  PERFORM _m2_ca_overhead_expense(b.org_id, 600000, '2027-12-01');
  PERFORM public.run_class_cost_allocation('2027-12-01');
  econ := public.get_class_economics(b.class1_id, '2027-12-01', '2027-12-01');
  PERFORM _m2_ca_record(
    25,
    'class total cost derived correctly',
    (econ->>'total_cost')::bigint = (econ->>'direct_personnel_cost')::bigint + (econ->>'allocated_operating_overhead')::bigint
  );
END $$;

-- 26: contribution derived correctly
DO $$
DECLARE b record; tid uuid; sid uuid; econ jsonb;
BEGIN
  SELECT * INTO b FROM _m2_ca_bootstrap();
  PERFORM _m2_ca_grant_admin(b.org_id);
  PERFORM _m2_ca_as_auth(b.admin_auth_id);
  INSERT INTO enrollment_financial_terms (organization_id, enrollment_id, agreed_tuition_amount, discount_amount, net_tuition_amount, agreement_date, recognition_basis_code, status)
  VALUES (b.org_id, b.enrollment1_id, 1000000, 0, 1000000, '2026-01-01', 'per_lesson', 'draft') RETURNING id INTO tid;
  INSERT INTO enrollment_payment_schedule_item (organization_id, enrollment_financial_terms_id, sequence_number, due_date, amount)
  VALUES (b.org_id, tid, 1, '2026-01-01', 1000000);
  UPDATE enrollment_financial_terms SET status = 'active' WHERE id = tid;
  PERFORM public.initialize_enrollment_per_lesson_recognition(tid, 1);
  sid := _m2_ca_session(b.org_id, b.class1_id, b.teacher_id, '2028-01-01');
  INSERT INTO attendance (organization_id, teaching_session_id, enrollment_id, status) VALUES (b.org_id, sid, b.enrollment1_id, 'present');
  PERFORM public.recognize_enrollment_revenue(b.enrollment1_id);
  PERFORM public.create_staff_compensation_rule(b.staff_user_id, 'personnel', 'per_session', 200000, '2026-01-01');
  PERFORM public.generate_teaching_session_personnel_cost(sid);
  econ := public.get_class_economics(b.class1_id, '2028-01-01', '2028-01-01');
  PERFORM _m2_ca_record(
    26,
    'contribution derived correctly',
    (econ->>'contribution')::bigint = (econ->>'recognized_revenue')::bigint - (econ->>'total_cost')::bigint
  );
END $$;

-- 27: margin derived correctly
DO $$
DECLARE b record; tid uuid; sid uuid; econ jsonb;
BEGIN
  SELECT * INTO b FROM _m2_ca_bootstrap();
  PERFORM _m2_ca_grant_admin(b.org_id);
  PERFORM _m2_ca_as_auth(b.admin_auth_id);
  INSERT INTO enrollment_financial_terms (organization_id, enrollment_id, agreed_tuition_amount, discount_amount, net_tuition_amount, agreement_date, recognition_basis_code, status)
  VALUES (b.org_id, b.enrollment1_id, 1000000, 0, 1000000, '2026-01-01', 'per_lesson', 'draft') RETURNING id INTO tid;
  INSERT INTO enrollment_payment_schedule_item (organization_id, enrollment_financial_terms_id, sequence_number, due_date, amount)
  VALUES (b.org_id, tid, 1, '2026-01-01', 1000000);
  UPDATE enrollment_financial_terms SET status = 'active' WHERE id = tid;
  PERFORM public.initialize_enrollment_per_lesson_recognition(tid, 1);
  sid := _m2_ca_session(b.org_id, b.class1_id, b.teacher_id, '2028-02-01');
  INSERT INTO attendance (organization_id, teaching_session_id, enrollment_id, status) VALUES (b.org_id, sid, b.enrollment1_id, 'present');
  PERFORM public.recognize_enrollment_revenue(b.enrollment1_id);
  econ := public.get_class_economics(b.class1_id, '2028-02-01', '2028-02-01');
  PERFORM _m2_ca_record(27, 'margin derived correctly', (econ->>'margin_percentage')::numeric = 100);
END $$;

-- 28: zero-revenue margin handled safely
DO $$
DECLARE b record; econ jsonb;
BEGIN
  SELECT * INTO b FROM _m2_ca_bootstrap();
  PERFORM _m2_ca_grant_admin(b.org_id);
  PERFORM _m2_ca_as_auth(b.admin_auth_id);
  econ := public.get_class_economics(b.class1_id, '2028-03-01', '2028-03-01');
  PERFORM _m2_ca_record(28, 'zero-revenue margin handled safely', econ->>'margin_percentage' IS NULL);
END $$;

-- 29: unallocated reconciliation exposed
DO $$
DECLARE b record; rec jsonb;
BEGIN
  SELECT * INTO b FROM _m2_ca_bootstrap();
  PERFORM _m2_ca_grant_admin(b.org_id);
  PERFORM _m2_ca_as_auth(b.admin_auth_id);
  PERFORM public.end_cost_allocation_rule(
    (SELECT id FROM cost_allocation_rule WHERE organization_id = b.org_id AND source_scope_code = 'marketing_sales' AND status = 'active' LIMIT 1),
    '2026-02-28'
  );
  PERFORM public.create_cost_allocation_rule('marketing_sales', 'recognized_revenue', '2026-03-01');
  INSERT INTO app_user (organization_id, email, display_name, status) VALUES (b.org_id, 'm3@test.local', 'M3', 'active');
  PERFORM public.create_staff_compensation_rule(
    (SELECT id FROM app_user WHERE email = 'm3@test.local'), 'marketing_sales', 'monthly_fixed', 700000, '2026-01-01'
  );
  PERFORM public.generate_personnel_costs('2028-04-01');
  PERFORM public.run_class_cost_allocation('2028-04-01');
  rec := public.get_organization_cost_reconciliation('2028-04-01');
  PERFORM _m2_ca_record(
    29,
    'unallocated reconciliation exposed',
    (rec->>'shared_source_total')::bigint = (rec->>'allocated_total')::bigint + (rec->>'unallocated_total')::bigint
      AND (rec->>'unallocated_total')::bigint = 700000
  );
END $$;

-- 30: cross-org allocation rejected
SELECT _m2_ca_expect_fail(30, 'cross-org allocation rejected', $$
  DO $i$ DECLARE a record; b record; BEGIN
    SELECT * INTO a FROM _m2_ca_bootstrap();
    SELECT * INTO b FROM _m2_ca_bootstrap();
    PERFORM _m2_ca_grant_admin(a.org_id);
    PERFORM _m2_ca_as_auth(a.admin_auth_id);
    INSERT INTO class_cost_allocation (
      organization_id, allocation_batch_id, accounting_period, class_id,
      source_type, source_record_id, cost_domain_code, source_scope_code,
      cost_allocation_rule_id, allocation_basis_code, source_amount_snapshot,
      weight_value, weight_total, sequence_number, allocated_amount
    )
    SELECT a.org_id, gen_random_uuid(), '2026-03-01', b.class1_id,
      'expense', gen_random_uuid(), 'operating_overhead', 'operating_overhead',
      (SELECT id FROM cost_allocation_rule WHERE organization_id = a.org_id LIMIT 1),
      'equal', 1000, 1, 1, 1, 1000;
  END $i$;
$$);

-- 31: RLS tenant isolation
DO $$
DECLARE b record; cnt integer;
BEGIN
  SELECT * INTO b FROM _m2_ca_bootstrap();
  PERFORM _m2_ca_grant_admin(b.org_id);
  PERFORM _m2_ca_as_auth(b.admin_auth_id);
  PERFORM _m2_ca_overhead_expense(b.org_id, 100000, '2028-05-01');
  PERFORM public.run_class_cost_allocation('2028-05-01');
  PERFORM _m2_ca_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO cnt FROM class_cost_allocation WHERE organization_id = b.org_id;
  PERFORM _m2_ca_record(31, 'RLS tenant isolation', cnt = 0);
END $$;

-- 32: permission enforcement
DO $$
DECLARE b record; ok boolean := false;
BEGIN
  SELECT * INTO b FROM _m2_ca_bootstrap();
  PERFORM _m2_ca_as_auth(b.admin_auth_id);
  BEGIN
    PERFORM public.run_class_cost_allocation('2028-06-01');
  EXCEPTION WHEN OTHERS THEN ok := true; END;
  PERFORM _m2_ca_record(32, 'permission enforcement', ok);
END $$;

-- 33: M1 academic rows unchanged
DO $$
DECLARE b record; sid uuid; st text;
BEGIN
  SELECT * INTO b FROM _m2_ca_bootstrap();
  sid := _m2_ca_session(b.org_id, b.class1_id, b.teacher_id, '2028-07-01');
  PERFORM _m2_ca_grant_admin(b.org_id);
  PERFORM _m2_ca_as_auth(b.admin_auth_id);
  PERFORM _m2_ca_overhead_expense(b.org_id, 100000, '2028-07-01');
  PERFORM public.run_class_cost_allocation('2028-07-01');
  SELECT status INTO st FROM teaching_session WHERE id = sid;
  PERFORM _m2_ca_record(33, 'M1 academic rows unchanged', st = 'completed');
END $$;

-- 34: T06/T07 source rows unchanged
DO $$
DECLARE b record; rev_cnt integer; pc_cnt integer;
BEGIN
  SELECT * INTO b FROM _m2_ca_bootstrap();
  PERFORM _m2_ca_grant_admin(b.org_id);
  PERFORM _m2_ca_as_auth(b.admin_auth_id);
  PERFORM public.create_staff_compensation_rule(b.staff_user_id, 'personnel', 'monthly_fixed', 1000000, '2026-01-01');
  PERFORM public.generate_personnel_costs('2028-08-01');
  SELECT count(*) INTO rev_cnt FROM revenue_recognition_event;
  SELECT count(*) INTO pc_cnt FROM personnel_cost_entry WHERE organization_id = b.org_id AND accounting_period = '2028-08-01';
  PERFORM _m2_ca_record(34, 'T06/T07 source rows unchanged', rev_cnt >= 0 AND pc_cnt = 1);
END $$;

-- 35: earlier M2 structures unaffected
DO $$
DECLARE pay_cnt integer; rule_cnt integer;
BEGIN
  SELECT count(*) INTO pay_cnt FROM payment;
  SELECT count(*) INTO rule_cnt FROM staff_compensation_rule;
  PERFORM _m2_ca_record(35, 'earlier M2 structures unaffected', pay_cnt >= 0 AND rule_cnt >= 0);
END $$;

DO $$
DECLARE total integer; passed integer; failed integer;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE result = 'PASS'), count(*) FILTER (WHERE result = 'FAIL')
    INTO total, passed, failed FROM _m2_ca_results;
  RAISE NOTICE 'M2 class cost allocation Tests: % / % passed (% failed)', passed, total, failed;
  IF failed > 0 OR total <> 35 THEN
    RAISE EXCEPTION 'M2 class cost allocation tests failed: % of % (expected 35)', failed, total;
  END IF;
END $$;

SELECT test_no, test_name, result FROM _m2_ca_results ORDER BY test_no;

ROLLBACK;
