-- M5-T06: Executive cross-domain overview tests (32 scenarios)

BEGIN;

CREATE TEMP TABLE _m5_t06_results (
  test_no   integer PRIMARY KEY,
  test_name text NOT NULL,
  result    text NOT NULL CHECK (result IN ('PASS', 'FAIL'))
);

GRANT ALL ON TABLE _m5_t06_results TO authenticated, anon;

CREATE OR REPLACE FUNCTION _m5_t06_record(test_no integer, test_name text, passed boolean)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO _m5_t06_results (test_no, test_name, result)
  VALUES (test_no, test_name, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END);
END;
$$;

CREATE OR REPLACE FUNCTION _m5_t06_as_auth(p_auth_id uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', p_auth_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_auth_id::text, 'role', 'authenticated')::text, true);
END;
$$;

-- 1: executive manager can load overview
DO $$
DECLARE v jsonb;
BEGIN
  PERFORM _m5_t06_as_auth('a1111111-1111-4111-8111-111111111111');
  v := public.get_executive_overview(
    date_trunc('month', CURRENT_DATE)::date,
    (date_trunc('month', CURRENT_DATE) + interval '1 month - 1 day')::date,
    true
  );
  PERFORM _m5_t06_record(1, 'executive manager loads overview', v ? 'finance' AND v ? 'operations');
END $$;

-- 2: reader denied overview RPC
DO $$
DECLARE v_denied boolean := false;
BEGIN
  PERFORM _m5_t06_as_auth('a4444444-4444-4444-8444-444444444444');
  BEGIN
    PERFORM public.get_executive_overview(CURRENT_DATE, CURRENT_DATE, false);
    v_denied := false;
  EXCEPTION WHEN others THEN
    v_denied := true;
  END;
  PERFORM _m5_t06_record(2, 'reader denied get_executive_overview', v_denied);
END $$;

-- 3: accountant denied (no executive permission)
DO $$
DECLARE v_denied boolean := false;
BEGIN
  PERFORM _m5_t06_as_auth('a7777777-7777-4777-8777-777777777777');
  BEGIN
    PERFORM public.get_executive_overview(CURRENT_DATE, CURRENT_DATE, false);
    v_denied := false;
  EXCEPTION WHEN others THEN
    v_denied := true;
  END;
  PERFORM _m5_t06_record(3, 'accountant denied executive overview', v_denied);
END $$;

-- 4: teacher denied
DO $$
DECLARE v_denied boolean := false;
BEGIN
  PERFORM _m5_t06_as_auth('e2222222-2222-4222-8222-222222222222');
  BEGIN
    PERFORM public.get_executive_overview(CURRENT_DATE, CURRENT_DATE, false);
    v_denied := false;
  EXCEPTION WHEN others THEN
    v_denied := true;
  END;
  PERFORM _m5_t06_record(4, 'teacher denied executive overview', v_denied);
END $$;

-- 5: list_executive_attention_items requires executive permission
DO $$
DECLARE v_denied boolean := false;
BEGIN
  PERFORM _m5_t06_as_auth('a4444444-4444-4444-8444-444444444444');
  BEGIN
    PERFORM public.list_executive_attention_items(CURRENT_DATE, CURRENT_DATE, 1);
    v_denied := false;
  EXCEPTION WHEN others THEN
    v_denied := true;
  END;
  PERFORM _m5_t06_record(5, 'reader denied attention list', v_denied);
END $$;

-- 6: finance block equals standalone overview
DO $$
DECLARE v_exec jsonb; v_fin jsonb;
  v_start date := date_trunc('month', CURRENT_DATE)::date;
  v_end date := (date_trunc('month', CURRENT_DATE) + interval '1 month - 1 day')::date;
BEGIN
  PERFORM _m5_t06_as_auth('a1111111-1111-4111-8111-111111111111');
  v_exec := public.get_executive_overview(v_start, v_end, true);
  v_fin := public.get_finance_intelligence_overview(v_start, v_end, true);
  PERFORM _m5_t06_record(6, 'finance composition equals domain RPC', (v_exec->'finance') = v_fin);
END $$;

-- 7: admissions block equals standalone
DO $$
DECLARE v_exec jsonb; v_crm jsonb;
  v_start date := date_trunc('month', CURRENT_DATE)::date;
  v_end date := (date_trunc('month', CURRENT_DATE) + interval '1 month - 1 day')::date;
BEGIN
  PERFORM _m5_t06_as_auth('a1111111-1111-4111-8111-111111111111');
  v_exec := public.get_executive_overview(v_start, v_end, true);
  v_crm := public.get_crm_admissions_overview(v_start, v_end, true);
  PERFORM _m5_t06_record(7, 'admissions composition equals domain RPC', (v_exec->'admissions') = v_crm);
END $$;

-- 8: quality block equals standalone
DO $$
DECLARE v_exec jsonb; v_qual jsonb;
  v_start date := date_trunc('month', CURRENT_DATE)::date;
  v_end date := (date_trunc('month', CURRENT_DATE) + interval '1 month - 1 day')::date;
BEGIN
  PERFORM _m5_t06_as_auth('a1111111-1111-4111-8111-111111111111');
  v_exec := public.get_executive_overview(v_start, v_end, true);
  v_qual := public.get_academic_quality_overview(v_start, v_end, true);
  PERFORM _m5_t06_record(8, 'quality composition equals domain RPC', (v_exec->'quality') = v_qual);
END $$;

-- 9: operations block equals standalone
DO $$
DECLARE v_exec jsonb; v_ops jsonb;
  v_start date := date_trunc('month', CURRENT_DATE)::date;
  v_end date := (date_trunc('month', CURRENT_DATE) + interval '1 month - 1 day')::date;
BEGIN
  PERFORM _m5_t06_as_auth('a1111111-1111-4111-8111-111111111111');
  v_exec := public.get_executive_overview(v_start, v_end, true);
  v_ops := public.get_teaching_ops_intelligence_overview(v_start, v_end, true);
  PERFORM _m5_t06_record(9, 'operations composition equals domain RPC', (v_exec->'operations') = v_ops);
END $$;

-- 10: cash and recognized revenue keys distinct
DO $$
DECLARE v_exec jsonb;
  v_start date := date_trunc('month', CURRENT_DATE)::date;
  v_end date := (date_trunc('month', CURRENT_DATE) + interval '1 month - 1 day')::date;
BEGIN
  PERFORM _m5_t06_as_auth('a1111111-1111-4111-8111-111111111111');
  v_exec := public.get_executive_overview(v_start, v_end, false);
  PERFORM _m5_t06_record(
    10,
    'finance cash and revenue distinct fields',
    (v_exec->'finance'->'cash_collected') IS NOT NULL
      AND (v_exec->'finance'->'recognized_revenue') IS NOT NULL
  );
END $$;

-- 11: comparison period present when compare true
DO $$
DECLARE v_exec jsonb;
  v_start date := date_trunc('month', CURRENT_DATE)::date;
  v_end date := (date_trunc('month', CURRENT_DATE) + interval '1 month - 1 day')::date;
BEGIN
  PERFORM _m5_t06_as_auth('a1111111-1111-4111-8111-111111111111');
  v_exec := public.get_executive_overview(v_start, v_end, true);
  PERFORM _m5_t06_record(
    11,
    'comparison period when compare true',
    v_exec->'comparison_period' IS NOT NULL
      AND v_exec->'finance'->'comparison_period' IS NOT NULL
  );
END $$;

-- 12: comparison null when compare false
DO $$
DECLARE v_exec jsonb;
  v_start date := date_trunc('month', CURRENT_DATE)::date;
  v_end date := (date_trunc('month', CURRENT_DATE) + interval '1 month - 1 day')::date;
BEGIN
  PERFORM _m5_t06_as_auth('a1111111-1111-4111-8111-111111111111');
  v_exec := public.get_executive_overview(v_start, v_end, false);
  PERFORM _m5_t06_record(
    12,
    'comparison null when compare false',
    v_exec->'comparison_period' IS NULL
      OR v_exec->'comparison_period' = 'null'::jsonb
      OR (v_exec->'finance'->'cash_collected'->>'change') IS NULL
  );
END $$;

-- 13: period bounds match resolve_reporting_period
DO $$
DECLARE v_exec jsonb; v_bounds reporting_period_bounds;
  v_start date := date_trunc('month', CURRENT_DATE)::date;
  v_end date := (date_trunc('month', CURRENT_DATE) + interval '1 month - 1 day')::date;
BEGIN
  PERFORM _m5_t06_as_auth('a1111111-1111-4111-8111-111111111111');
  v_exec := public.get_executive_overview(v_start, v_end, false);
  v_bounds := public.resolve_reporting_period(v_start, v_end);
  PERFORM _m5_t06_record(
    13,
    'period timezone boundaries',
    (v_exec->'period'->>'start_date')::date = v_bounds.start_date
      AND (v_exec->'period'->>'end_date')::date = v_bounds.end_date
      AND v_exec->'period'->>'timezone' = v_bounds.timezone
  );
END $$;

-- 14: attention array is json array
DO $$
DECLARE v_exec jsonb;
BEGIN
  PERFORM _m5_t06_as_auth('a1111111-1111-4111-8111-111111111111');
  v_exec := public.get_executive_overview(CURRENT_DATE, CURRENT_DATE, false);
  PERFORM _m5_t06_record(14, 'attention is json array', jsonb_typeof(v_exec->'attention') = 'array');
END $$;

-- 15: attention items tag domain when present
DO $$
DECLARE v_item jsonb;
BEGIN
  PERFORM _m5_t06_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT item INTO v_item
  FROM public.list_executive_attention_items(CURRENT_DATE, CURRENT_DATE, 1) item
  LIMIT 1;
  PERFORM _m5_t06_record(
    15,
    'attention item domain tag when any',
    v_item IS NULL OR (v_item ? 'domain' AND v_item ? 'domain_drill_down_path')
  );
END $$;

-- 16: CRM cohort conversion fields present
DO $$
DECLARE v_exec jsonb;
  v_start date := date_trunc('month', CURRENT_DATE)::date;
  v_end date := (date_trunc('month', CURRENT_DATE) + interval '1 month - 1 day')::date;
BEGIN
  PERFORM _m5_t06_as_auth('a1111111-1111-4111-8111-111111111111');
  v_exec := public.get_executive_overview(v_start, v_end, false);
  PERFORM _m5_t06_record(
    16,
    'CRM cohort conversion semantics fields',
    v_exec->'admissions'->'conversions' ? 'cohort_conversion_rate'
      AND v_exec->'admissions'->'conversions' ? 'conversions_in_period'
  );
END $$;

-- 17: quality uses teaching_delivery delivered sessions
DO $$
DECLARE v_exec jsonb; v_qual jsonb;
  v_start date := date_trunc('month', CURRENT_DATE)::date;
  v_end date := (date_trunc('month', CURRENT_DATE) + interval '1 month - 1 day')::date;
BEGIN
  PERFORM _m5_t06_as_auth('a1111111-1111-4111-8111-111111111111');
  v_exec := public.get_executive_overview(v_start, v_end, false);
  v_qual := public.get_academic_quality_overview(v_start, v_end, false);
  PERFORM _m5_t06_record(
    17,
    'quality delivered sessions match domain',
    v_exec->'quality'->'teaching_delivery'->>'delivered_sessions'
      = v_qual->'teaching_delivery'->>'delivered_sessions'
  );
END $$;

-- 18: operations delivered = completed semantics field
DO $$
DECLARE v_exec jsonb;
  v_start date := date_trunc('month', CURRENT_DATE)::date;
  v_end date := (date_trunc('month', CURRENT_DATE) + interval '1 month - 1 day')::date;
BEGIN
  PERFORM _m5_t06_as_auth('a1111111-1111-4111-8111-111111111111');
  v_exec := public.get_executive_overview(v_start, v_end, false);
  PERFORM _m5_t06_record(
    18,
    'operations delivered_sessions field present',
    v_exec->'operations'->'sessionMetrics'->'current' ? 'delivered_sessions'
      AND v_exec->'operations'->'sessionMetrics'->'current' ? 'projected_occurrences'
  );
END $$;

-- 19: composition rule present
DO $$
DECLARE v_exec jsonb;
BEGIN
  PERFORM _m5_t06_as_auth('a1111111-1111-4111-8111-111111111111');
  v_exec := public.get_executive_overview(CURRENT_DATE, CURRENT_DATE, false);
  PERFORM _m5_t06_record(
    19,
    'composition rule documented',
    coalesce(v_exec->>'composition_rule', '') <> ''
  );
END $$;

-- 20: org B executive sees org B period org id
DO $$
DECLARE v_exec jsonb; v_org uuid;
BEGIN
  PERFORM _m5_t06_as_auth('b1111111-1111-4111-8111-111111111111');
  v_exec := public.get_executive_overview(CURRENT_DATE, CURRENT_DATE, false);
  v_org := (v_exec->'period'->>'organization_id')::uuid;
  PERFORM _m5_t06_record(
    20,
    'organization isolation org B',
    v_org = 'b0000000-0000-4000-8000-000000000001'
  );
END $$;

-- 21: org A vs org B finance cash differs or both zero (isolation smoke)
DO $$
DECLARE v_a jsonb; v_b jsonb;
  v_start date := date_trunc('month', CURRENT_DATE)::date;
  v_end date := (date_trunc('month', CURRENT_DATE) + interval '1 month - 1 day')::date;
BEGIN
  PERFORM _m5_t06_as_auth('a1111111-1111-4111-8111-111111111111');
  v_a := public.get_executive_overview(v_start, v_end, false);
  PERFORM _m5_t06_as_auth('b1111111-1111-4111-8111-111111111111');
  v_b := public.get_executive_overview(v_start, v_end, false);
  PERFORM _m5_t06_record(
    21,
    'cross-org overview isolation smoke',
    (v_a->'period'->>'organization_id') <> (v_b->'period'->>'organization_id')
  );
END $$;

-- 22: get_executive_reporting_access still works
DO $$
DECLARE v jsonb;
BEGIN
  PERFORM _m5_t06_as_auth('a1111111-1111-4111-8111-111111111111');
  v := public.get_executive_reporting_access();
  PERFORM _m5_t06_record(22, 'legacy executive access RPC intact', (v->>'executive_access')::boolean);
END $$;

-- 23: attention limit per domain respected
DO $$
DECLARE v_cnt integer;
BEGIN
  PERFORM _m5_t06_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_cnt
  FROM public.list_executive_attention_items(CURRENT_DATE, CURRENT_DATE, 2);
  PERFORM _m5_t06_record(23, 'attention limit per domain', v_cnt <= 8);
END $$;

-- 24: operations previous metrics when compare
DO $$
DECLARE v_exec jsonb;
  v_start date := date_trunc('month', CURRENT_DATE)::date;
  v_end date := (date_trunc('month', CURRENT_DATE) + interval '1 month - 1 day')::date;
BEGIN
  PERFORM _m5_t06_as_auth('a1111111-1111-4111-8111-111111111111');
  v_exec := public.get_executive_overview(v_start, v_end, true);
  PERFORM _m5_t06_record(
    24,
    'operations comparison previous block',
    v_exec->'operations'->'sessionMetrics' ? 'previous'
  );
END $$;

-- 25: finance receivables point-in-time block
DO $$
DECLARE v_exec jsonb;
BEGIN
  PERFORM _m5_t06_as_auth('a1111111-1111-4111-8111-111111111111');
  v_exec := public.get_executive_overview(CURRENT_DATE, CURRENT_DATE, false);
  PERFORM _m5_t06_record(
    25,
    'finance receivables block present',
    v_exec->'finance'->'receivables' ? 'total_outstanding'
  );
END $$;

-- 26: quality attendance comparison rate_change key when compare
DO $$
DECLARE v_exec jsonb;
  v_start date := date_trunc('month', CURRENT_DATE)::date;
  v_end date := (date_trunc('month', CURRENT_DATE) + interval '1 month - 1 day')::date;
BEGIN
  PERFORM _m5_t06_as_auth('a1111111-1111-4111-8111-111111111111');
  v_exec := public.get_executive_overview(v_start, v_end, true);
  PERFORM _m5_t06_record(
    26,
    'quality attendance comparison block',
    v_exec->'quality'->'attendance' ? 'rate_change'
  );
END $$;

-- 27: admissions lead intake metric type event-based
DO $$
DECLARE v_exec jsonb;
  v_start date := date_trunc('month', CURRENT_DATE)::date;
  v_end date := (date_trunc('month', CURRENT_DATE) + interval '1 month - 1 day')::date;
BEGIN
  PERFORM _m5_t06_as_auth('a1111111-1111-4111-8111-111111111111');
  v_exec := public.get_executive_overview(v_start, v_end, false);
  PERFORM _m5_t06_record(
    27,
    'CRM lead intake event semantics',
    v_exec->'admissions'->'leadIntake' ? 'leads_created'
  );
END $$;

-- 28: operations change metrics reschedule events
DO $$
DECLARE v_exec jsonb;
  v_start date := date_trunc('month', CURRENT_DATE)::date;
  v_end date := (date_trunc('month', CURRENT_DATE) + interval '1 month - 1 day')::date;
BEGIN
  PERFORM _m5_t06_as_auth('a1111111-1111-4111-8111-111111111111');
  v_exec := public.get_executive_overview(v_start, v_end, false);
  PERFORM _m5_t06_record(
    28,
    'operations change metrics present',
    v_exec->'operations'->'changeMetrics'->'current'->'reschedule' ? 'event_count'
  );
END $$;

-- 29: zero-limit attention returns empty set
DO $$
DECLARE v_cnt integer;
BEGIN
  PERFORM _m5_t06_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_cnt
  FROM public.list_executive_attention_items(CURRENT_DATE, CURRENT_DATE, 0);
  PERFORM _m5_t06_record(29, 'zero attention limit empty', v_cnt = 0);
END $$;

-- 30: non-executive staff denied (org A staff without executive)
DO $$
DECLARE v_denied boolean := false;
BEGIN
  PERFORM _m5_t06_as_auth('a6666666-6666-4666-8666-666666666666');
  BEGIN
    PERFORM public.get_executive_overview(CURRENT_DATE, CURRENT_DATE, false);
    v_denied := false;
  EXCEPTION WHEN others THEN
    v_denied := true;
  END;
  PERFORM _m5_t06_record(30, 'non-executive manager denied', v_denied);
END $$;

-- 31: executive overview org id matches current org
DO $$
DECLARE v_exec jsonb; v_org uuid;
BEGIN
  PERFORM _m5_t06_as_auth('a1111111-1111-4111-8111-111111111111');
  v_exec := public.get_executive_overview(CURRENT_DATE, CURRENT_DATE, false);
  v_org := public.current_organization_id();
  PERFORM _m5_t06_record(
    31,
    'period organization matches session org',
    (v_exec->'period'->>'organization_id')::uuid = v_org
  );
END $$;

-- 32: embedded attention matches list RPC count cap
DO $$
DECLARE v_exec jsonb; v_cnt integer;
BEGIN
  PERFORM _m5_t06_as_auth('a1111111-1111-4111-8111-111111111111');
  v_exec := public.get_executive_overview(CURRENT_DATE, CURRENT_DATE, false);
  SELECT count(*) INTO v_cnt
  FROM public.list_executive_attention_items(CURRENT_DATE, CURRENT_DATE, 5);
  PERFORM _m5_t06_record(
    32,
    'embedded attention count matches list cap',
    jsonb_array_length(v_exec->'attention') = v_cnt
  );
END $$;

DO $$
DECLARE v_fail integer; v_total integer; r record;
BEGIN
  SELECT count(*) FILTER (WHERE result = 'FAIL'), count(*) INTO v_fail, v_total FROM _m5_t06_results;
  IF v_fail > 0 THEN
    FOR r IN SELECT test_no, test_name FROM _m5_t06_results WHERE result = 'FAIL' LOOP
      RAISE NOTICE 'FAILED: % - %', r.test_no, r.test_name;
    END LOOP;
    RAISE EXCEPTION 'M5-T06 executive overview: %/% FAIL (% failed)',
      v_total - v_fail, v_total, v_fail;
  END IF;
  RAISE NOTICE 'M5-T06 executive overview: %/% PASS (0 FAIL)', v_total, v_total;
END $$;

COMMIT;
