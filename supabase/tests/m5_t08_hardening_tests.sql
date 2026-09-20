-- M5-T08: Management intelligence hardening — security spot checks (17 scenarios)

BEGIN;

CREATE TEMP TABLE _m5_t08_results (
  test_no   integer PRIMARY KEY,
  test_name text NOT NULL,
  result    text NOT NULL CHECK (result IN ('PASS', 'FAIL'))
);

GRANT ALL ON TABLE _m5_t08_results TO authenticated, anon;

CREATE OR REPLACE FUNCTION _m5_t08_record(test_no integer, test_name text, passed boolean)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO _m5_t08_results (test_no, test_name, result)
  VALUES (test_no, test_name, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END);
END;
$$;

CREATE OR REPLACE FUNCTION _m5_t08_as_auth(p_auth_id uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', p_auth_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_auth_id::text, 'role', 'authenticated')::text, true);
END;
$$;

-- 1: exception key contract unchanged
DO $$
DECLARE v_key text;
BEGIN
  v_key := public.build_executive_exception_key('finance', 'receivable_overdue', 'charge', 'abc');
  PERFORM _m5_t08_record(1, 'exception key contract stable', v_key = 'finance|receivable_overdue|charge|abc');
END $$;

-- 2: reader denied list_executive_exceptions
DO $$
DECLARE v_denied boolean := false;
BEGIN
  PERFORM _m5_t08_as_auth('a4444444-4444-4444-8444-444444444444');
  BEGIN
    PERFORM public.list_executive_exceptions(CURRENT_DATE, CURRENT_DATE, NULL, NULL, NULL, NULL, true);
    v_denied := false;
  EXCEPTION WHEN others THEN
    v_denied := true;
  END;
  PERFORM _m5_t08_record(2, 'reader denied executive exceptions RPC', v_denied);
END $$;

-- 3: consultant denied executive overview
DO $$
DECLARE v_denied boolean := false;
BEGIN
  PERFORM _m5_t08_as_auth('d1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.get_executive_overview(CURRENT_DATE, CURRENT_DATE, false);
    v_denied := false;
  EXCEPTION WHEN others THEN
    v_denied := true;
  END;
  PERFORM _m5_t08_record(3, 'consultant denied executive overview RPC', v_denied);
END $$;

-- 4: teacher denied executive exceptions
DO $$
DECLARE v_denied boolean := false;
BEGIN
  PERFORM _m5_t08_as_auth('e2222222-2222-4222-8222-222222222222');
  BEGIN
    PERFORM public.list_executive_exceptions(CURRENT_DATE, CURRENT_DATE, NULL, NULL, NULL, NULL, true);
    v_denied := false;
  EXCEPTION WHEN others THEN
    v_denied := true;
  END;
  PERFORM _m5_t08_record(4, 'teacher denied executive exceptions RPC', v_denied);
END $$;

-- 5: manager can load worklist summary
DO $$
DECLARE v jsonb;
  v_start date := date_trunc('month', CURRENT_DATE)::date;
  v_end date := (date_trunc('month', CURRENT_DATE) + interval '1 month - 1 day')::date;
BEGIN
  PERFORM _m5_t08_as_auth('a1111111-1111-4111-8111-111111111111');
  v := public.get_executive_exception_worklist_summary(v_start, v_end);
  PERFORM _m5_t08_record(5, 'manager loads worklist summary', v ? 'current_detected_count');
END $$;

-- 6: worklist summary detected count matches domain union size
DO $$
DECLARE v_summary jsonb; v_manual integer;
  v_start date := date_trunc('month', CURRENT_DATE)::date;
  v_end date := (date_trunc('month', CURRENT_DATE) + interval '1 month - 1 day')::date;
BEGIN
  PERFORM _m5_t08_as_auth('a1111111-1111-4111-8111-111111111111');
  v_summary := public.get_executive_exception_worklist_summary(v_start, v_end);
  SELECT (
    (SELECT count(*)::integer FROM public.list_finance_exceptions(v_start, v_end))
    + (SELECT count(*)::integer FROM public.list_crm_admissions_exceptions(v_start, v_end))
    + (SELECT count(*)::integer FROM public.list_academic_exceptions(v_start, v_end))
    + (SELECT count(*)::integer FROM public.list_teaching_ops_exceptions(v_start, v_end))
  ) INTO v_manual;
  PERFORM _m5_t08_record(
    6,
    'worklist summary detected count equals domain union',
    (v_summary->>'current_detected_count')::integer = v_manual
  );
END $$;

-- 7: reader denied follow-up mutation
DO $$
DECLARE v_denied boolean := false;
BEGIN
  PERFORM _m5_t08_as_auth('a4444444-4444-4444-8444-444444444444');
  BEGIN
    PERFORM public.save_executive_exception_follow_up(
      'finance|x|y|z', 'finance', 'x', 'y', 'z', 'open', NULL
    );
    v_denied := false;
  EXCEPTION WHEN others THEN
    v_denied := true;
  END;
  PERFORM _m5_t08_record(7, 'reader denied follow-up mutation', v_denied);
END $$;

-- 8: manager retains follow-up manage permission
DO $$
DECLARE v_ok boolean;
BEGIN
  PERFORM _m5_t08_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT public.has_permission('report.executive.follow_up.manage') INTO v_ok;
  PERFORM _m5_t08_record(8, 'manager has follow-up manage permission', v_ok);
END $$;

-- 9: org B cannot read org A follow-up via history RPC
DO $$
DECLARE v_cnt_a integer; v_cnt_b integer;
  v_key text := 'finance|receivable_overdue|charge|00000000-0000-4000-8000-000000000088';
BEGIN
  PERFORM _m5_t08_as_auth('a1111111-1111-4111-8111-111111111111');
  SET LOCAL ROLE authenticated;
  PERFORM public.save_executive_exception_follow_up(
    v_key, 'finance', 'receivable_overdue', 'charge',
    '00000000-0000-4000-8000-000000000088', 'open', 'T08 isolation'
  );
  SELECT count(*) INTO v_cnt_a
  FROM public.list_executive_exception_follow_up_history(v_key);

  PERFORM _m5_t08_as_auth('b1111111-1111-4111-8111-111111111111');
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO v_cnt_b
  FROM public.list_executive_exception_follow_up_history(v_key);

  PERFORM _m5_t08_record(
    9,
    'cross-org follow-up history isolated',
    v_cnt_a >= 1 AND v_cnt_b = 0
  );
END $$;

-- 10: finance overview still requires finance or executive permission
DO $$
DECLARE v_denied boolean := false;
BEGIN
  PERFORM _m5_t08_as_auth('a4444444-4444-4444-8444-444444444444');
  BEGIN
    PERFORM public.get_finance_intelligence_overview(CURRENT_DATE, CURRENT_DATE, false);
    v_denied := false;
  EXCEPTION WHEN others THEN
    v_denied := true;
  END;
  PERFORM _m5_t08_record(10, 'reader denied finance intelligence overview', v_denied);
END $$;

-- 11: executive exceptions stable ordering by domain/code/entity
DO $$
DECLARE v_prev text := ''; v_key text;
  v_start date := date_trunc('month', CURRENT_DATE)::date;
  v_end date := (date_trunc('month', CURRENT_DATE) + interval '1 month - 1 day')::date;
  v_ok boolean := true;
BEGIN
  PERFORM _m5_t08_as_auth('a1111111-1111-4111-8111-111111111111');
  FOR v_key IN
    SELECT row->>'exception_key'
    FROM public.list_executive_exceptions(v_start, v_end, NULL, NULL, NULL, NULL, false) row
    ORDER BY row->>'domain', row->>'exception_code', row->>'entity_id'
  LOOP
    IF v_prev <> '' AND v_key < v_prev THEN
      v_ok := false;
      EXIT;
    END IF;
    v_prev := v_key;
  END LOOP;
  PERFORM _m5_t08_record(11, 'executive exceptions deterministic sort keys', v_ok);
END $$;

-- 12: exception filter excludes non-matching historical rows
DO $$
DECLARE v_cnt integer;
  v_start date := date_trunc('month', CURRENT_DATE)::date;
  v_end date := (date_trunc('month', CURRENT_DATE) + interval '1 month - 1 day')::date;
BEGIN
  PERFORM _m5_t08_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_cnt
  FROM public.list_executive_exceptions(
    v_start, v_end, NULL, '__no_such_code__', NULL, NULL, true
  ) row;
  PERFORM _m5_t08_record(12, 'exception code filter excludes unrelated historical', v_cnt = 0);
END $$;

-- 13: T06 finance composition unchanged
DO $$
DECLARE v_exec jsonb; v_fin jsonb;
  v_start date := date_trunc('month', CURRENT_DATE)::date;
  v_end date := (date_trunc('month', CURRENT_DATE) + interval '1 month - 1 day')::date;
BEGIN
  PERFORM _m5_t08_as_auth('a1111111-1111-4111-8111-111111111111');
  v_exec := public.get_executive_overview(v_start, v_end, true);
  v_fin := public.get_finance_intelligence_overview(v_start, v_end, true);
  PERFORM _m5_t08_record(13, 'executive finance block unchanged', (v_exec->'finance') = v_fin);
END $$;

-- 14: get_my_teaching_ops_overview denied without teacher link (reader)
DO $$
DECLARE v_denied boolean := false;
BEGIN
  PERFORM _m5_t08_as_auth('a4444444-4444-4444-8444-444444444444');
  BEGIN
    PERFORM public.get_my_teaching_ops_overview(CURRENT_DATE, CURRENT_DATE);
    v_denied := false;
  EXCEPTION WHEN others THEN
    v_denied := true;
  END;
  PERFORM _m5_t08_record(14, 'non-teacher denied personal teaching overview', v_denied);
END $$;

-- 15: accountant denied executive read unless granted
DO $$
DECLARE v_denied boolean := false;
BEGIN
  PERFORM _m5_t08_as_auth('a7777777-7777-4777-8777-777777777777');
  BEGIN
    PERFORM public.list_executive_exceptions(CURRENT_DATE, CURRENT_DATE, NULL, NULL, NULL, NULL, true);
    v_denied := false;
  EXCEPTION WHEN others THEN
    v_denied := true;
  END;
  PERFORM _m5_t08_record(15, 'accountant denied executive exceptions', v_denied);
END $$;

-- 16: academic ops denied executive exceptions
DO $$
DECLARE v_denied boolean := false;
BEGIN
  PERFORM _m5_t08_as_auth('a8888888-8888-4888-8888-888888888888');
  BEGIN
    PERFORM public.list_executive_exceptions(CURRENT_DATE, CURRENT_DATE, NULL, NULL, NULL, NULL, true);
    v_denied := false;
  EXCEPTION WHEN others THEN
    v_denied := true;
  END;
  PERFORM _m5_t08_record(16, 'academic ops denied executive exceptions', v_denied);
END $$;

-- 17: follow-up history ordered ascending
DO $$
DECLARE v_prev timestamptz; v_at timestamptz; v_ok boolean := true;
  v_key text := 'finance|receivable_overdue|charge|00000000-0000-4000-8000-000000000088';
BEGIN
  PERFORM _m5_t08_as_auth('a1111111-1111-4111-8111-111111111111');
  SET LOCAL ROLE authenticated;
  FOR v_at IN
    SELECT (row->>'created_at')::timestamptz
    FROM public.list_executive_exception_follow_up_history(v_key) row
  LOOP
    IF v_prev IS NOT NULL AND v_at < v_prev THEN
      v_ok := false;
      EXIT;
    END IF;
    v_prev := v_at;
  END LOOP;
  PERFORM _m5_t08_record(17, 'follow-up history chronological', v_ok);
END $$;

-- 18: all tests recorded
DO $$
DECLARE v_total integer; v_fail integer;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE result = 'FAIL')
  INTO v_total, v_fail
  FROM _m5_t08_results;
  IF v_fail > 0 THEN
    RAISE EXCEPTION 'M5-T08 tests failed: % of % failing', v_fail, v_total;
  END IF;
  RAISE NOTICE 'M5-T08 management intelligence hardening: %/% PASS', v_total, v_total;
END $$;

COMMIT;
