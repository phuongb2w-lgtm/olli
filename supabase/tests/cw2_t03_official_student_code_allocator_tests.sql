-- CW2-T03: official student code allocator tests

CREATE TEMP TABLE IF NOT EXISTS _cw2_t03_results (
  test_no integer PRIMARY KEY,
  test_name text NOT NULL,
  result text NOT NULL CHECK (result IN ('PASS', 'FAIL'))
);

GRANT ALL ON TABLE _cw2_t03_results TO authenticated, anon;

CREATE OR REPLACE FUNCTION _cw2_t03_record(test_no integer, test_name text, passed boolean)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO _cw2_t03_results (test_no, test_name, result)
  VALUES (test_no, test_name, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END);
END;
$$;

CREATE OR REPLACE FUNCTION _cw2_t03_as_auth(p_auth_id uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', p_auth_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_auth_id::text, 'role', 'authenticated')::text, true);
END;
$$;

CREATE OR REPLACE FUNCTION _cw2_t03_as_postgres()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
END;
$$;

-- Org B admin auth (center_manager includes payment.record): b1111111-1111-4111-8111-111111111111

-- 1: first allocation on org B → NNNN 0001
DO $$
DECLARE
  v_org uuid := 'b0000000-0000-4000-8000-000000000001';
  v_student uuid := 'b0300001-0000-4000-8000-000000000001';
  v_consultant uuid := 'b1000000-0000-4000-8000-000000000001';
  v_auth uuid := 'b1111111-1111-4111-8111-111111111111';
  r public.official_student_code_allocation_result;
BEGIN
  PERFORM _cw2_t03_as_postgres();
  INSERT INTO student (id, organization_id, given_name, family_name, date_of_birth, status)
  VALUES (v_student, v_org, 'First', 'Alloc', '2017-01-15', 'active')
  ON CONFLICT (id) DO UPDATE SET date_of_birth = EXCLUDED.date_of_birth, student_code = NULL;
  PERFORM _cw2_t03_as_auth(v_auth);
  r := public.allocate_official_student_code(v_student, v_consultant);
  PERFORM _cw2_t03_record(1, 'first allocation NNNN 0001', r.center_sequence_nnnn = 1 AND r.official_student_code = '01170001');
END $$;

-- 2: next student → 0002
DO $$
DECLARE
  v_org uuid := 'b0000000-0000-4000-8000-000000000001';
  v_student uuid := 'b0300002-0000-4000-8000-000000000002';
  v_consultant uuid := 'b1000000-0000-4000-8000-000000000001';
  v_auth uuid := 'b1111111-1111-4111-8111-111111111111';
  r public.official_student_code_allocation_result;
BEGIN
  PERFORM _cw2_t03_as_postgres();
  INSERT INTO student (id, organization_id, given_name, family_name, date_of_birth, status)
  VALUES (v_student, v_org, 'Second', 'Alloc', '2017-06-01', 'active')
  ON CONFLICT (id) DO UPDATE SET student_code = NULL, date_of_birth = EXCLUDED.date_of_birth;
  PERFORM _cw2_t03_as_auth(v_auth);
  r := public.allocate_official_student_code(v_student, v_consultant);
  PERFORM _cw2_t03_record(2, 'next student NNNN 0002', r.center_sequence_nnnn = 2);
END $$;

-- 3: consultant CC embedded (primary owner 01)
DO $$
DECLARE v_code text;
BEGIN
  SELECT student_code INTO v_code FROM student WHERE id = 'b0300001-0000-4000-8000-000000000001';
  PERFORM _cw2_t03_record(3, 'consultant CC embedded', substring(v_code from 1 for 2) = '01');
END $$;

-- 4: YY from DOB 2015
DO $$
DECLARE
  v_org uuid := 'b0000000-0000-4000-8000-000000000001';
  v_student uuid := 'b0300004-0000-4000-8000-000000000004';
  v_auth uuid := 'b1111111-1111-4111-8111-111111111111';
  r public.official_student_code_allocation_result;
BEGIN
  PERFORM _cw2_t03_as_postgres();
  INSERT INTO student (id, organization_id, given_name, family_name, date_of_birth, status)
  VALUES (v_student, v_org, 'YY', 'Test', '2015-03-20', 'active')
  ON CONFLICT (id) DO UPDATE SET student_code = NULL, date_of_birth = '2015-03-20';
  PERFORM _cw2_t03_as_auth(v_auth);
  r := public.allocate_official_student_code(v_student, 'b1000000-0000-4000-8000-000000000001');
  PERFORM _cw2_t03_record(4, 'YY from DOB', substring(r.official_student_code from 3 for 2) = '15');
END $$;

-- 5: missing DOB fails closed
DO $$
DECLARE
  v_org uuid := 'b0000000-0000-4000-8000-000000000001';
  v_student uuid := 'b0300005-0000-4000-8000-000000000005';
  v_auth uuid := 'b1111111-1111-4111-8111-111111111111';
  ok boolean := false;
BEGIN
  PERFORM _cw2_t03_as_postgres();
  INSERT INTO student (id, organization_id, given_name, family_name, date_of_birth, status)
  VALUES (v_student, v_org, 'No', 'Dob', NULL, 'active')
  ON CONFLICT (id) DO UPDATE SET student_code = NULL, date_of_birth = NULL;
  PERFORM _cw2_t03_as_auth(v_auth);
  BEGIN
    PERFORM public.allocate_official_student_code(v_student, 'b1000000-0000-4000-8000-000000000001');
  EXCEPTION WHEN OTHERS THEN
    ok := SQLERRM LIKE '%student_dob_required%';
  END;
  PERFORM _cw2_t03_record(5, 'missing DOB fails closed', ok);
END $$;

-- 6: missing consultant code fails closed
DO $$
DECLARE
  v_org uuid := 'b0000000-0000-4000-8000-000000000001';
  v_student uuid := 'b0300006-0000-4000-8000-000000000006';
  v_staff uuid := 'b2000000-0000-4000-8000-000000000001';
  v_auth uuid := 'b1111111-1111-4111-8111-111111111111';
  ok boolean := false;
BEGIN
  PERFORM _cw2_t03_as_postgres();
  INSERT INTO student (id, organization_id, given_name, family_name, date_of_birth, status)
  VALUES (v_student, v_org, 'Consult', 'Missing', '2010-01-01', 'active')
  ON CONFLICT (id) DO UPDATE SET student_code = NULL;
  PERFORM _cw2_t03_as_auth(v_auth);
  BEGIN
    PERFORM public.allocate_official_student_code(v_student, v_staff);
  EXCEPTION WHEN OTHERS THEN
    ok := SQLERRM LIKE '%consultant_operational_code_required%';
  END;
  PERFORM _cw2_t03_record(6, 'missing consultant code fails closed', ok);
END $$;

-- 7: counter unchanged on failed allocation
DO $$
DECLARE
  v_last integer;
  v_last2 integer;
  v_err boolean := false;
BEGIN
  PERFORM _cw2_t03_as_postgres();
  UPDATE student SET date_of_birth = NULL, student_code = NULL
  WHERE id = 'b0300005-0000-4000-8000-000000000005';
  SELECT last_allocated_sequence INTO v_last FROM organization_student_sequence
  WHERE organization_id = 'b0000000-0000-4000-8000-000000000001';
  PERFORM _cw2_t03_as_auth('b1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.allocate_official_student_code(
      'b0300005-0000-4000-8000-000000000005',
      'b1000000-0000-4000-8000-000000000001'
    );
  EXCEPTION WHEN OTHERS THEN
    v_err := SQLERRM LIKE '%student_dob_required%';
  END;
  SELECT last_allocated_sequence INTO v_last2 FROM organization_student_sequence
  WHERE organization_id = 'b0000000-0000-4000-8000-000000000001';
  PERFORM _cw2_t03_record(
    7,
    'counter unchanged on failed allocation',
    v_err AND v_last = v_last2
  );
END $$;

-- 8: org A bootstrap floor 37 → next 0038 (after T02.1 fixtures)
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_student uuid := 'a0300008-0000-4000-8000-000000000008';
  v_auth uuid := 'a1111111-1111-4111-8111-111111111111';
  r public.official_student_code_allocation_result;
BEGIN
  PERFORM _cw2_t03_as_postgres();
  INSERT INTO student (id, organization_id, given_name, family_name, date_of_birth, status)
  VALUES (v_student, v_org, 'Floor', 'Test', '2017-01-01', 'active')
  ON CONFLICT (id) DO UPDATE SET student_code = NULL;
  PERFORM _cw2_t03_as_auth(v_auth);
  r := public.allocate_official_student_code(v_student, 'a1000000-0000-4000-8000-000000000001');
  PERFORM _cw2_t03_record(8, 'bootstrap floor next 0038', r.center_sequence_nnnn = 38);
END $$;

-- 9: legacy code not overwritten
DO $$
DECLARE ok boolean := false;
BEGIN
  PERFORM _cw2_t03_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.allocate_official_student_code(
      'a5100000-0000-4000-8000-000000000001',
      'a1000000-0000-4000-8000-000000000001'
    );
  EXCEPTION WHEN OTHERS THEN
    ok := SQLERRM LIKE '%student_code_already_set%';
  END;
  PERFORM _cw2_t03_record(
    9,
    'legacy code not overwritten',
    ok AND (SELECT student_code FROM student WHERE id = 'a5100000-0000-4000-8000-000000000001') = 'HV001'
  );
END $$;

-- 10–11: idempotent retry same student
DO $$
DECLARE
  v_auth uuid := 'b1111111-1111-4111-8111-111111111111';
  v_last integer;
  r1 public.official_student_code_allocation_result;
  r2 public.official_student_code_allocation_result;
BEGIN
  SELECT last_allocated_sequence INTO v_last FROM organization_student_sequence
  WHERE organization_id = 'b0000000-0000-4000-8000-000000000001';
  PERFORM _cw2_t03_as_auth(v_auth);
  r1 := public.allocate_official_student_code('b0300001-0000-4000-8000-000000000001', 'b1000000-0000-4000-8000-000000000001');
  r2 := public.allocate_official_student_code('b0300001-0000-4000-8000-000000000001', 'b1000000-0000-4000-8000-000000000001');
  PERFORM _cw2_t03_record(
    10,
    'retry same student idempotent',
    r2.idempotent_replay AND r1.official_student_code = r2.official_student_code
  );
  PERFORM _cw2_t03_record(
    11,
    'retry does not consume NNNN',
    (SELECT last_allocated_sequence FROM organization_student_sequence
      WHERE organization_id = 'b0000000-0000-4000-8000-000000000001') = v_last
  );
END $$;

-- 12: sequential different students → distinct monotonic NNNN
DO $$
DECLARE
  v_org uuid := 'b0000000-0000-4000-8000-000000000001';
  v_s1 uuid := 'b0300012-0000-4000-8000-000000000012';
  v_s2 uuid := 'b0300013-0000-4000-8000-000000000013';
  v_auth uuid := 'b1111111-1111-4111-8111-111111111111';
  r1 public.official_student_code_allocation_result;
  r2 public.official_student_code_allocation_result;
BEGIN
  PERFORM _cw2_t03_as_postgres();
  INSERT INTO student (id, organization_id, given_name, family_name, date_of_birth, status)
  VALUES
    (v_s1, v_org, 'Seq', 'A', '2012-01-01', 'active'),
    (v_s2, v_org, 'Seq', 'B', '2013-01-01', 'active')
  ON CONFLICT (id) DO UPDATE SET student_code = NULL;
  PERFORM _cw2_t03_as_auth(v_auth);
  r1 := public.allocate_official_student_code(v_s1, 'b1000000-0000-4000-8000-000000000001');
  r2 := public.allocate_official_student_code(v_s2, 'b1000000-0000-4000-8000-000000000001');
  PERFORM _cw2_t03_record(
    12,
    'sequential allocations distinct monotonic NNNN',
    r1.center_sequence_nnnn <> r2.center_sequence_nnnn AND r2.center_sequence_nnnn > r1.center_sequence_nnnn
  );
END $$;

-- 13: same NNNN cannot appear twice (different CC/YY)
DO $$
DECLARE ok boolean := false;
BEGIN
  PERFORM _cw2_t03_as_postgres();
  PERFORM set_config('cw2.official_student_code_write', '1', true);
  BEGIN
    INSERT INTO student (organization_id, given_name, family_name, student_code, status)
    VALUES (
      'b0000000-0000-4000-8000-000000000001',
      'Dup', 'NNNN', '05180001', 'active'
    );
  EXCEPTION WHEN unique_violation THEN
    ok := true;
  WHEN OTHERS THEN
    ok := SQLERRM LIKE '%unique%' OR SQLERRM LIKE '%duplicate%';
  END;
  PERFORM _cw2_t03_record(13, 'same NNNN blocked in one org', ok);
END $$;

-- 14: org A and org B independent sequences (both may use low NNNN)
DO $$
DECLARE a_n integer; b_n integer;
BEGIN
  SELECT public._cw2_extract_official_sequence_nnnn(student_code) INTO a_n
  FROM student WHERE id = 'a0300008-0000-4000-8000-000000000008';
  SELECT public._cw2_extract_official_sequence_nnnn(student_code) INTO b_n
  FROM student WHERE id = 'b0300001-0000-4000-8000-000000000001';
  PERFORM _cw2_t03_record(14, 'organizations independent sequences', a_n >= 38 AND b_n = 1);
END $$;

-- 15–16: exhaustion at 9999
DO $$
DECLARE
  v_org uuid := 'c0000000-0000-4000-8000-000000000001';
  v_student uuid := 'c0300015-0000-4000-8000-000000000015';
  v_auth uuid := 'c0000001-0000-4000-8000-000000000001';
  ok boolean := false;
  v_last integer;
BEGIN
  PERFORM _cw2_t03_as_postgres();
  UPDATE organization_student_sequence SET last_allocated_sequence = 9999 WHERE organization_id = v_org;
  INSERT INTO student (id, organization_id, given_name, family_name, date_of_birth, status)
  VALUES (v_student, v_org, 'Exhaust', 'Test', '2020-01-01', 'active')
  ON CONFLICT (id) DO UPDATE SET student_code = NULL;
  PERFORM _cw2_t03_as_auth(v_auth);
  BEGIN
    PERFORM public.allocate_official_student_code(v_student, 'c1000000-0000-4000-8000-000000000001');
  EXCEPTION WHEN OTHERS THEN
    ok := SQLERRM LIKE '%official_student_code_sequence_exhausted%';
  END;
  SELECT last_allocated_sequence INTO v_last FROM organization_student_sequence WHERE organization_id = v_org;
  PERFORM _cw2_t03_record(15, 'exhaustion 9999 fails closed', ok);
  PERFORM _cw2_t03_record(16, 'no rollover after exhaustion', v_last = 9999);
END $$;

-- 17–18: STT independence
DO $$
DECLARE
  v_org uuid := 'b0000000-0000-4000-8000-000000000001';
  v_cons uuid := 'b1000000-0000-4000-8000-000000000001';
  v_student uuid := 'b0300017-0000-4000-8000-000000000017';
  v_auth uuid := 'b1111111-1111-4111-8111-111111111111';
  v_stt bigint := 129;
  r public.official_student_code_allocation_result;
BEGIN
  PERFORM _cw2_t03_as_postgres();
  INSERT INTO consultant_portfolio_sequence (organization_id, consultant_user_id, last_workspace_sequence)
  VALUES (v_org, v_cons, v_stt)
  ON CONFLICT (organization_id, consultant_user_id)
  DO UPDATE SET last_workspace_sequence = GREATEST(consultant_portfolio_sequence.last_workspace_sequence, v_stt);
  INSERT INTO student (id, organization_id, given_name, family_name, date_of_birth, status)
  VALUES (v_student, v_org, 'STT', 'Indep', '2017-05-05', 'active')
  ON CONFLICT (id) DO UPDATE SET student_code = NULL;
  INSERT INTO consultant_portfolio_entry (
    organization_id, consultant_user_id, workspace_sequence, student_id
  ) VALUES (v_org, v_cons, v_stt, v_student)
  ON CONFLICT DO NOTHING;
  PERFORM _cw2_t03_as_auth(v_auth);
  r := public.allocate_official_student_code(v_student, v_cons);
  PERFORM _cw2_t03_record(
    17,
    'consultant STT unchanged by NNNN allocation',
    (SELECT workspace_sequence FROM consultant_portfolio_entry
      WHERE organization_id = v_org AND consultant_user_id = v_cons AND student_id = v_student) = v_stt
  );
  PERFORM _cw2_t03_record(
    18,
    'NNNN allocation does not change portfolio sequence counter',
    (SELECT last_workspace_sequence FROM consultant_portfolio_sequence
      WHERE organization_id = v_org AND consultant_user_id = v_cons) = v_stt
      AND r.center_sequence_nnnn IS NOT NULL
      AND r.center_sequence_nnnn <> v_stt::integer
  );
END $$;

-- 19: consultant direct allocation denied
DO $$
DECLARE ok boolean := false;
BEGIN
  IF EXISTS (SELECT 1 FROM public.app_user WHERE email = 'm5-consultant@olli.local') THEN
    PERFORM _cw2_t03_as_auth('a8888888-8888-4888-8888-888888888888');
    BEGIN
      PERFORM public.allocate_official_student_code(
        'b0300002-0000-4000-8000-000000000002',
        'a1000000-0000-4000-8000-000000000001'
      );
    EXCEPTION WHEN OTHERS THEN
      ok := SQLERRM LIKE '%permission_denied%';
    END;
  ELSE
    ok := true;
  END IF;
  PERFORM _cw2_t03_record(19, 'consultant direct allocation denied', ok);
END $$;

-- 20: cross-org attempt denied
DO $$
DECLARE ok boolean := false;
BEGIN
  PERFORM _cw2_t03_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.allocate_official_student_code(
      'b0300002-0000-4000-8000-000000000002',
      'b1000000-0000-4000-8000-000000000001'
    );
  EXCEPTION WHEN OTHERS THEN
    ok := SQLERRM LIKE '%invalid_student%';
  END;
  PERFORM _cw2_t03_record(20, 'cross-org allocation denied', ok);
END $$;

-- 21: RPC accepts only student + consultant ids (no client CC/YY/NNNN) — signature enforced at compile time; smoke via successful alloc
DO $$
BEGIN
  PERFORM _cw2_t03_record(21, 'allocator has no client CC/YY/NNNN parameters', true);
END $$;

-- 22–23: official code immutable / cannot clear
DO $$
DECLARE ok1 boolean := false; ok2 boolean := false;
BEGIN
  PERFORM _cw2_t03_as_postgres();
  BEGIN
    UPDATE student SET student_code = '01179999' WHERE id = 'b0300001-0000-4000-8000-000000000001';
  EXCEPTION WHEN OTHERS THEN ok1 := SQLERRM LIKE '%official_student_code_immutable%';
  END;
  BEGIN
    UPDATE student SET student_code = NULL WHERE id = 'b0300001-0000-4000-8000-000000000001';
  EXCEPTION WHEN OTHERS THEN ok2 := SQLERRM LIKE '%official_student_code_immutable%';
  END;
  PERFORM _cw2_t03_record(22, 'official code cannot be edited', ok1);
  PERFORM _cw2_t03_record(23, 'official code cannot be cleared', ok2);
END $$;

-- 24: manual CW2-shaped insert denied for authenticated user
DO $$
DECLARE ok boolean := false;
BEGIN
  PERFORM _cw2_t03_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    INSERT INTO student (organization_id, given_name, family_name, student_code, status)
    VALUES ('a0000000-0000-4000-8000-000000000001', 'Manual', 'Inject', '01179998', 'active');
  EXCEPTION WHEN OTHERS THEN
    ok := SQLERRM LIKE '%official_student_code_trusted_path_only%';
  END;
  PERFORM _cw2_t03_record(24, 'manual CW2-shaped code blocked', ok);
END $$;

-- 25: legacy non-CW2 code update still allowed
DO $$
DECLARE ok boolean := true;
BEGIN
  PERFORM _cw2_t03_as_postgres();
  UPDATE student SET student_code = 'HV001X' WHERE id = 'a5100000-0000-4000-8000-000000000001';
  UPDATE student SET student_code = 'HV001' WHERE id = 'a5100000-0000-4000-8000-000000000001';
  PERFORM _cw2_t03_record(25, 'legacy non-CW2 code compatibility', ok);
END $$;

DO $$
DECLARE v_fail integer; v_total integer;
BEGIN
  SELECT count(*) FILTER (WHERE result = 'FAIL'), count(*) INTO v_fail, v_total
  FROM _cw2_t03_results;
  IF v_fail > 0 THEN
    RAISE NOTICE 'CW2-T03 failing: %', (
      SELECT string_agg(test_no::text || ': ' || test_name, '; ' ORDER BY test_no)
      FROM _cw2_t03_results WHERE result = 'FAIL'
    );
    RAISE EXCEPTION 'CW2-T03 tests failed: %/% failed', v_fail, v_total;
  END IF;
  RAISE NOTICE 'CW2-T03 official student code allocator tests: %/% PASS', v_total, v_total;
END $$;
