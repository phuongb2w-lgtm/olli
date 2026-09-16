-- M2-T09: class financial simulator (35 scenarios)

BEGIN;

CREATE TEMP TABLE _m2_sim_results (
  test_no   integer PRIMARY KEY,
  test_name text NOT NULL,
  result    text NOT NULL CHECK (result IN ('PASS', 'FAIL'))
);

GRANT ALL ON TABLE _m2_sim_results TO authenticated, anon;

CREATE OR REPLACE FUNCTION _m2_sim_record(test_no integer, test_name text, passed boolean)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO _m2_sim_results (test_no, test_name, result)
  VALUES (test_no, test_name, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END);
END;
$$;

CREATE OR REPLACE FUNCTION _m2_sim_expect_fail(test_no integer, test_name text, sql_text text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN EXECUTE sql_text; PERFORM _m2_sim_record(test_no, test_name, false);
  EXCEPTION WHEN OTHERS THEN PERFORM _m2_sim_record(test_no, test_name, true); END;
END;
$$;

CREATE OR REPLACE FUNCTION _m2_sim_as_super() RETURNS void LANGUAGE plpgsql AS $$
BEGIN RESET ROLE; SET LOCAL ROLE postgres; END; $$;

CREATE OR REPLACE FUNCTION _m2_sim_as_auth(p_auth_id uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE; SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', p_auth_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_auth_id::text, 'role', 'authenticated')::text, true);
END; $$;

CREATE OR REPLACE FUNCTION _m2_sim_grant_admin(p_org uuid) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_user uuid; v_role uuid;
BEGIN
  PERFORM public.ensure_default_allocation_rules(p_org);
  SELECT id INTO v_user FROM app_user WHERE organization_id = p_org LIMIT 1;
  INSERT INTO role (organization_id, code) VALUES (p_org, 'sim_admin') RETURNING id INTO v_role;
  INSERT INTO role_permission (role_id, permission_id) SELECT v_role, p.id FROM permission p;
  INSERT INTO user_role (organization_id, user_id, role_id, effective_from, status) VALUES (p_org, v_user, v_role, CURRENT_DATE, 'active');
END; $$;

CREATE OR REPLACE FUNCTION _m2_sim_bootstrap()
RETURNS TABLE (
  org_id uuid, class_id uuid, teacher_id uuid, staff_user_id uuid, admin_auth_id uuid
) LANGUAGE plpgsql AS $$
DECLARE
  v_org uuid; v_class uuid; v_teacher uuid; v_staff uuid; v_auth uuid; v_staff_auth uuid; v_course uuid;
BEGIN
  PERFORM _m2_sim_as_super();
  v_org := gen_random_uuid();
  v_auth := gen_random_uuid();
  v_staff_auth := gen_random_uuid();
  INSERT INTO organization (id, name) VALUES (v_org, 'M2 Sim Org');
  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at, is_sso_user, is_anonymous)
  VALUES
    (v_auth, (SELECT id FROM auth.instances LIMIT 1), 'authenticated', 'authenticated', 'sim-admin-' || replace(v_auth::text, '-', '') || '@test.local', '', now(), now(), now(), false, false),
    (v_staff_auth, (SELECT id FROM auth.instances LIMIT 1), 'authenticated', 'authenticated', 'sim-staff-' || replace(v_staff_auth::text, '-', '') || '@test.local', '', now(), now(), now(), false, false);
  INSERT INTO app_user (organization_id, email, display_name, auth_user_id, status)
  VALUES (v_org, 'sim-admin@test.local', 'Sim Admin', v_auth, 'active');
  INSERT INTO app_user (organization_id, email, display_name, auth_user_id, status)
  VALUES (v_org, 'sim-staff@test.local', 'Sim Staff', v_staff_auth, 'active') RETURNING id INTO v_staff;
  INSERT INTO course (organization_id, code, name) VALUES (v_org, 'SIM1', 'Sim Course') RETURNING id INTO v_course;
  INSERT INTO class (organization_id, course_id, name, status, capacity)
  VALUES (v_org, v_course, 'Sim Class', 'planned', 20) RETURNING id INTO v_class;
  INSERT INTO teacher (organization_id, user_id, given_name, family_name, status)
  VALUES (v_org, v_staff, 'Sim', 'Teacher', 'active') RETURNING id INTO v_teacher;
  RETURN QUERY SELECT v_org, v_class, v_teacher, v_staff, v_auth;
END; $$;

-- 1: create scenario
DO $$
DECLARE b record; sid uuid; row_cnt integer;
BEGIN
  SELECT * INTO b FROM _m2_sim_bootstrap();
  PERFORM _m2_sim_grant_admin(b.org_id);
  PERFORM _m2_sim_as_auth(b.admin_auth_id);
  sid := public.create_class_financial_scenario(
    'Base', 10, 5000000, 6, 24, b.class_id, 200000, NULL, 100000, 50000, 300000, 'one_time', 20000
  );
  SELECT count(*) INTO row_cnt FROM class_financial_scenario WHERE id = sid AND status = 'draft';
  PERFORM _m2_sim_record(1, 'create scenario', sid IS NOT NULL AND row_cnt = 1);
END $$;

-- 2: multiple scenarios per class
DO $$
DECLARE b record; s1 uuid; s2 uuid; cnt integer;
BEGIN
  SELECT * INTO b FROM _m2_sim_bootstrap();
  PERFORM _m2_sim_grant_admin(b.org_id);
  PERFORM _m2_sim_as_auth(b.admin_auth_id);
  s1 := public.create_class_financial_scenario('Conservative', 8, 4500000, 6, 24, b.class_id);
  s2 := public.create_class_financial_scenario('Growth', 15, 5500000, 6, 24, b.class_id);
  SELECT count(*) INTO cnt FROM class_financial_scenario WHERE class_id = b.class_id;
  PERFORM _m2_sim_record(2, 'multiple scenarios per class', cnt = 2 AND s1 <> s2);
END $$;

-- 3: scenario without class link
DO $$
DECLARE b record; sid uuid; econ jsonb;
BEGIN
  SELECT * INTO b FROM _m2_sim_bootstrap();
  PERFORM _m2_sim_grant_admin(b.org_id);
  PERFORM _m2_sim_as_auth(b.admin_auth_id);
  sid := public.create_class_financial_scenario('Pre-class', 12, 4000000, 4, 16, NULL, 150000);
  econ := public.calculate_scenario_economics(sid);
  PERFORM _m2_sim_record(
    3, 'scenario without class link',
    (SELECT class_id IS NULL FROM class_financial_scenario WHERE id = sid)
      AND (econ->>'projected_revenue')::bigint = 48000000
  );
END $$;

-- 4: uniform tuition projected revenue
DO $$
DECLARE b record; sid uuid; econ jsonb;
BEGIN
  SELECT * INTO b FROM _m2_sim_bootstrap();
  PERFORM _m2_sim_grant_admin(b.org_id);
  PERFORM _m2_sim_as_auth(b.admin_auth_id);
  sid := public.create_class_financial_scenario('Uniform', 10, 3000000, 3, 12, b.class_id);
  econ := public.calculate_scenario_economics(sid);
  PERFORM _m2_sim_record(4, 'uniform tuition projected revenue', (econ->>'projected_revenue')::bigint = 30000000);
END $$;

-- 5: class does not become authoritative tuition
DO $$
DECLARE b record; sid uuid; econ jsonb;
BEGIN
  SELECT * INTO b FROM _m2_sim_bootstrap();
  PERFORM _m2_sim_grant_admin(b.org_id);
  PERFORM _m2_sim_as_auth(b.admin_auth_id);
  sid := public.create_class_financial_scenario('Assumption', 5, 2500000, 3, 12, b.class_id);
  PERFORM _m2_sim_as_super();
  UPDATE class SET name = 'Renamed' WHERE id = b.class_id;
  PERFORM _m2_sim_as_auth(b.admin_auth_id);
  econ := public.calculate_scenario_economics(sid);
  PERFORM _m2_sim_record(
    5, 'class does not become authoritative tuition',
    (SELECT assumed_net_tuition_per_learner FROM class_financial_scenario WHERE id = sid) = 2500000
      AND (econ->>'projected_revenue')::bigint = 12500000
  );
END $$;

-- 6: planned session-derived teacher cost
DO $$
DECLARE b record; sid uuid; econ jsonb;
BEGIN
  SELECT * INTO b FROM _m2_sim_bootstrap();
  PERFORM _m2_sim_grant_admin(b.org_id);
  PERFORM _m2_sim_as_auth(b.admin_auth_id);
  sid := public.create_class_financial_scenario('Sessions', 10, 5000000, 6, 20, b.class_id, 100000);
  econ := public.calculate_scenario_economics(sid);
  PERFORM _m2_sim_record(6, 'planned session-derived teacher cost', (econ->>'projected_direct_personnel')::bigint = 2000000);
END $$;

-- 7: compensation rule snapshot works
DO $$
DECLARE b record; sid uuid; rule_id uuid; econ1 jsonb; econ2 jsonb;
BEGIN
  SELECT * INTO b FROM _m2_sim_bootstrap();
  PERFORM _m2_sim_grant_admin(b.org_id);
  PERFORM _m2_sim_as_auth(b.admin_auth_id);
  rule_id := public.create_staff_compensation_rule(b.staff_user_id, 'personnel', 'per_session', 120000, '2026-01-01');
  sid := public.create_class_financial_scenario('Rule', 10, 5000000, 6, 10, b.class_id, NULL, rule_id);
  econ1 := public.finalize_class_financial_scenario(sid);
  PERFORM _m2_sim_as_super();
  UPDATE staff_compensation_rule SET amount = 999999 WHERE id = rule_id;
  PERFORM _m2_sim_as_auth(b.admin_auth_id);
  econ2 := public.calculate_scenario_economics(sid);
  PERFORM _m2_sim_record(
    7, 'compensation rule snapshot works',
    (econ1->>'projected_direct_personnel')::bigint = 1200000
      AND (econ2->>'projected_direct_personnel')::bigint = 1200000
      AND (SELECT per_session_rate_snapshot FROM class_financial_scenario WHERE id = sid) = 120000
  );
END $$;

-- 8: explicit teacher-rate override works
DO $$
DECLARE b record; sid uuid; rule_id uuid; econ jsonb;
BEGIN
  SELECT * INTO b FROM _m2_sim_bootstrap();
  PERFORM _m2_sim_grant_admin(b.org_id);
  PERFORM _m2_sim_as_auth(b.admin_auth_id);
  rule_id := public.create_staff_compensation_rule(b.staff_user_id, 'personnel', 'per_session', 120000, '2026-01-01');
  sid := public.create_class_financial_scenario('Override', 10, 5000000, 6, 10, b.class_id, 80000, rule_id);
  econ := public.calculate_scenario_economics(sid);
  PERFORM _m2_sim_record(8, 'explicit teacher-rate override works', (econ->>'projected_direct_personnel')::bigint = 800000);
END $$;

-- 9: shared personnel calculation
DO $$
DECLARE b record; sid uuid; econ jsonb;
BEGIN
  SELECT * INTO b FROM _m2_sim_bootstrap();
  PERFORM _m2_sim_grant_admin(b.org_id);
  PERFORM _m2_sim_as_auth(b.admin_auth_id);
  sid := public.create_class_financial_scenario('Shared', 10, 5000000, 4, 12, b.class_id, 0, NULL, 250000);
  econ := public.calculate_scenario_economics(sid);
  PERFORM _m2_sim_record(9, 'shared personnel calculation', (econ->>'projected_shared_personnel')::bigint = 1000000);
END $$;

-- 10: overhead calculation
DO $$
DECLARE b record; sid uuid; econ jsonb;
BEGIN
  SELECT * INTO b FROM _m2_sim_bootstrap();
  PERFORM _m2_sim_grant_admin(b.org_id);
  PERFORM _m2_sim_as_auth(b.admin_auth_id);
  sid := public.create_class_financial_scenario('Overhead', 10, 5000000, 3, 12, b.class_id, 0, NULL, 0, 80000);
  econ := public.calculate_scenario_economics(sid);
  PERFORM _m2_sim_record(10, 'overhead calculation', (econ->>'projected_operating_overhead')::bigint = 240000);
END $$;

-- 11: marketing calculation
DO $$
DECLARE b record; sid uuid; econ jsonb;
BEGIN
  SELECT * INTO b FROM _m2_sim_bootstrap();
  PERFORM _m2_sim_grant_admin(b.org_id);
  PERFORM _m2_sim_as_auth(b.admin_auth_id);
  sid := public.create_class_financial_scenario('Marketing', 10, 5000000, 6, 12, b.class_id, 0, NULL, 0, 0, 500000, 'one_time');
  econ := public.calculate_scenario_economics(sid);
  PERFORM _m2_sim_record(11, 'marketing calculation', (econ->>'projected_marketing_sales')::bigint = 500000);
END $$;

-- 12: depreciation calculation
DO $$
DECLARE b record; sid uuid; econ jsonb;
BEGIN
  SELECT * INTO b FROM _m2_sim_bootstrap();
  PERFORM _m2_sim_grant_admin(b.org_id);
  PERFORM _m2_sim_as_auth(b.admin_auth_id);
  sid := public.create_class_financial_scenario('Depreciation', 10, 5000000, 5, 12, b.class_id, 0, NULL, 0, 0, 0, 'one_time', 30000);
  econ := public.calculate_scenario_economics(sid);
  PERFORM _m2_sim_record(12, 'depreciation calculation', (econ->>'projected_depreciation')::bigint = 150000);
END $$;

-- 13: duration scaling correct
DO $$
DECLARE b record; sid uuid; econ jsonb;
BEGIN
  SELECT * INTO b FROM _m2_sim_bootstrap();
  PERFORM _m2_sim_grant_admin(b.org_id);
  PERFORM _m2_sim_as_auth(b.admin_auth_id);
  sid := public.create_class_financial_scenario('Duration', 10, 5000000, 6, 12, b.class_id, 0, NULL, 100000, 50000, 60000, 'monthly', 10000);
  econ := public.calculate_scenario_economics(sid);
  PERFORM _m2_sim_record(
    13, 'duration scaling correct',
    (econ->>'projected_shared_personnel')::bigint = 600000
      AND (econ->>'projected_operating_overhead')::bigint = 300000
      AND (econ->>'projected_marketing_sales')::bigint = 360000
      AND (econ->>'projected_depreciation')::bigint = 60000
  );
END $$;

-- 14: projected total cost correct
DO $$
DECLARE b record; sid uuid; econ jsonb; expected bigint;
BEGIN
  SELECT * INTO b FROM _m2_sim_bootstrap();
  PERFORM _m2_sim_grant_admin(b.org_id);
  PERFORM _m2_sim_as_auth(b.admin_auth_id);
  sid := public.create_class_financial_scenario('Total', 10, 5000000, 2, 10, b.class_id, 50000, NULL, 100000, 50000, 200000, 'one_time', 25000);
  econ := public.calculate_scenario_economics(sid);
  expected := 500000 + 200000 + 100000 + 200000 + 50000;
  PERFORM _m2_sim_record(14, 'projected total cost correct', (econ->>'projected_total_cost')::bigint = expected);
END $$;

-- 15: contribution correct
DO $$
DECLARE b record; sid uuid; econ jsonb;
BEGIN
  SELECT * INTO b FROM _m2_sim_bootstrap();
  PERFORM _m2_sim_grant_admin(b.org_id);
  PERFORM _m2_sim_as_auth(b.admin_auth_id);
  sid := public.create_class_financial_scenario('Contribution', 10, 1000000, 1, 5, b.class_id, 100000);
  econ := public.calculate_scenario_economics(sid);
  PERFORM _m2_sim_record(
    15, 'contribution correct',
    (econ->>'projected_contribution')::bigint = (econ->>'projected_revenue')::bigint - (econ->>'projected_total_cost')::bigint
  );
END $$;

-- 16: margin correct
DO $$
DECLARE b record; sid uuid; econ jsonb;
BEGIN
  SELECT * INTO b FROM _m2_sim_bootstrap();
  PERFORM _m2_sim_grant_admin(b.org_id);
  PERFORM _m2_sim_as_auth(b.admin_auth_id);
  sid := public.create_class_financial_scenario('Margin', 10, 1000000, 1, 0, b.class_id);
  econ := public.calculate_scenario_economics(sid);
  PERFORM _m2_sim_record(16, 'margin correct', (econ->>'projected_margin_percentage')::numeric = 100);
END $$;

-- 17: zero revenue margin safe
DO $$
DECLARE b record; sid uuid; econ jsonb;
BEGIN
  SELECT * INTO b FROM _m2_sim_bootstrap();
  PERFORM _m2_sim_grant_admin(b.org_id);
  PERFORM _m2_sim_as_auth(b.admin_auth_id);
  sid := public.create_class_financial_scenario('ZeroRev', 10, 0, 1, 0, b.class_id, 100000);
  econ := public.calculate_scenario_economics(sid);
  PERFORM _m2_sim_record(17, 'zero revenue margin safe', econ->>'projected_margin_percentage' IS NULL);
END $$;

-- 18: break-even learner count correct
DO $$
DECLARE b record; sid uuid; econ jsonb;
BEGIN
  SELECT * INTO b FROM _m2_sim_bootstrap();
  PERFORM _m2_sim_grant_admin(b.org_id);
  PERFORM _m2_sim_as_auth(b.admin_auth_id);
  sid := public.create_class_financial_scenario('BreakEven', 10, 500000, 1, 0, b.class_id, NULL, NULL, 0, 0, 2000000, 'one_time');
  econ := public.calculate_scenario_economics(sid);
  PERFORM _m2_sim_record(18, 'break-even learner count correct', (econ->>'break_even_learner_count')::integer = 4);
END $$;

-- 19: break-even is integer ceiling
DO $$
DECLARE be integer;
BEGIN
  be := public.compute_break_even_learner_count(1000001, 500000);
  PERFORM _m2_sim_record(19, 'break-even is integer ceiling', be = 3);
END $$;

-- 20: zero/invalid tuition handled safely
DO $$
DECLARE be integer;
BEGIN
  be := public.compute_break_even_learner_count(1000000, 0);
  PERFORM _m2_sim_record(20, 'zero/invalid tuition handled safely', be IS NULL);
END $$;

-- 21: capacity comparison
DO $$
DECLARE b record; sid uuid; econ jsonb;
BEGIN
  SELECT * INTO b FROM _m2_sim_bootstrap();
  PERFORM _m2_sim_as_super();
  UPDATE class SET capacity = 5 WHERE id = b.class_id;
  PERFORM _m2_sim_grant_admin(b.org_id);
  PERFORM _m2_sim_as_auth(b.admin_auth_id);
  sid := public.create_class_financial_scenario('Capacity', 10, 500000, 1, 0, b.class_id, NULL, NULL, 0, 0, 5000000, 'one_time');
  econ := public.calculate_scenario_economics(sid);
  PERFORM _m2_sim_record(
    21, 'capacity comparison',
    (econ->>'capacity')::integer = 5
      AND (econ->>'break_even_learner_count')::integer = 10
      AND (econ->>'break_even_within_capacity')::boolean = false
  );
END $$;

-- 22: finalized scenario immutable
SELECT _m2_sim_expect_fail(22, 'finalized scenario immutable', $$
  DO $i$ DECLARE b record; sid uuid; BEGIN
    SELECT * INTO b FROM _m2_sim_bootstrap();
    PERFORM _m2_sim_grant_admin(b.org_id);
    PERFORM _m2_sim_as_auth(b.admin_auth_id);
    sid := public.create_class_financial_scenario('Final', 10, 5000000, 3, 12, b.class_id);
    PERFORM public.finalize_class_financial_scenario(sid);
    PERFORM public.update_class_financial_scenario(sid, p_planned_learner_count := 99);
  END $i$;
$$);

-- 23: later compensation-rate change does not rewrite finalized scenario
DO $$
DECLARE b record; sid uuid; rule_id uuid; before jsonb; after jsonb;
BEGIN
  SELECT * INTO b FROM _m2_sim_bootstrap();
  PERFORM _m2_sim_grant_admin(b.org_id);
  PERFORM _m2_sim_as_auth(b.admin_auth_id);
  rule_id := public.create_staff_compensation_rule(b.staff_user_id, 'personnel', 'per_session', 100000, '2026-01-01');
  sid := public.create_class_financial_scenario('Snap', 10, 5000000, 3, 8, b.class_id, NULL, rule_id);
  before := public.finalize_class_financial_scenario(sid);
  PERFORM _m2_sim_as_super();
  UPDATE staff_compensation_rule SET amount = 500000 WHERE id = rule_id;
  PERFORM _m2_sim_as_auth(b.admin_auth_id);
  after := public.calculate_scenario_economics(sid);
  PERFORM _m2_sim_record(
    23, 'later compensation-rate change does not rewrite finalized scenario',
    (before->>'projected_direct_personnel')::bigint = (after->>'projected_direct_personnel')::bigint
  );
END $$;

-- 24: later actual cost change does not rewrite scenario snapshot
DO $$
DECLARE b record; sid uuid; before jsonb; after jsonb; eid uuid;
BEGIN
  SELECT * INTO b FROM _m2_sim_bootstrap();
  PERFORM _m2_sim_grant_admin(b.org_id);
  PERFORM _m2_sim_as_auth(b.admin_auth_id);
  sid := public.create_class_financial_scenario('Snapshot', 10, 5000000, 3, 12, b.class_id, NULL, NULL, 100000);
  before := public.finalize_class_financial_scenario(sid);
  INSERT INTO expense (organization_id, expense_category_id, cost_group_id, amount, incurred_date, status)
  SELECT b.org_id, ec.id, cg.id, 5000000, '2028-09-01', 'posted'
  FROM cost_group cg
  JOIN expense_category ec ON ec.cost_group_id = cg.id AND ec.organization_id = b.org_id
  WHERE cg.organization_id = b.org_id AND cg.cost_domain_code = 'operating_overhead'
  LIMIT 1
  RETURNING id INTO eid;
  PERFORM public.run_class_cost_allocation('2028-09-01');
  after := public.calculate_scenario_economics(sid);
  PERFORM _m2_sim_record(
    24, 'later actual cost change does not rewrite scenario snapshot',
    eid IS NOT NULL
      AND (before->>'projected_shared_personnel')::bigint = (after->>'projected_shared_personnel')::bigint
  );
END $$;

-- 25-29: accounting boundary (no finance facts)
DO $$
DECLARE b record; sid uuid;
  c0 integer; c1 integer; p0 integer; p1 integer; r0 integer; r1 integer;
  pc0 integer; pc1 integer; a0 integer; a1 integer;
BEGIN
  SELECT * INTO b FROM _m2_sim_bootstrap();
  PERFORM _m2_sim_grant_admin(b.org_id);
  PERFORM _m2_sim_as_auth(b.admin_auth_id);
  SELECT count(*) INTO c0 FROM charge;
  SELECT count(*) INTO p0 FROM payment;
  SELECT count(*) INTO r0 FROM revenue_recognition_event;
  SELECT count(*) INTO pc0 FROM personnel_cost_entry;
  SELECT count(*) INTO a0 FROM class_cost_allocation;
  sid := public.create_class_financial_scenario('Boundary', 10, 5000000, 6, 24, b.class_id, 200000);
  PERFORM public.finalize_class_financial_scenario(sid);
  PERFORM public.clone_class_financial_scenario(sid);
  SELECT count(*) INTO c1 FROM charge;
  SELECT count(*) INTO p1 FROM payment;
  SELECT count(*) INTO r1 FROM revenue_recognition_event;
  SELECT count(*) INTO pc1 FROM personnel_cost_entry;
  SELECT count(*) INTO a1 FROM class_cost_allocation;
  PERFORM _m2_sim_record(25, 'scenario creates no charge', c1 = c0);
  PERFORM _m2_sim_record(26, 'scenario creates no payment', p1 = p0);
  PERFORM _m2_sim_record(27, 'scenario creates no recognition event', r1 = r0);
  PERFORM _m2_sim_record(28, 'scenario creates no personnel cost entry', pc1 = pc0);
  PERFORM _m2_sim_record(29, 'scenario creates no class cost allocation', a1 = a0);
END $$;

-- 30: actual T08 economics unaffected
DO $$
DECLARE b record; sid uuid; econ_before jsonb; econ_after jsonb;
BEGIN
  SELECT * INTO b FROM _m2_sim_bootstrap();
  PERFORM _m2_sim_grant_admin(b.org_id);
  PERFORM _m2_sim_as_auth(b.admin_auth_id);
  econ_before := public.get_class_economics(b.class_id, '2026-01-01', '2026-12-31');
  sid := public.create_class_financial_scenario('NoEffect', 20, 8000000, 12, 48, b.class_id, 300000, NULL, 500000, 200000, 1000000);
  PERFORM public.finalize_class_financial_scenario(sid);
  econ_after := public.get_class_economics(b.class_id, '2026-01-01', '2026-12-31');
  PERFORM _m2_sim_record(
    30, 'actual T08 economics unaffected',
    (econ_before->>'recognized_revenue')::bigint = (econ_after->>'recognized_revenue')::bigint
      AND (econ_before->>'total_cost')::bigint = (econ_after->>'total_cost')::bigint
  );
END $$;

-- 31: projected-vs-actual comparison
DO $$
DECLARE b record; sid uuid; cmp jsonb;
BEGIN
  SELECT * INTO b FROM _m2_sim_bootstrap();
  PERFORM _m2_sim_grant_admin(b.org_id);
  PERFORM _m2_sim_as_auth(b.admin_auth_id);
  sid := public.create_class_financial_scenario('Compare', 10, 1000000, 1, 0, b.class_id);
  cmp := public.get_projected_vs_actual_class_economics(sid, '2026-01-01', '2026-12-31');
  PERFORM _m2_sim_record(
    31, 'projected-vs-actual comparison',
    cmp ? 'projected' AND cmp ? 'actual' AND cmp ? 'variance'
      AND (cmp->'projected'->>'projected_revenue')::bigint = 10000000
      AND (cmp->'variance'->>'revenue')::bigint = 0 - 10000000
  );
END $$;

-- 32: cross-org class linkage rejected
SELECT _m2_sim_expect_fail(32, 'cross-org class linkage rejected', $$
  DO $i$ DECLARE a record; b record; BEGIN
    SELECT * INTO a FROM _m2_sim_bootstrap();
    SELECT * INTO b FROM _m2_sim_bootstrap();
    PERFORM _m2_sim_grant_admin(a.org_id);
    PERFORM _m2_sim_as_auth(a.admin_auth_id);
    PERFORM public.create_class_financial_scenario('Cross', 10, 5000000, 3, 12, b.class_id);
  END $i$;
$$);

-- 33: RLS tenant isolation
DO $$
DECLARE b record; cnt integer;
BEGIN
  SELECT * INTO b FROM _m2_sim_bootstrap();
  PERFORM _m2_sim_grant_admin(b.org_id);
  PERFORM _m2_sim_as_auth(b.admin_auth_id);
  PERFORM public.create_class_financial_scenario('RLS', 10, 5000000, 3, 12, b.class_id);
  PERFORM _m2_sim_as_auth('b2222222-2222-4222-8222-222222222222');
  SELECT count(*) INTO cnt FROM class_financial_scenario WHERE organization_id = b.org_id;
  PERFORM _m2_sim_record(33, 'RLS tenant isolation', cnt = 0);
END $$;

-- 34: permission enforcement
DO $$
DECLARE b record; ok boolean := false;
BEGIN
  SELECT * INTO b FROM _m2_sim_bootstrap();
  PERFORM _m2_sim_as_auth(b.admin_auth_id);
  BEGIN
    PERFORM public.create_class_financial_scenario('Denied', 10, 5000000, 3, 12, b.class_id);
  EXCEPTION WHEN OTHERS THEN ok := true; END;
  PERFORM _m2_sim_record(34, 'permission enforcement', ok);
END $$;

-- 35: compare scenarios read model
DO $$
DECLARE b record; s1 uuid; s2 uuid; cmp jsonb;
BEGIN
  SELECT * INTO b FROM _m2_sim_bootstrap();
  PERFORM _m2_sim_grant_admin(b.org_id);
  PERFORM _m2_sim_as_auth(b.admin_auth_id);
  s1 := public.create_class_financial_scenario('A', 8, 4000000, 3, 12, b.class_id);
  s2 := public.create_class_financial_scenario('B', 12, 4500000, 3, 12, b.class_id);
  cmp := public.compare_class_financial_scenarios(b.class_id);
  PERFORM _m2_sim_record(
    35, 'compare scenarios read model',
    jsonb_array_length(cmp->'scenarios') = 2
      AND (cmp->'scenarios'->0->>'planned_learner_count')::integer IN (8, 12)
  );
END $$;

DO $$
DECLARE total integer; passed integer; failed integer;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE result = 'PASS'), count(*) FILTER (WHERE result = 'FAIL')
    INTO total, passed, failed FROM _m2_sim_results;
  RAISE NOTICE 'M2 class financial simulator Tests: % / % passed (% failed)', passed, total, failed;
  IF failed > 0 OR total <> 35 THEN
    RAISE EXCEPTION 'M2 class financial simulator tests failed: % of % (expected 35)', failed, total;
  END IF;
END $$;

SELECT test_no, test_name, result FROM _m2_sim_results ORDER BY test_no;

ROLLBACK;
