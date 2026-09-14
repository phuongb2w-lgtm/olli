-- M0-T04 security / RLS verification: 30 scenarios
-- Requires local Supabase stack + dev seed fixtures.
-- Tests run as SET ROLE authenticated/anon (not superuser bypass).

CREATE TEMP TABLE IF NOT EXISTS _sec_results (
  test_no integer PRIMARY KEY,
  test_name text NOT NULL,
  result text NOT NULL CHECK (result IN ('PASS', 'FAIL'))
);

GRANT ALL ON TABLE _sec_results TO authenticated, anon;

CREATE OR REPLACE FUNCTION _sec_record(test_no integer, test_name text, passed boolean)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO _sec_results (test_no, test_name, result)
  VALUES (test_no, test_name, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END);
END;
$$;

CREATE OR REPLACE FUNCTION _sec_as_auth(p_auth_id uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', p_auth_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_auth_id::text, 'role', 'authenticated')::text, true);
END;
$$;

CREATE OR REPLACE FUNCTION _sec_as_anon()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE anon;
  PERFORM set_config('request.jwt.claim.sub', '', true);
END;
$$;

CREATE OR REPLACE FUNCTION _sec_as_super()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
END;
$$;

-- Fixture UUIDs (must match supabase/seed.sql)
-- Org A: a0000000-0000-4000-8000-000000000001
-- Org B: b0000000-0000-4000-8000-000000000001

-- 1 auth resolves to app_user
DO $$
DECLARE v_org uuid;
BEGIN
  PERFORM _sec_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT organization_id INTO v_org FROM app_user WHERE auth_user_id = auth.uid();
  PERFORM _sec_record(1, 'auth user resolves to app_user', v_org = 'a0000000-0000-4000-8000-000000000001');
END $$;

-- 2 unmapped auth has no org access
DO $$
DECLARE v_count integer;
BEGIN
  PERFORM _sec_as_auth('c1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_count FROM student;
  PERFORM _sec_record(2, 'unmapped auth no org access', v_count = 0);
END $$;

-- 3 removed auth mapping preserves app_user, blocks access
DO $$
DECLARE v_exists boolean; v_count integer;
BEGIN
  PERFORM _sec_as_super();
  PERFORM set_config('olli.bypass_app_user_guard', 'true', true);
  UPDATE app_user SET auth_user_id = NULL WHERE email = 'org-a-admin@olli.local';
  PERFORM set_config('olli.bypass_app_user_guard', 'false', true);
  SELECT EXISTS(SELECT 1 FROM app_user WHERE email = 'org-a-admin@olli.local') INTO v_exists;
  PERFORM _sec_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_count FROM student WHERE organization_id = 'a0000000-0000-4000-8000-000000000001';
  PERFORM _sec_record(3, 'removed auth mapping blocks access keeps app_user', v_exists AND v_count = 0);
  -- restore mapping for later tests
  PERFORM _sec_as_super();
  PERFORM set_config('olli.bypass_app_user_guard', 'true', true);
  UPDATE app_user SET auth_user_id = 'a1111111-1111-4111-8111-111111111111' WHERE email = 'org-a-admin@olli.local';
  PERFORM set_config('olli.bypass_app_user_guard', 'false', true);
END $$;

-- 4-6 anonymous denied
DO $$
BEGIN
  PERFORM _sec_as_anon();
  BEGIN
    PERFORM 1 FROM student LIMIT 1;
    PERFORM _sec_record(4, 'anon cannot read student', false);
  EXCEPTION WHEN insufficient_privilege THEN
    PERFORM _sec_record(4, 'anon cannot read student', true);
  END;
  BEGIN
    PERFORM 1 FROM charge LIMIT 1;
    PERFORM _sec_record(5, 'anon cannot read finance', false);
  EXCEPTION WHEN insufficient_privilege THEN
    PERFORM _sec_record(5, 'anon cannot read finance', true);
  END;
  BEGIN
    INSERT INTO student (organization_id, given_name, family_name)
    VALUES ('a0000000-0000-4000-8000-000000000001', 'X', 'Y');
    PERFORM _sec_record(6, 'anon cannot mutate', false);
  EXCEPTION WHEN insufficient_privilege THEN
    PERFORM _sec_record(6, 'anon cannot mutate', true);
  END;
END $$;

-- 7 org A admin reads org A student
DO $$
DECLARE v_count integer;
BEGIN
  PERFORM _sec_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_count FROM student WHERE organization_id = 'a0000000-0000-4000-8000-000000000001';
  PERFORM _sec_record(7, 'org A admin reads org A data', v_count >= 1);
END $$;

-- 8-11 org A cannot read org B
DO $$
DECLARE c integer;
BEGIN
  PERFORM _sec_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO c FROM student WHERE organization_id = 'b0000000-0000-4000-8000-000000000001';
  PERFORM _sec_record(8, 'org A cannot read org B student', c = 0);
  SELECT count(*) INTO c FROM class WHERE organization_id = 'b0000000-0000-4000-8000-000000000001';
  PERFORM _sec_record(9, 'org A cannot read org B class', c = 0);
  SELECT count(*) INTO c FROM charge WHERE organization_id = 'b0000000-0000-4000-8000-000000000001';
  PERFORM _sec_record(10, 'org A cannot read org B charge', c = 0);
  SELECT count(*) INTO c FROM expense WHERE organization_id = 'b0000000-0000-4000-8000-000000000001';
  PERFORM _sec_record(11, 'org A cannot read org B expense', c = 0);
END $$;

-- 12 insert claiming org B denied
DO $$
BEGIN
  PERFORM _sec_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    INSERT INTO student (organization_id, given_name, family_name)
    VALUES ('b0000000-0000-4000-8000-000000000001', 'Bad', 'Insert');
    PERFORM _sec_record(12, 'org A cannot insert org B row', false);
  EXCEPTION WHEN OTHERS THEN
    PERFORM _sec_record(12, 'org A cannot insert org B row', true);
  END;
END $$;

-- 13 update row to org B denied
DO $$
DECLARE v_id uuid;
BEGIN
  PERFORM _sec_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT id INTO v_id FROM student WHERE organization_id = 'a0000000-0000-4000-8000-000000000001' LIMIT 1;
  BEGIN
    UPDATE student SET organization_id = 'b0000000-0000-4000-8000-000000000001' WHERE id = v_id;
    PERFORM _sec_record(13, 'org A cannot move row to org B', false);
  EXCEPTION WHEN OTHERS THEN
    PERFORM _sec_record(13, 'org A cannot move row to org B', true);
  END;
END $$;

-- 14 staff with student.read can read
DO $$
DECLARE c integer;
BEGIN
  PERFORM _sec_as_auth('a2222222-2222-4222-8222-222222222222');
  SELECT count(*) INTO c FROM student;
  PERFORM _sec_record(14, 'student reader reads students', c >= 1);
END $$;

-- 15 staff without student.create cannot create
DO $$
BEGIN
  PERFORM _sec_as_auth('a2222222-2222-4222-8222-222222222222');
  BEGIN
    INSERT INTO student (organization_id, given_name, family_name)
    VALUES ('a0000000-0000-4000-8000-000000000001', 'No', 'Create');
    PERFORM _sec_record(15, 'no student.create denied', false);
  EXCEPTION WHEN OTHERS THEN
    PERFORM _sec_record(15, 'no student.create denied', true);
  END;
END $$;

-- 16 finance reader reads charges
DO $$
DECLARE c integer;
BEGIN
  PERFORM _sec_as_auth('a2222222-2222-4222-8222-222222222222');
  SELECT count(*) INTO c FROM charge;
  PERFORM _sec_record(16, 'finance reader reads charges', c >= 1);
END $$;

-- 17 no charge.create cannot create charge
DO $$
DECLARE g uuid;
BEGIN
  PERFORM _sec_as_auth('a2222222-2222-4222-8222-222222222222');
  SELECT id INTO g FROM guardian WHERE organization_id = 'a0000000-0000-4000-8000-000000000001' LIMIT 1;
  BEGIN
    INSERT INTO charge (organization_id, student_id, guardian_id, amount)
    SELECT organization_id, id, g, 1000 FROM student WHERE organization_id = 'a0000000-0000-4000-8000-000000000001' LIMIT 1;
    PERFORM _sec_record(17, 'no charge.create denied', false);
  EXCEPTION WHEN OTHERS THEN
    PERFORM _sec_record(17, 'no charge.create denied', true);
  END;
END $$;

-- 18 admin can create observation
DO $$
DECLARE v_enr uuid; v_class uuid; v_teacher uuid;
BEGIN
  PERFORM _sec_as_super();
  INSERT INTO teacher (organization_id, given_name, family_name) VALUES ('a0000000-0000-4000-8000-000000000001', 'T', 'Obs') RETURNING id INTO v_teacher;
  SELECT e.id, e.class_id INTO v_enr, v_class FROM enrollment e
  JOIN student s ON s.id = e.student_id
  WHERE s.organization_id = 'a0000000-0000-4000-8000-000000000001' LIMIT 1;
  IF v_enr IS NULL THEN
    INSERT INTO enrollment (organization_id, student_id, class_id, start_date, status)
    SELECT 'a0000000-0000-4000-8000-000000000001', s.id, c.id, CURRENT_DATE, 'active'
    FROM student s, class c
    WHERE s.organization_id = 'a0000000-0000-4000-8000-000000000001'
      AND c.organization_id = 'a0000000-0000-4000-8000-000000000001'
    LIMIT 1
    RETURNING id, class_id INTO v_enr, v_class;
  END IF;
  PERFORM _sec_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    INSERT INTO teacher_observation (organization_id, enrollment_id, class_id, teacher_id, observed_at, status)
    VALUES ('a0000000-0000-4000-8000-000000000001', v_enr, v_class, v_teacher, now(), 'recorded');
    PERFORM _sec_record(18, 'observation writer creates evidence', true);
  EXCEPTION WHEN OTHERS THEN
    PERFORM _sec_record(18, 'observation writer creates evidence', false);
  END;
END $$;

-- 19 staff cannot create observation
DO $$
DECLARE v_enr uuid; v_class uuid; v_teacher uuid;
BEGIN
  PERFORM _sec_as_auth('a2222222-2222-4222-8222-222222222222');
  SELECT t.id INTO v_teacher FROM teacher t WHERE t.organization_id = 'a0000000-0000-4000-8000-000000000001' LIMIT 1;
  SELECT e.id, e.class_id INTO v_enr, v_class FROM enrollment e WHERE e.organization_id = 'a0000000-0000-4000-8000-000000000001' LIMIT 1;
  BEGIN
    INSERT INTO teacher_observation (organization_id, enrollment_id, class_id, teacher_id, observed_at, status)
    VALUES ('a0000000-0000-4000-8000-000000000001', v_enr, v_class, v_teacher, now(), 'recorded');
    PERFORM _sec_record(19, 'no observation.record denied', false);
  EXCEPTION WHEN OTHERS THEN
    PERFORM _sec_record(19, 'no observation.record denied', true);
  END;
END $$;

-- 20 staff cannot assign self role
DO $$
DECLARE v_role uuid;
BEGIN
  PERFORM _sec_as_auth('a2222222-2222-4222-8222-222222222222');
  SELECT id INTO v_role FROM role WHERE organization_id = 'a0000000-0000-4000-8000-000000000001' AND code = 'admin' LIMIT 1;
  BEGIN
    INSERT INTO user_role (organization_id, user_id, role_id, effective_from, status)
    VALUES ('a0000000-0000-4000-8000-000000000001', 'a2000000-0000-4000-8000-000000000001', v_role, CURRENT_DATE, 'active');
    PERFORM _sec_record(20, 'self role assign denied', false);
  EXCEPTION WHEN OTHERS THEN
    PERFORM _sec_record(20, 'self role assign denied', true);
  END;
END $$;

-- 21 staff cannot grant permission on role
DO $$
DECLARE v_role uuid; v_perm uuid;
BEGIN
  PERFORM _sec_as_auth('a2222222-2222-4222-8222-222222222222');
  SELECT id INTO v_role FROM role WHERE organization_id = 'a0000000-0000-4000-8000-000000000001' AND code = 'staff' LIMIT 1;
  SELECT id INTO v_perm FROM permission WHERE code = 'student.create' LIMIT 1;
  BEGIN
    INSERT INTO role_permission (role_id, permission_id) VALUES (v_role, v_perm);
    PERFORM _sec_record(21, 'self permission grant denied', false);
  EXCEPTION WHEN OTHERS THEN
    PERFORM _sec_record(21, 'self permission grant denied', true);
  END;
END $$;

-- 22 org A admin cannot manage org B roles
DO $$
DECLARE v_role uuid; v_rows integer;
BEGIN
  PERFORM _sec_as_super();
  SELECT id INTO v_role FROM role WHERE organization_id = 'b0000000-0000-4000-8000-000000000001' LIMIT 1;
  PERFORM _sec_as_auth('a1111111-1111-4111-8111-111111111111');
  UPDATE role SET code = 'hacked' WHERE id = v_role;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  PERFORM _sec_record(22, 'cross-org role manage denied', v_rows = 0);
END $$;

-- 23 staff cannot mutate permission codes
DO $$
DECLARE v_rows integer;
BEGIN
  PERFORM _sec_as_auth('a2222222-2222-4222-8222-222222222222');
  UPDATE permission SET code = 'hacked' WHERE code = 'student.read';
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  PERFORM _sec_record(23, 'permission mutate denied', v_rows = 0);
END $$;

-- 24 staff cannot change own organization_id
DO $$
BEGIN
  PERFORM _sec_as_auth('a2222222-2222-4222-8222-222222222222');
  BEGIN
    UPDATE app_user SET organization_id = 'b0000000-0000-4000-8000-000000000001'
    WHERE id = 'a2000000-0000-4000-8000-000000000001';
    PERFORM _sec_record(24, 'self org change denied', false);
  EXCEPTION WHEN OTHERS THEN
    PERFORM _sec_record(24, 'self org change denied', true);
  END;
END $$;

-- 25-29 historical constraints under RLS context
DO $$
DECLARE v_ar uuid;
BEGIN
  PERFORM _sec_as_super();
  INSERT INTO assessment (organization_id, class_id, assessment_type_code, title, max_score, assessed_on, status)
  SELECT 'a0000000-0000-4000-8000-000000000001', c.id, 'quiz', 'RLS Q', 20, CURRENT_DATE, 'open'
  FROM class c WHERE c.organization_id = 'a0000000-0000-4000-8000-000000000001' LIMIT 1;
  INSERT INTO assessment_result (organization_id, assessment_id, enrollment_id, raw_score, max_score, status, finalized_at)
  SELECT 'a0000000-0000-4000-8000-000000000001', a.id, e.id, 10, 20, 'finalized', now()
  FROM assessment a, enrollment e
  WHERE a.organization_id = 'a0000000-0000-4000-8000-000000000001'
    AND e.organization_id = 'a0000000-0000-4000-8000-000000000001'
  LIMIT 1
  RETURNING id INTO v_ar;
  PERFORM _sec_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    UPDATE assessment_result SET raw_score = 99 WHERE id = v_ar;
    PERFORM _sec_record(25, 'finalized result protected under rls', false);
  EXCEPTION WHEN OTHERS THEN
    PERFORM _sec_record(25, 'finalized result protected under rls', true);
  END;
END $$;

DO $$
DECLARE v_ses uuid; v_t2 uuid;
BEGIN
  PERFORM _sec_as_super();
  SELECT ts.id INTO v_ses FROM teaching_session ts
  WHERE ts.organization_id = 'a0000000-0000-4000-8000-000000000001' AND ts.status = 'completed' LIMIT 1;
  IF v_ses IS NULL THEN
    INSERT INTO teaching_session (organization_id, class_id, teacher_id, scheduled_start_at, scheduled_end_at, status)
    SELECT 'a0000000-0000-4000-8000-000000000001', c.id, t.id, now(), now() + interval '1 hour', 'completed'
    FROM class c, teacher t
    WHERE c.organization_id = 'a0000000-0000-4000-8000-000000000001'
      AND t.organization_id = 'a0000000-0000-4000-8000-000000000001'
    LIMIT 1
    RETURNING id INTO v_ses;
  END IF;
  SELECT t.id INTO v_t2
  FROM teacher t
  WHERE t.organization_id = 'a0000000-0000-4000-8000-000000000001'
    AND t.id <> (SELECT teacher_id FROM teaching_session WHERE id = v_ses)
  LIMIT 1;
  IF v_t2 IS NULL THEN
    INSERT INTO teacher (organization_id, given_name, family_name)
    VALUES ('a0000000-0000-4000-8000-000000000001', 'Alt', 'Teacher')
    RETURNING id INTO v_t2;
  END IF;
  PERFORM _sec_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    UPDATE teaching_session SET teacher_id = v_t2 WHERE id = v_ses;
    PERFORM _sec_record(26, 'completed session teacher protected', false);
  EXCEPTION WHEN OTHERS THEN
    PERFORM _sec_record(26, 'completed session teacher protected', true);
  END;
END $$;

DO $$
DECLARE v_ch uuid;
BEGIN
  PERFORM _sec_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT id INTO v_ch FROM charge WHERE organization_id = 'a0000000-0000-4000-8000-000000000001' LIMIT 1;
  BEGIN
    UPDATE charge SET amount = 999999 WHERE id = v_ch;
    PERFORM _sec_record(27, 'immutable charge amount protected', false);
  EXCEPTION WHEN OTHERS THEN
    PERFORM _sec_record(27, 'immutable charge amount protected', true);
  END;
END $$;

DO $$
DECLARE v_pay uuid; v_chg uuid; v_rows integer;
BEGIN
  PERFORM _sec_as_super();
  SELECT id INTO v_chg FROM charge WHERE organization_id = 'b0000000-0000-4000-8000-000000000001' LIMIT 1;
  INSERT INTO payment (organization_id, guardian_id, amount, paid_at, method_code, status)
  SELECT 'b0000000-0000-4000-8000-000000000001', g.id, 100000, now(), 'cash', 'posted'
  FROM guardian g WHERE g.organization_id = 'b0000000-0000-4000-8000-000000000001' LIMIT 1
  RETURNING id INTO v_pay;
  PERFORM _sec_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    INSERT INTO payment_allocation (organization_id, payment_id, charge_id, amount)
    VALUES ('b0000000-0000-4000-8000-000000000001', v_pay, v_chg, 1000);
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    PERFORM _sec_record(28, 'cross-org allocation denied', v_rows = 0);
  EXCEPTION WHEN OTHERS THEN
    PERFORM _sec_record(28, 'cross-org allocation denied', true);
  END;
END $$;

DO $$
DECLARE v_cat uuid; v_g2 uuid;
BEGIN
  PERFORM _sec_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT ec.id, cg.id INTO v_cat, v_g2
  FROM expense_category ec
  JOIN cost_group cg ON cg.id = ec.cost_group_id
  WHERE ec.organization_id = 'a0000000-0000-4000-8000-000000000001'
    AND cg.group_slot = 2
  LIMIT 1;
  BEGIN
    INSERT INTO expense (organization_id, expense_category_id, cost_group_id, amount, incurred_date)
    VALUES ('a0000000-0000-4000-8000-000000000001', v_cat, (SELECT id FROM cost_group WHERE organization_id = 'a0000000-0000-4000-8000-000000000001' AND group_slot = 1), 1000, CURRENT_DATE);
    PERFORM _sec_record(29, 'expense group mismatch denied', false);
  EXCEPTION WHEN OTHERS THEN
    PERFORM _sec_record(29, 'expense group mismatch denied', true);
  END;
END $$;

-- 30 disabled app_user denied
DO $$
DECLARE c integer;
BEGIN
  PERFORM _sec_as_auth('a3333333-3333-4333-8333-333333333333');
  SELECT count(*) INTO c FROM student;
  PERFORM _sec_record(30, 'disabled app_user denied', c = 0);
END $$;

DO $$
DECLARE total integer; passed integer; failed integer;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE result = 'PASS'), count(*) FILTER (WHERE result = 'FAIL')
  INTO total, passed, failed FROM _sec_results;
  RAISE NOTICE 'M0 Security Tests: % / % passed (% failed)', passed, total, failed;
  IF failed > 0 OR total <> 30 THEN
    RAISE EXCEPTION 'Security tests failed: % of % (expected 30)', failed, total;
  END IF;
END $$;

SELECT test_no, test_name, result FROM _sec_results ORDER BY test_no;
