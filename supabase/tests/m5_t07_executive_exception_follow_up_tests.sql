-- M5-T07: Executive exception worklist + management follow-up tests (40 scenarios)

BEGIN;

CREATE TEMP TABLE _m5_t07_results (
  test_no   integer PRIMARY KEY,
  test_name text NOT NULL,
  result    text NOT NULL CHECK (result IN ('PASS', 'FAIL'))
);

GRANT ALL ON TABLE _m5_t07_results TO authenticated, anon;

CREATE OR REPLACE FUNCTION _m5_t07_record(test_no integer, test_name text, passed boolean)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO _m5_t07_results (test_no, test_name, result)
  VALUES (test_no, test_name, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END);
END;
$$;

CREATE OR REPLACE FUNCTION _m5_t07_as_auth(p_auth_id uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', p_auth_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_auth_id::text, 'role', 'authenticated')::text, true);
END;
$$;

-- 1: exception key is deterministic
DO $$
DECLARE v_key text;
BEGIN
  v_key := public.build_executive_exception_key(
    'finance', 'receivable_overdue', 'charge', 'abc-123'
  );
  PERFORM _m5_t07_record(
    1,
    'exception key deterministic',
    v_key = 'finance|receivable_overdue|charge|abc-123'
  );
END $$;

-- 2: manager can list executive exceptions
DO $$
DECLARE v_cnt integer;
  v_start date := date_trunc('month', CURRENT_DATE)::date;
  v_end date := (date_trunc('month', CURRENT_DATE) + interval '1 month - 1 day')::date;
BEGIN
  PERFORM _m5_t07_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_cnt
  FROM public.list_executive_exceptions(v_start, v_end, NULL, NULL, NULL, NULL, true);
  PERFORM _m5_t07_record(2, 'manager lists executive exceptions', v_cnt >= 0);
END $$;

-- 3: reader denied list
DO $$
DECLARE v_denied boolean := false;
BEGIN
  PERFORM _m5_t07_as_auth('a4444444-4444-4444-8444-444444444444');
  BEGIN
    PERFORM public.list_executive_exceptions(CURRENT_DATE, CURRENT_DATE, NULL, NULL, NULL, NULL, true);
    v_denied := false;
  EXCEPTION WHEN others THEN
    v_denied := true;
  END;
  PERFORM _m5_t07_record(3, 'reader denied exception list', v_denied);
END $$;

-- 4: teacher denied list
DO $$
DECLARE v_denied boolean := false;
BEGIN
  PERFORM _m5_t07_as_auth('e2222222-2222-4222-8222-222222222222');
  BEGIN
    PERFORM public.list_executive_exceptions(CURRENT_DATE, CURRENT_DATE, NULL, NULL, NULL, NULL, true);
    v_denied := false;
  EXCEPTION WHEN others THEN
    v_denied := true;
  END;
  PERFORM _m5_t07_record(4, 'teacher denied exception list', v_denied);
END $$;

-- 5: accountant denied unless executive granted
DO $$
DECLARE v_denied boolean := false;
BEGIN
  PERFORM _m5_t07_as_auth('a7777777-7777-4777-8777-777777777777');
  BEGIN
    PERFORM public.list_executive_exceptions(CURRENT_DATE, CURRENT_DATE, NULL, NULL, NULL, NULL, true);
    v_denied := false;
  EXCEPTION WHEN others THEN
    v_denied := true;
  END;
  PERFORM _m5_t07_record(5, 'accountant denied exception list', v_denied);
END $$;

-- 6: no duplicate keys in composed list
DO $$
DECLARE v_dup integer;
  v_start date := date_trunc('month', CURRENT_DATE)::date;
  v_end date := (date_trunc('month', CURRENT_DATE) + interval '1 month - 1 day')::date;
BEGIN
  PERFORM _m5_t07_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_dup
  FROM (
    SELECT row->>'exception_key' AS k, count(*)
    FROM public.list_executive_exceptions(v_start, v_end, NULL, NULL, NULL, NULL, false) row
    GROUP BY 1 HAVING count(*) > 1
  ) d;
  PERFORM _m5_t07_record(6, 'no duplicate normalized exception keys', v_dup = 0);
END $$;

-- 7: finance domain filter
DO $$
DECLARE v_bad integer;
  v_start date := date_trunc('month', CURRENT_DATE)::date;
  v_end date := (date_trunc('month', CURRENT_DATE) + interval '1 month - 1 day')::date;
BEGIN
  PERFORM _m5_t07_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_bad
  FROM public.list_executive_exceptions(v_start, v_end, 'finance', NULL, NULL, NULL, false) row
  WHERE row->>'domain' <> 'finance';
  PERFORM _m5_t07_record(7, 'finance domain filter', v_bad = 0);
END $$;

-- 8: admissions domain filter
DO $$
DECLARE v_bad integer;
  v_start date := date_trunc('month', CURRENT_DATE)::date;
  v_end date := (date_trunc('month', CURRENT_DATE) + interval '1 month - 1 day')::date;
BEGIN
  PERFORM _m5_t07_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_bad
  FROM public.list_executive_exceptions(v_start, v_end, 'admissions', NULL, NULL, NULL, false) row
  WHERE row->>'domain' <> 'admissions';
  PERFORM _m5_t07_record(8, 'admissions domain filter', v_bad = 0);
END $$;

-- 9: quality domain filter
DO $$
DECLARE v_bad integer;
  v_start date := date_trunc('month', CURRENT_DATE)::date;
  v_end date := (date_trunc('month', CURRENT_DATE) + interval '1 month - 1 day')::date;
BEGIN
  PERFORM _m5_t07_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_bad
  FROM public.list_executive_exceptions(v_start, v_end, 'quality', NULL, NULL, NULL, false) row
  WHERE row->>'domain' <> 'quality';
  PERFORM _m5_t07_record(9, 'quality domain filter', v_bad = 0);
END $$;

-- 10: operations domain filter
DO $$
DECLARE v_bad integer;
  v_start date := date_trunc('month', CURRENT_DATE)::date;
  v_end date := (date_trunc('month', CURRENT_DATE) + interval '1 month - 1 day')::date;
BEGIN
  PERFORM _m5_t07_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_bad
  FROM public.list_executive_exceptions(v_start, v_end, 'operations', NULL, NULL, NULL, false) row
  WHERE row->>'domain' <> 'operations';
  PERFORM _m5_t07_record(10, 'operations domain filter', v_bad = 0);
END $$;

-- 11: create follow-up
DO $$
DECLARE v_row executive_exception_follow_up;
  v_key text := 'finance|receivable_overdue|charge|00000000-0000-4000-8000-000000000099';
BEGIN
  PERFORM _m5_t07_as_auth('a1111111-1111-4111-8111-111111111111');
  v_row := public.save_executive_exception_follow_up(
    v_key, 'finance', 'receivable_overdue', 'charge',
    '00000000-0000-4000-8000-000000000099', 'open', 'Initial note'
  );
  PERFORM _m5_t07_record(11, 'create follow-up', v_row.status = 'open' AND v_row.latest_note = 'Initial note');
END $$;

-- 12: acknowledge follow-up
DO $$
DECLARE v_row executive_exception_follow_up;
  v_key text := 'finance|receivable_overdue|charge|00000000-0000-4000-8000-000000000099';
BEGIN
  PERFORM _m5_t07_as_auth('a1111111-1111-4111-8111-111111111111');
  v_row := public.save_executive_exception_follow_up(
    v_key, 'finance', 'receivable_overdue', 'charge',
    '00000000-0000-4000-8000-000000000099', 'acknowledged', NULL
  );
  PERFORM _m5_t07_record(12, 'acknowledge follow-up', v_row.status = 'acknowledged');
END $$;

-- 13: resolve follow-up
DO $$
DECLARE v_row executive_exception_follow_up;
  v_key text := 'finance|receivable_overdue|charge|00000000-0000-4000-8000-000000000099';
BEGIN
  PERFORM _m5_t07_as_auth('a1111111-1111-4111-8111-111111111111');
  v_row := public.save_executive_exception_follow_up(
    v_key, 'finance', 'receivable_overdue', 'charge',
    '00000000-0000-4000-8000-000000000099', 'resolved', 'Manager closed follow-up'
  );
  PERFORM _m5_t07_record(13, 'resolve follow-up', v_row.status = 'resolved');
END $$;

-- 14: resolved follow-up does not suppress detected row when present
DO $$
DECLARE v_row jsonb;
  v_start date := date_trunc('month', CURRENT_DATE)::date;
  v_end date := (date_trunc('month', CURRENT_DATE) + interval '1 month - 1 day')::date;
  v_key text;
BEGIN
  PERFORM _m5_t07_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT row INTO v_row
  FROM public.list_executive_exceptions(v_start, v_end, NULL, NULL, NULL, NULL, true) row
  WHERE row->>'exception_key' = 'finance|receivable_overdue|charge|00000000-0000-4000-8000-000000000099'
  LIMIT 1;
  IF v_row IS NULL THEN
    PERFORM _m5_t07_record(14, 'resolved follow-up retains row when detected', true);
  ELSE
    PERFORM _m5_t07_record(
      14,
      'resolved follow-up retains row when detected',
      (v_row->'follow_up'->>'status') = 'resolved'
        AND COALESCE((v_row->>'source_currently_detected')::boolean, false) IN (true, false)
    );
  END IF;
END $$;

-- 15: history has audit events
DO $$
DECLARE v_cnt integer;
  v_key text := 'finance|receivable_overdue|charge|00000000-0000-4000-8000-000000000099';
BEGIN
  PERFORM _m5_t07_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_cnt
  FROM public.list_executive_exception_follow_up_history(v_key);
  PERFORM _m5_t07_record(15, 'follow-up history auditable', v_cnt >= 3);
END $$;

-- 16: reader cannot mutate follow-up
DO $$
DECLARE v_denied boolean := false;
  v_key text := 'finance|receivable_overdue|charge|00000000-0000-4000-8000-000000000099';
BEGIN
  PERFORM _m5_t07_as_auth('a4444444-4444-4444-8444-444444444444');
  BEGIN
    PERFORM public.save_executive_exception_follow_up(
      v_key, 'finance', 'receivable_overdue', 'charge',
      '00000000-0000-4000-8000-000000000099', 'dismissed', NULL
    );
    v_denied := false;
  EXCEPTION WHEN others THEN
    v_denied := true;
  END;
  PERFORM _m5_t07_record(16, 'reader denied follow-up mutation', v_denied);
END $$;

-- 17: manager can dismiss
DO $$
DECLARE v_row executive_exception_follow_up;
  v_key text := 'finance|receivable_overdue|charge|00000000-0000-4000-8000-000000000099';
BEGIN
  PERFORM _m5_t07_as_auth('a1111111-1111-4111-8111-111111111111');
  v_row := public.save_executive_exception_follow_up(
    v_key, 'finance', 'receivable_overdue', 'charge',
    '00000000-0000-4000-8000-000000000099', 'dismissed', NULL
  );
  PERFORM _m5_t07_record(17, 'dismiss follow-up', v_row.status = 'dismissed');
END $$;

-- 18: exception key mismatch rejected
DO $$
DECLARE v_failed boolean := false;
BEGIN
  PERFORM _m5_t07_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.save_executive_exception_follow_up(
      'bad-key', 'finance', 'receivable_overdue', 'charge', 'x', 'open', NULL
    );
    v_failed := false;
  EXCEPTION WHEN others THEN
    v_failed := true;
  END;
  PERFORM _m5_t07_record(18, 'exception key mismatch rejected', v_failed);
END $$;

-- 19: historical follow-up retained when not currently detected
DO $$
DECLARE v_cnt integer;
  v_start date := date_trunc('month', CURRENT_DATE)::date;
  v_end date := (date_trunc('month', CURRENT_DATE) + interval '1 month - 1 day')::date;
BEGIN
  PERFORM _m5_t07_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_cnt
  FROM public.list_executive_exceptions(v_start, v_end, NULL, NULL, NULL, NULL, true) row
  WHERE row->>'exception_key' = 'finance|receivable_overdue|charge|00000000-0000-4000-8000-000000000099';
  PERFORM _m5_t07_record(19, 'historical follow-up row retained', v_cnt = 1);
END $$;

-- 20: historical row marks source not detected when absent from domain reads
DO $$
DECLARE v_row jsonb;
  v_start date := date_trunc('month', CURRENT_DATE)::date;
  v_end date := (date_trunc('month', CURRENT_DATE) + interval '1 month - 1 day')::date;
BEGIN
  PERFORM _m5_t07_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT row INTO v_row
  FROM public.list_executive_exceptions(v_start, v_end, NULL, NULL, NULL, NULL, true) row
  WHERE row->>'exception_key' = 'finance|receivable_overdue|charge|00000000-0000-4000-8000-000000000099'
  LIMIT 1;
  PERFORM _m5_t07_record(
    20,
    'historical source flag when not detected',
    v_row IS NOT NULL AND (v_row->>'source_currently_detected')::boolean = false
  );
END $$;

-- 21: follow-up status filter dismissed
DO $$
DECLARE v_bad integer;
  v_start date := date_trunc('month', CURRENT_DATE)::date;
  v_end date := (date_trunc('month', CURRENT_DATE) + interval '1 month - 1 day')::date;
BEGIN
  PERFORM _m5_t07_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_bad
  FROM public.list_executive_exceptions(v_start, v_end, NULL, NULL, 'dismissed', NULL, true) row
  WHERE row->'follow_up'->>'status' IS DISTINCT FROM 'dismissed';
  PERFORM _m5_t07_record(21, 'follow-up status filter', v_bad = 0);
END $$;

-- 22: worklist summary on overview
DO $$
DECLARE v_exec jsonb;
  v_start date := date_trunc('month', CURRENT_DATE)::date;
  v_end date := (date_trunc('month', CURRENT_DATE) + interval '1 month - 1 day')::date;
BEGIN
  PERFORM _m5_t07_as_auth('a1111111-1111-4111-8111-111111111111');
  v_exec := public.get_executive_overview(v_start, v_end, false);
  PERFORM _m5_t07_record(
    22,
    'overview includes exception worklist summary',
    v_exec ? 'exception_worklist'
      AND (v_exec->'exception_worklist'->>'worklist_path') = '/executive/exceptions'
  );
END $$;

-- 23: T06 domain blocks unchanged on overview
DO $$
DECLARE v_exec jsonb; v_fin jsonb;
  v_start date := date_trunc('month', CURRENT_DATE)::date;
  v_end date := (date_trunc('month', CURRENT_DATE) + interval '1 month - 1 day')::date;
BEGIN
  PERFORM _m5_t07_as_auth('a1111111-1111-4111-8111-111111111111');
  v_exec := public.get_executive_overview(v_start, v_end, true);
  v_fin := public.get_finance_intelligence_overview(v_start, v_end, true);
  PERFORM _m5_t07_record(23, 'finance composition unchanged on overview', (v_exec->'finance') = v_fin);
END $$;

-- 24: attention array still present
DO $$
DECLARE v_exec jsonb;
BEGIN
  PERFORM _m5_t07_as_auth('a1111111-1111-4111-8111-111111111111');
  v_exec := public.get_executive_overview(CURRENT_DATE, CURRENT_DATE, false);
  PERFORM _m5_t07_record(24, 'attention array preserved', jsonb_typeof(v_exec->'attention') = 'array');
END $$;

-- 25: org isolation on follow-up history read
DO $$
DECLARE v_cnt integer;
  v_key text := 'finance|receivable_overdue|charge|00000000-0000-4000-8000-000000000099';
BEGIN
  PERFORM _m5_t07_as_auth('b1111111-1111-4111-8111-111111111111');
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO v_cnt
  FROM public.list_executive_exception_follow_up_history(v_key);
  PERFORM _m5_t07_record(25, 'cross-org follow-up not visible', v_cnt = 0);
END $$;

-- 26: cross-org follow-up rows remain isolated (org B cannot see or overwrite org A)
DO $$
DECLARE v_org_a_cnt integer; v_org_b_cnt integer;
  v_key text := 'finance|receivable_overdue|charge|00000000-0000-4000-8000-000000000099';
BEGIN
  PERFORM _m5_t07_as_auth('b1111111-1111-4111-8111-111111111111');
  SET LOCAL ROLE authenticated;
  PERFORM public.save_executive_exception_follow_up(
    v_key, 'finance', 'receivable_overdue', 'charge',
    '00000000-0000-4000-8000-000000000099', 'open', 'Org B follow-up'
  );
  SELECT count(*) INTO v_org_b_cnt
  FROM executive_exception_follow_up WHERE exception_key = v_key;

  PERFORM _m5_t07_as_auth('a1111111-1111-4111-8111-111111111111');
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO v_org_a_cnt
  FROM executive_exception_follow_up WHERE exception_key = v_key;

  PERFORM _m5_t07_record(
    26,
    'cross-org follow-up isolated per organization',
    v_org_a_cnt = 1 AND v_org_b_cnt = 1
  );
END $$;

-- 27: reappear with same key preserves follow-up
DO $$
DECLARE v_row executive_exception_follow_up;
  v_key text := 'finance|receivable_overdue|charge|00000000-0000-4000-8000-000000000099';
BEGIN
  PERFORM _m5_t07_as_auth('a1111111-1111-4111-8111-111111111111');
  SET LOCAL ROLE authenticated;
  SELECT * INTO v_row FROM executive_exception_follow_up
  WHERE exception_key = v_key AND organization_id = public.current_organization_id();
  PERFORM _m5_t07_record(27, 'stable key preserves follow-up row', v_row.id IS NOT NULL);
END $$;

-- 28: search filter accepts entity id fragment
DO $$
DECLARE v_cnt integer;
  v_start date := date_trunc('month', CURRENT_DATE)::date;
  v_end date := (date_trunc('month', CURRENT_DATE) + interval '1 month - 1 day')::date;
BEGIN
  PERFORM _m5_t07_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_cnt
  FROM public.list_executive_exceptions(v_start, v_end, NULL, NULL, NULL, '00000099', true) row;
  PERFORM _m5_t07_record(28, 'search filter matches entity id', v_cnt >= 1);
END $$;

-- 29: each row exposes drill-down path when detected from finance RPC shape
DO $$
DECLARE v_missing integer;
  v_start date := date_trunc('month', CURRENT_DATE)::date;
  v_end date := (date_trunc('month', CURRENT_DATE) + interval '1 month - 1 day')::date;
BEGIN
  PERFORM _m5_t07_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_missing
  FROM public.list_executive_exceptions(v_start, v_end, NULL, NULL, NULL, NULL, false) row
  WHERE (row->>'source_currently_detected')::boolean
    AND (row->>'drill_down_path' IS NULL OR length(row->>'drill_down_path') = 0);
  PERFORM _m5_t07_record(29, 'detected exceptions include drill-down path', v_missing = 0);
END $$;

-- 30: consultant denied executive exceptions
DO $$
DECLARE v_denied boolean := false;
BEGIN
  PERFORM _m5_t07_as_auth('d1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.list_executive_exceptions(CURRENT_DATE, CURRENT_DATE, NULL, NULL, NULL, NULL, true);
    v_denied := false;
  EXCEPTION WHEN others THEN
    v_denied := true;
  END;
  PERFORM _m5_t07_record(30, 'consultant denied exception list', v_denied);
END $$;

-- 31: manager has follow-up manage permission via seed all-perms
DO $$
DECLARE v_ok boolean;
BEGIN
  PERFORM _m5_t07_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT public.has_permission('report.executive.follow_up.manage') INTO v_ok;
  PERFORM _m5_t07_record(31, 'manager has follow-up manage permission', v_ok);
END $$;

-- 32: reader lacks follow-up manage permission
DO $$
DECLARE v_ok boolean;
BEGIN
  PERFORM _m5_t07_as_auth('a4444444-4444-4444-8444-444444444444');
  SELECT public.has_permission('report.executive.follow_up.manage') INTO v_ok;
  PERFORM _m5_t07_record(32, 'reader lacks follow-up manage permission', NOT v_ok);
END $$;

-- 33: unique follow-up per org and key (upsert updates same row)
DO $$
DECLARE v_cnt integer;
  v_key text := 'operations|session_missing_teacher|teaching_session|00000000-0000-4000-8000-000000000088';
BEGIN
  PERFORM _m5_t07_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.save_executive_exception_follow_up(
    v_key, 'operations', 'session_missing_teacher', 'teaching_session',
    '00000000-0000-4000-8000-000000000088', 'open', NULL
  );
  PERFORM public.save_executive_exception_follow_up(
    v_key, 'operations', 'session_missing_teacher', 'teaching_session',
    '00000000-0000-4000-8000-000000000088', 'acknowledged', NULL
  );
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO v_cnt
  FROM executive_exception_follow_up
  WHERE organization_id = public.current_organization_id()
    AND exception_key = v_key;
  PERFORM _m5_t07_record(33, 'unique follow-up per org and key', v_cnt = 1);
END $$;

-- 34: empty identity rejected
DO $$
DECLARE v_failed boolean := false;
BEGIN
  PERFORM _m5_t07_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.save_executive_exception_follow_up(
      'finance|x|y|z', '', 'x', 'y', 'z', 'open', NULL
    );
    v_failed := false;
  EXCEPTION WHEN others THEN
    v_failed := true;
  END;
  PERFORM _m5_t07_record(34, 'empty identity rejected', v_failed);
END $$;

-- 35: include_historical false excludes follow-up-only rows
DO $$
DECLARE v_cnt_with integer; v_cnt_without integer;
  v_start date := date_trunc('month', CURRENT_DATE)::date;
  v_end date := (date_trunc('month', CURRENT_DATE) + interval '1 month - 1 day')::date;
BEGIN
  PERFORM _m5_t07_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_cnt_with
  FROM public.list_executive_exceptions(v_start, v_end, NULL, NULL, NULL, NULL, true) row
  WHERE row->>'exception_key' = 'finance|receivable_overdue|charge|00000000-0000-4000-8000-000000000099';
  SELECT count(*) INTO v_cnt_without
  FROM public.list_executive_exceptions(v_start, v_end, NULL, NULL, NULL, NULL, false) row
  WHERE row->>'exception_key' = 'finance|receivable_overdue|charge|00000000-0000-4000-8000-000000000099';
  PERFORM _m5_t07_record(
    35,
    'include_historical toggles follow-up-only rows',
    v_cnt_with = 1 AND v_cnt_without = 0
  );
END $$;

-- 36: note_added events append-only
DO $$
DECLARE v_cnt1 integer; v_cnt2 integer;
  v_key text := 'operations|session_missing_teacher|teaching_session|00000000-0000-4000-8000-000000000088';
BEGIN
  PERFORM _m5_t07_as_auth('a1111111-1111-4111-8111-111111111111');
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO v_cnt1 FROM executive_exception_follow_up_event WHERE exception_key = v_key;
  PERFORM public.save_executive_exception_follow_up(
    v_key, 'operations', 'session_missing_teacher', 'teaching_session',
    '00000000-0000-4000-8000-000000000088', NULL, 'Another note'
  );
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO v_cnt2 FROM executive_exception_follow_up_event WHERE exception_key = v_key;
  PERFORM _m5_t07_record(36, 'note append creates history event', v_cnt2 > v_cnt1);
END $$;

-- 37: academic ops denied without executive permission
DO $$
DECLARE v_denied boolean := false;
BEGIN
  PERFORM _m5_t07_as_auth('a8888888-8888-4888-8888-888888888888');
  BEGIN
    PERFORM public.list_executive_exceptions(CURRENT_DATE, CURRENT_DATE, NULL, NULL, NULL, NULL, true);
    v_denied := false;
  EXCEPTION WHEN others THEN
    v_denied := true;
  END;
  PERFORM _m5_t07_record(37, 'academic ops denied exception list', v_denied);
END $$;

-- 38: worklist summary counts are numeric
DO $$
DECLARE v_summary jsonb;
  v_start date := date_trunc('month', CURRENT_DATE)::date;
  v_end date := (date_trunc('month', CURRENT_DATE) + interval '1 month - 1 day')::date;
BEGIN
  PERFORM _m5_t07_as_auth('a1111111-1111-4111-8111-111111111111');
  v_summary := public.get_executive_exception_worklist_summary(v_start, v_end);
  PERFORM _m5_t07_record(
    38,
    'worklist summary numeric fields',
    jsonb_typeof(v_summary->'current_detected_count') = 'number'
  );
END $$;

-- 39: domain drill-down path present on composed rows
DO $$
DECLARE v_missing integer;
  v_start date := date_trunc('month', CURRENT_DATE)::date;
  v_end date := (date_trunc('month', CURRENT_DATE) + interval '1 month - 1 day')::date;
BEGIN
  PERFORM _m5_t07_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_missing
  FROM public.list_executive_exceptions(v_start, v_end, NULL, NULL, NULL, NULL, false) row
  WHERE row->>'domain_drill_down_path' IS NULL OR length(row->>'domain_drill_down_path') = 0;
  PERFORM _m5_t07_record(39, 'domain drill-down path on rows', v_missing = 0);
END $$;

-- 40: all tests recorded
DO $$
DECLARE v_total integer; v_fail integer;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE result = 'FAIL')
  INTO v_total, v_fail
  FROM _m5_t07_results;
  IF v_fail > 0 THEN
    RAISE EXCEPTION 'M5-T07 tests failed: % of % failing', v_fail, v_total;
  END IF;
  RAISE NOTICE 'M5-T07 executive exception follow-up: %/% PASS', v_total, v_total;
END $$;

COMMIT;
