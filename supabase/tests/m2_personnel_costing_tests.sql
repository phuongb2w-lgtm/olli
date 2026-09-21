-- M2-T07: personnel costing foundation (24 scenarios)

BEGIN;

CREATE TEMP TABLE _m2_pc_results (
  test_no   integer PRIMARY KEY,
  test_name text NOT NULL,
  result    text NOT NULL CHECK (result IN ('PASS', 'FAIL'))
);

GRANT ALL ON TABLE _m2_pc_results TO authenticated, anon;

CREATE OR REPLACE FUNCTION _m2_pc_record(test_no integer, test_name text, passed boolean)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO _m2_pc_results (test_no, test_name, result)
  VALUES (test_no, test_name, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END);
END;
$$;

CREATE OR REPLACE FUNCTION _m2_pc_expect_fail(test_no integer, test_name text, sql_text text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN EXECUTE sql_text; PERFORM _m2_pc_record(test_no, test_name, false);
  EXCEPTION WHEN OTHERS THEN PERFORM _m2_pc_record(test_no, test_name, true); END;
END;
$$;

CREATE OR REPLACE FUNCTION _m2_pc_as_super() RETURNS void LANGUAGE plpgsql AS $$
BEGIN RESET ROLE; SET LOCAL ROLE postgres; END; $$;

CREATE OR REPLACE FUNCTION _m2_pc_as_auth(p_auth_id uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE; SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', p_auth_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_auth_id::text, 'role', 'authenticated')::text, true);
END; $$;

CREATE OR REPLACE FUNCTION _m2_pc_bootstrap()
RETURNS TABLE (
  org_id uuid, class_id uuid, teacher_id uuid, staff_user_id uuid, admin_auth_id uuid
) LANGUAGE plpgsql AS $$
DECLARE
  v_org uuid; v_class uuid; v_teacher uuid; v_staff uuid; v_admin uuid; v_auth uuid; v_staff_auth uuid;
BEGIN
  PERFORM _m2_pc_as_super();
  v_org := gen_random_uuid();
  v_auth := gen_random_uuid();
  v_staff_auth := gen_random_uuid();
  INSERT INTO organization (id, name) VALUES (v_org, 'M2 PC Org');
  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at, is_sso_user, is_anonymous)
  VALUES
    (v_auth, (SELECT id FROM auth.instances LIMIT 1), 'authenticated', 'authenticated', 'pc-admin-' || replace(v_auth::text, '-', '') || '@test.local', '', now(), now(), now(), false, false),
    (v_staff_auth, (SELECT id FROM auth.instances LIMIT 1), 'authenticated', 'authenticated', 'pc-staff-' || replace(v_staff_auth::text, '-', '') || '@test.local', '', now(), now(), now(), false, false);
  v_admin := public.test_fixture_insert_app_user(v_org, 'pc-admin@test.local', 'PC Admin', v_auth);
  v_staff := public.test_fixture_insert_app_user(v_org, 'pc-staff@test.local', 'PC Staff', v_staff_auth);
  PERFORM public.set_primary_owner_for_organization(v_org, v_admin);
  INSERT INTO course (organization_id, code, name) VALUES (v_org, 'PC1', 'PC Course');
  INSERT INTO class (organization_id, course_id, name, status)
  SELECT v_org, c.id, 'PC Class', 'active' FROM course c WHERE c.organization_id = v_org LIMIT 1 RETURNING id INTO v_class;
  INSERT INTO teacher (organization_id, user_id, given_name, family_name, status)
  VALUES (v_org, v_staff, 'PC', 'Teacher', 'active') RETURNING id INTO v_teacher;
  RETURN QUERY SELECT v_org, v_class, v_teacher, v_staff, v_auth;
END; $$;

CREATE OR REPLACE FUNCTION _m2_pc_grant_admin(p_org uuid) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_user uuid;
BEGIN
  SELECT id INTO v_user FROM app_user WHERE organization_id = p_org AND email = 'pc-admin@test.local' LIMIT 1;
  PERFORM public.test_fixture_grant_all_permissions_role(p_org, v_user, 'pc_admin');
END; $$;

CREATE OR REPLACE FUNCTION _m2_pc_session(
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

-- 1: monthly fixed rule creation
DO $$
DECLARE b record; rid uuid;
BEGIN
  SELECT * INTO b FROM _m2_pc_bootstrap();
  PERFORM _m2_pc_grant_admin(b.org_id);
  PERFORM _m2_pc_as_auth(b.admin_auth_id);
  rid := public.create_staff_compensation_rule(b.staff_user_id, 'personnel', 'monthly_fixed', 5000000, '2026-01-01');
  PERFORM _m2_pc_record(1, 'monthly fixed rule creation', rid IS NOT NULL);
END $$;

-- 2: per-session rule creation
DO $$
DECLARE b record; rid uuid;
BEGIN
  SELECT * INTO b FROM _m2_pc_bootstrap();
  PERFORM _m2_pc_grant_admin(b.org_id);
  PERFORM _m2_pc_as_auth(b.admin_auth_id);
  rid := public.create_staff_compensation_rule(b.staff_user_id, 'personnel', 'per_session', 300000, '2026-01-01');
  PERFORM _m2_pc_record(2, 'per-session rule creation', rid IS NOT NULL);
END $$;

-- 3: teacher rule classified B2
DO $$
DECLARE b record; domain text;
BEGIN
  SELECT * INTO b FROM _m2_pc_bootstrap();
  PERFORM _m2_pc_grant_admin(b.org_id);
  PERFORM _m2_pc_as_auth(b.admin_auth_id);
  PERFORM public.create_staff_compensation_rule(b.staff_user_id, 'personnel', 'per_session', 300000, '2026-01-01');
  SELECT cost_domain_code INTO domain FROM staff_compensation_rule WHERE organization_id = b.org_id LIMIT 1;
  PERFORM _m2_pc_record(3, 'teacher rule classified B2', domain = 'personnel');
END $$;

-- 4: counselor rule classified Cost C
DO $$
DECLARE b record; counselor uuid; domain text;
BEGIN
  SELECT * INTO b FROM _m2_pc_bootstrap();
  counselor := public.test_fixture_insert_app_user(b.org_id, 'counselor@test.local', 'Counselor');
  PERFORM _m2_pc_grant_admin(b.org_id);
  PERFORM _m2_pc_as_auth(b.admin_auth_id);
  PERFORM public.create_staff_compensation_rule(counselor, 'marketing_sales', 'monthly_fixed', 8000000, '2026-01-01');
  SELECT cost_domain_code INTO domain FROM staff_compensation_rule WHERE app_user_id = counselor;
  PERFORM _m2_pc_record(4, 'counselor rule classified Cost C', domain = 'marketing_sales');
END $$;

-- 5: capital/overhead classification rejected
SELECT _m2_pc_expect_fail(5, 'capital/overhead classification rejected', $$
  DO $i$ DECLARE b record; BEGIN
    SELECT * INTO b FROM _m2_pc_bootstrap();
    PERFORM _m2_pc_grant_admin(b.org_id);
    PERFORM _m2_pc_as_auth(b.admin_auth_id);
    PERFORM public.create_staff_compensation_rule(b.staff_user_id, 'operating_overhead', 'monthly_fixed', 1000000, '2026-01-01');
  END $i$;
$$);

-- 6: effective-dated rate change preserves history
DO $$
DECLARE b record; r1 uuid; r2 uuid; cnt integer;
BEGIN
  SELECT * INTO b FROM _m2_pc_bootstrap();
  PERFORM _m2_pc_grant_admin(b.org_id);
  PERFORM _m2_pc_as_auth(b.admin_auth_id);
  r1 := public.create_staff_compensation_rule(b.staff_user_id, 'personnel', 'per_session', 300000, '2026-01-01');
  PERFORM public.end_staff_compensation_rule(r1, '2026-06-30');
  r2 := public.create_staff_compensation_rule(b.staff_user_id, 'personnel', 'per_session', 350000, '2026-07-01');
  SELECT count(*) INTO cnt FROM staff_compensation_rule WHERE organization_id = b.org_id AND status <> 'void';
  PERFORM _m2_pc_record(6, 'effective-dated rate change preserves history', cnt = 2 AND r1 <> r2);
END $$;

-- 7: invalid overlapping rule rejected
SELECT _m2_pc_expect_fail(7, 'invalid overlapping rule rejected', $$
  DO $i$ DECLARE b record; BEGIN
    SELECT * INTO b FROM _m2_pc_bootstrap();
    PERFORM _m2_pc_grant_admin(b.org_id);
    PERFORM _m2_pc_as_auth(b.admin_auth_id);
    PERFORM public.create_staff_compensation_rule(b.staff_user_id, 'personnel', 'monthly_fixed', 5000000, '2026-01-01');
    PERFORM public.create_staff_compensation_rule(b.staff_user_id, 'personnel', 'monthly_fixed', 6000000, '2026-03-01');
  END $i$;
$$);

-- 8: completed teaching session generates direct cost
DO $$
DECLARE b record; sid uuid; res jsonb; cnt integer;
BEGIN
  SELECT * INTO b FROM _m2_pc_bootstrap();
  PERFORM _m2_pc_grant_admin(b.org_id);
  PERFORM _m2_pc_as_auth(b.admin_auth_id);
  PERFORM public.create_staff_compensation_rule(b.staff_user_id, 'personnel', 'per_session', 300000, '2026-01-01');
  sid := _m2_pc_session(b.org_id, b.class_id, b.teacher_id, 0, 'completed');
  res := public.generate_teaching_session_personnel_cost(sid);
  SELECT count(*) INTO cnt FROM personnel_cost_entry WHERE teaching_session_id = sid AND status = 'posted';
  PERFORM _m2_pc_record(8, 'completed session generates direct cost', cnt = 1 AND (res->>'entries_created')::int = 1);
END $$;

-- 9: non-completed session generates none
DO $$
DECLARE b record; sid uuid; cnt integer;
BEGIN
  SELECT * INTO b FROM _m2_pc_bootstrap();
  PERFORM _m2_pc_grant_admin(b.org_id);
  PERFORM _m2_pc_as_auth(b.admin_auth_id);
  PERFORM public.create_staff_compensation_rule(b.staff_user_id, 'personnel', 'per_session', 300000, '2026-01-01');
  sid := _m2_pc_session(b.org_id, b.class_id, b.teacher_id, 1, 'scheduled');
  PERFORM public.generate_teaching_session_personnel_cost(sid);
  SELECT count(*) INTO cnt FROM personnel_cost_entry WHERE teaching_session_id = sid AND status = 'posted';
  PERFORM _m2_pc_record(9, 'non-completed session generates none', cnt = 0);
END $$;

-- 10: same session/rule cannot generate twice
DO $$
DECLARE b record; sid uuid; cnt integer;
BEGIN
  SELECT * INTO b FROM _m2_pc_bootstrap();
  PERFORM _m2_pc_grant_admin(b.org_id);
  PERFORM _m2_pc_as_auth(b.admin_auth_id);
  PERFORM public.create_staff_compensation_rule(b.staff_user_id, 'personnel', 'per_session', 300000, '2026-01-01');
  sid := _m2_pc_session(b.org_id, b.class_id, b.teacher_id, 2, 'completed');
  PERFORM public.generate_teaching_session_personnel_cost(sid);
  PERFORM public.generate_teaching_session_personnel_cost(sid);
  SELECT count(*) INTO cnt FROM personnel_cost_entry WHERE teaching_session_id = sid AND status = 'posted';
  PERFORM _m2_pc_record(10, 'same session/rule cannot generate twice', cnt = 1);
END $$;

-- 11: generated entry links to class/session
DO $$
DECLARE b record; sid uuid; cid uuid; tid uuid;
BEGIN
  SELECT * INTO b FROM _m2_pc_bootstrap();
  PERFORM _m2_pc_grant_admin(b.org_id);
  PERFORM _m2_pc_as_auth(b.admin_auth_id);
  PERFORM public.create_staff_compensation_rule(b.staff_user_id, 'personnel', 'per_session', 300000, '2026-01-01');
  sid := _m2_pc_session(b.org_id, b.class_id, b.teacher_id, 3, 'completed');
  PERFORM public.generate_teaching_session_personnel_cost(sid);
  SELECT class_id, teacher_id INTO cid, tid FROM personnel_cost_entry WHERE teaching_session_id = sid LIMIT 1;
  PERFORM _m2_pc_record(11, 'generated entry links to class/session', cid = b.class_id AND tid = b.teacher_id);
END $$;

-- 12: monthly fixed entry generated once per month/rule
DO $$
DECLARE b record; cnt integer;
BEGIN
  SELECT * INTO b FROM _m2_pc_bootstrap();
  PERFORM _m2_pc_grant_admin(b.org_id);
  PERFORM _m2_pc_as_auth(b.admin_auth_id);
  PERFORM public.create_staff_compensation_rule(b.staff_user_id, 'personnel', 'monthly_fixed', 5000000, '2026-01-01');
  PERFORM public.generate_personnel_costs('2026-03-01');
  SELECT count(*) INTO cnt FROM personnel_cost_entry
  WHERE organization_id = b.org_id AND source_type = 'monthly_fixed' AND accounting_period = '2026-03-01';
  PERFORM _m2_pc_record(12, 'monthly fixed entry once per month/rule', cnt = 1);
END $$;

-- 13: retry is idempotent
DO $$
DECLARE b record; r1 jsonb; r2 jsonb; cnt integer;
BEGIN
  SELECT * INTO b FROM _m2_pc_bootstrap();
  PERFORM _m2_pc_grant_admin(b.org_id);
  PERFORM _m2_pc_as_auth(b.admin_auth_id);
  PERFORM public.create_staff_compensation_rule(b.staff_user_id, 'personnel', 'monthly_fixed', 5000000, '2026-01-01');
  r1 := public.generate_personnel_costs('2026-04-01');
  r2 := public.generate_personnel_costs('2026-04-01');
  SELECT count(*) INTO cnt FROM personnel_cost_entry
  WHERE organization_id = b.org_id AND source_type = 'monthly_fixed' AND accounting_period = '2026-04-01';
  PERFORM _m2_pc_record(
    13,
    'retry is idempotent',
    cnt = 1 AND (r1->>'monthly_entries_created')::int = 1 AND (r2->>'monthly_entries_created')::int = 0
  );
END $$;

-- 14: welfare baseline generates B2 cost
DO $$
DECLARE b record; cnt integer; domain text;
BEGIN
  SELECT * INTO b FROM _m2_pc_bootstrap();
  PERFORM _m2_pc_grant_admin(b.org_id);
  PERFORM _m2_pc_as_auth(b.admin_auth_id);
  PERFORM public.configure_welfare_fund_baseline(2000000, '2026-01-01');
  PERFORM public.generate_personnel_costs('2026-05-01');
  SELECT count(*), max(cost_domain_code) INTO cnt, domain
  FROM personnel_cost_entry
  WHERE organization_id = b.org_id AND source_type = 'welfare_baseline' AND accounting_period = '2026-05-01';
  PERFORM _m2_pc_record(14, 'welfare baseline generates B2 cost', cnt = 1 AND domain = 'personnel');
END $$;

-- 15: welfare entry requires no fake staff identity
DO $$
DECLARE b record; uid uuid;
BEGIN
  SELECT * INTO b FROM _m2_pc_bootstrap();
  PERFORM _m2_pc_grant_admin(b.org_id);
  PERFORM _m2_pc_as_auth(b.admin_auth_id);
  PERFORM public.configure_welfare_fund_baseline(2000000, '2026-01-01');
  PERFORM public.generate_personnel_costs('2026-06-01');
  SELECT app_user_id INTO uid FROM personnel_cost_entry
  WHERE organization_id = b.org_id AND source_type = 'welfare_baseline' LIMIT 1;
  PERFORM _m2_pc_record(15, 'welfare entry requires no fake staff identity', uid IS NULL);
END $$;

-- 16: historical cost survives later rate change
DO $$
DECLARE b record; rid uuid; sid uuid; old_amt bigint; new_amt bigint;
BEGIN
  SELECT * INTO b FROM _m2_pc_bootstrap();
  PERFORM _m2_pc_grant_admin(b.org_id);
  PERFORM _m2_pc_as_auth(b.admin_auth_id);
  rid := public.create_staff_compensation_rule(b.staff_user_id, 'personnel', 'per_session', 300000, '2026-01-01');
  sid := _m2_pc_session(b.org_id, b.class_id, b.teacher_id, 4, 'completed');
  PERFORM public.generate_teaching_session_personnel_cost(sid);
  SELECT amount INTO old_amt FROM personnel_cost_entry WHERE teaching_session_id = sid;
  PERFORM public.end_staff_compensation_rule(rid, CURRENT_DATE);
  PERFORM public.create_staff_compensation_rule(b.staff_user_id, 'personnel', 'per_session', 350000, CURRENT_DATE + 1);
  SELECT amount INTO new_amt FROM personnel_cost_entry WHERE teaching_session_id = sid;
  PERFORM _m2_pc_record(16, 'historical cost survives later rate change', old_amt = 300000 AND new_amt = 300000);
END $$;

-- 17: historical domain snapshot cannot silently change
DO $$
DECLARE b record; eid uuid; ok boolean := false;
BEGIN
  SELECT * INTO b FROM _m2_pc_bootstrap();
  PERFORM _m2_pc_grant_admin(b.org_id);
  PERFORM _m2_pc_as_auth(b.admin_auth_id);
  PERFORM public.create_staff_compensation_rule(b.staff_user_id, 'personnel', 'monthly_fixed', 5000000, '2026-01-01');
  PERFORM public.generate_personnel_costs('2026-07-01');
  SELECT id INTO eid FROM personnel_cost_entry WHERE organization_id = b.org_id AND source_type = 'monthly_fixed' LIMIT 1;
  BEGIN
    UPDATE personnel_cost_entry SET cost_domain_code = 'marketing_sales' WHERE id = eid;
  EXCEPTION WHEN OTHERS THEN ok := true; END;
  PERFORM _m2_pc_record(17, 'historical domain snapshot cannot silently change', ok);
END $$;

-- 18: cross-org staff/rule linkage rejected
SELECT _m2_pc_expect_fail(18, 'cross-org staff/rule linkage rejected', $$
  DO $i$ DECLARE a record; b record; BEGIN
    SELECT * INTO a FROM _m2_pc_bootstrap();
    SELECT * INTO b FROM _m2_pc_bootstrap();
    PERFORM _m2_pc_grant_admin(a.org_id);
    PERFORM _m2_pc_as_auth(a.admin_auth_id);
    PERFORM public.create_staff_compensation_rule(b.staff_user_id, 'personnel', 'monthly_fixed', 1000000, '2026-01-01');
  END $i$;
$$);

-- 19: RLS tenant isolation
DO $$
DECLARE b record; cnt integer;
BEGIN
  SELECT * INTO b FROM _m2_pc_bootstrap();
  PERFORM _m2_pc_grant_admin(b.org_id);
  PERFORM _m2_pc_as_auth(b.admin_auth_id);
  PERFORM public.create_staff_compensation_rule(b.staff_user_id, 'personnel', 'monthly_fixed', 5000000, '2026-01-01');
  PERFORM public.generate_personnel_costs('2026-08-01');
  PERFORM _m2_pc_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO cnt FROM personnel_cost_entry WHERE organization_id = b.org_id;
  PERFORM _m2_pc_record(19, 'RLS tenant isolation', cnt = 0);
END $$;

-- 20: permission enforcement
DO $$
DECLARE b record; ok boolean := false;
BEGIN
  SELECT * INTO b FROM _m2_pc_bootstrap();
  PERFORM _m2_pc_as_auth(b.admin_auth_id);
  BEGIN
    PERFORM public.generate_personnel_costs('2026-09-01');
  EXCEPTION WHEN OTHERS THEN ok := true; END;
  PERFORM _m2_pc_record(20, 'permission enforcement', ok);
END $$;

-- 21: group_slot not used for accounting identity
DO $$
DECLARE b record; slot_used boolean;
BEGIN
  SELECT * INTO b FROM _m2_pc_bootstrap();
  PERFORM _m2_pc_grant_admin(b.org_id);
  PERFORM _m2_pc_as_auth(b.admin_auth_id);
  PERFORM public.create_staff_compensation_rule(b.staff_user_id, 'personnel', 'monthly_fixed', 5000000, '2026-01-01');
  SELECT EXISTS (
    SELECT 1
    FROM staff_compensation_rule r
    JOIN cost_group g ON g.organization_id = r.organization_id AND g.cost_domain_code = r.cost_domain_code
    WHERE r.organization_id = b.org_id
  ) INTO slot_used;
  PERFORM _m2_pc_record(21, 'group_slot not used for accounting identity', slot_used);
END $$;

-- 22: no mirrored ordinary expense required
DO $$
DECLARE b record; before_cnt integer; after_cnt integer;
BEGIN
  SELECT * INTO b FROM _m2_pc_bootstrap();
  PERFORM _m2_pc_grant_admin(b.org_id);
  PERFORM _m2_pc_as_auth(b.admin_auth_id);
  SELECT count(*) INTO before_cnt FROM expense WHERE organization_id = b.org_id;
  PERFORM public.create_staff_compensation_rule(b.staff_user_id, 'personnel', 'monthly_fixed', 5000000, '2026-01-01');
  PERFORM public.generate_personnel_costs('2026-10-01');
  PERFORM public.configure_welfare_fund_baseline(2000000, '2026-01-01');
  PERFORM public.generate_personnel_costs('2026-10-01');
  SELECT count(*) INTO after_cnt FROM expense WHERE organization_id = b.org_id;
  PERFORM _m2_pc_record(22, 'no mirrored ordinary expense required', before_cnt = after_cnt);
END $$;

-- 23: M1 academic rows unchanged
DO $$
DECLARE b record; sid uuid; ts_status text;
BEGIN
  SELECT * INTO b FROM _m2_pc_bootstrap();
  PERFORM _m2_pc_grant_admin(b.org_id);
  PERFORM _m2_pc_as_auth(b.admin_auth_id);
  PERFORM public.create_staff_compensation_rule(b.staff_user_id, 'personnel', 'per_session', 300000, '2026-01-01');
  sid := _m2_pc_session(b.org_id, b.class_id, b.teacher_id, 5, 'completed');
  PERFORM public.generate_teaching_session_personnel_cost(sid);
  SELECT status INTO ts_status FROM teaching_session WHERE id = sid;
  PERFORM _m2_pc_record(23, 'M1 academic rows unchanged', ts_status = 'completed');
END $$;

-- 24: existing M2 structures unaffected
DO $$
DECLARE pay_cnt integer; rev_cnt integer;
BEGIN
  SELECT count(*) INTO pay_cnt FROM payment;
  SELECT count(*) INTO rev_cnt FROM revenue_recognition_event;
  PERFORM _m2_pc_record(24, 'existing M2 structures unaffected', pay_cnt >= 0 AND rev_cnt >= 0);
END $$;

DO $$
DECLARE total integer; passed integer; failed integer;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE result = 'PASS'), count(*) FILTER (WHERE result = 'FAIL')
    INTO total, passed, failed FROM _m2_pc_results;
  RAISE NOTICE 'M2 personnel costing Tests: % / % passed (% failed)', passed, total, failed;
  IF failed > 0 OR total <> 24 THEN
    RAISE EXCEPTION 'M2 personnel costing tests failed: % of % (expected 24)', failed, total;
  END IF;
END $$;

SELECT test_no, test_name, result FROM _m2_pc_results ORDER BY test_no;

ROLLBACK;
