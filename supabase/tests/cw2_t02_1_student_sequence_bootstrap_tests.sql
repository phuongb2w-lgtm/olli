-- CW2-T02.1: student sequence bootstrap vs legacy students

CREATE TEMP TABLE IF NOT EXISTS _cw2_t021_results (
  test_no integer PRIMARY KEY,
  test_name text NOT NULL,
  result text NOT NULL CHECK (result IN ('PASS', 'FAIL'))
);

GRANT ALL ON TABLE _cw2_t021_results TO authenticated, anon;

CREATE OR REPLACE FUNCTION _cw2_t021_record(test_no integer, test_name text, passed boolean)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO _cw2_t021_results (test_no, test_name, result)
  VALUES (test_no, test_name, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END);
END;
$$;

CREATE OR REPLACE FUNCTION _cw2_t021_as_postgres()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
END;
$$;

-- 1: legacy seed codes do not advance org A floor (HV001/HV002)
DO $$
DECLARE v_last integer;
BEGIN
  PERFORM _cw2_t021_as_postgres();
  SELECT last_allocated_sequence INTO v_last
  FROM public.organization_student_sequence
  WHERE organization_id = 'a0000000-0000-4000-8000-000000000001';
  PERFORM _cw2_t021_record(
    1,
    'legacy student codes leave sequence at 0',
    v_last = 0
  );
END $$;

-- 2: shaped historical code raises floor (no rewrite of legacy rows)
DO $$
DECLARE
  v_id uuid := 'a5100000-0000-4000-8000-000000000099';
  v_last integer;
  v_legacy text;
BEGIN
  PERFORM _cw2_t021_as_postgres();
  INSERT INTO public.student (
    id, organization_id, given_name, family_name, student_code, status
  ) VALUES (
    v_id,
    'a0000000-0000-4000-8000-000000000001',
    'Bootstrap',
    'CW2',
    '02170037',
    'active'
  );
  SELECT last_allocated_sequence INTO v_last
  FROM public.organization_student_sequence
  WHERE organization_id = 'a0000000-0000-4000-8000-000000000001';
  SELECT student_code INTO v_legacy
  FROM public.student
  WHERE id = 'a5100000-0000-4000-8000-000000000001';
  PERFORM _cw2_t021_record(
    2,
    'CW2-shaped code sets floor to 37 without changing legacy HV001',
    v_last = 37 AND v_legacy = 'HV001'
  );
END $$;

-- 3: next allocation would be 38 (documented floor semantics)
DO $$
DECLARE v_floor integer;
BEGIN
  v_floor := public._cw2_compute_organization_student_sequence_floor(
    'a0000000-0000-4000-8000-000000000001'
  );
  PERFORM _cw2_t021_record(3, 'computed floor matches stored counter', v_floor = 37);
END $$;

-- 4: org B isolated (no shaped codes in seed)
DO $$
DECLARE v_b integer;
BEGIN
  SELECT last_allocated_sequence INTO v_b
  FROM public.organization_student_sequence
  WHERE organization_id = 'b0000000-0000-4000-8000-000000000001';
  PERFORM _cw2_t021_record(4, 'org B bootstrap isolated at 0', v_b = 0);
END $$;

-- 5: non-shaped 8-digit with 0000 suffix ignored
DO $$
DECLARE v_before integer; v_after integer;
BEGIN
  PERFORM _cw2_t021_as_postgres();
  SELECT last_allocated_sequence INTO v_before
  FROM public.organization_student_sequence
  WHERE organization_id = 'b0000000-0000-4000-8000-000000000001';
  INSERT INTO public.student (
    organization_id, given_name, family_name, student_code, status
  ) VALUES (
    'b0000000-0000-4000-8000-000000000001',
    'Provisional',
    'Display',
    '02170000',
    'prospect'
  );
  SELECT last_allocated_sequence INTO v_after
  FROM public.organization_student_sequence
  WHERE organization_id = 'b0000000-0000-4000-8000-000000000001';
  PERFORM _cw2_t021_record(
    5,
    'CCYY0000-shaped code does not consume sequence',
    v_before = v_after AND v_after = 0
  );
END $$;

-- 6: portfolio STT independent of student sequence
DO $$
DECLARE v_portfolio bigint; v_seq integer;
BEGIN
  SELECT COALESCE(max(workspace_sequence), 0) INTO v_portfolio
  FROM public.consultant_portfolio_entry
  WHERE organization_id = 'a0000000-0000-4000-8000-000000000001';
  SELECT last_allocated_sequence INTO v_seq
  FROM public.organization_student_sequence
  WHERE organization_id = 'a0000000-0000-4000-8000-000000000001';
  PERFORM _cw2_t021_record(
    6,
    'portfolio STT does not drive registration sequence',
    v_portfolio IS NOT NULL AND v_seq = 37
  );
END $$;

-- 7: extract helper rejects legacy HV prefix
DO $$
DECLARE v_n integer;
BEGIN
  v_n := public._cw2_extract_official_sequence_nnnn('HV002');
  PERFORM _cw2_t021_record(7, 'legacy code not parsed as NNNN', v_n IS NULL);
END $$;

-- 8: consultant code sanity — primary owner still 01
DO $$
DECLARE v_code char(2);
BEGIN
  SELECT consultant_operational_code INTO v_code
  FROM public.app_user
  WHERE id = 'a1000000-0000-4000-8000-000000000001';
  PERFORM _cw2_t021_record(8, 'primary owner consultant code 01', v_code = '01');
END $$;

DO $$
DECLARE v_fail integer; v_total integer;
BEGIN
  SELECT count(*) FILTER (WHERE result = 'FAIL'), count(*) INTO v_fail, v_total
  FROM _cw2_t021_results;
  IF v_fail > 0 THEN
    RAISE NOTICE 'CW2-T02.1 failing: %', (
      SELECT string_agg(test_no::text || ': ' || test_name, '; ' ORDER BY test_no)
      FROM _cw2_t021_results WHERE result = 'FAIL'
    );
    RAISE EXCEPTION 'CW2-T02.1 tests failed: %/% failed', v_fail, v_total;
  END IF;
  RAISE NOTICE 'CW2-T02.1 student sequence bootstrap tests: %/% PASS', v_total, v_total;
END $$;
