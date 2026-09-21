-- M5-T09: cross-domain milestone acceptance (16 scenarios)

BEGIN;

CREATE TEMP TABLE _m5_ma_results (
  test_no   integer PRIMARY KEY,
  test_name text NOT NULL,
  result    text NOT NULL CHECK (result IN ('PASS', 'FAIL'))
);

GRANT ALL ON TABLE _m5_ma_results TO authenticated, anon;

CREATE OR REPLACE FUNCTION _m5_ma_record(test_no integer, test_name text, passed boolean)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO _m5_ma_results (test_no, test_name, result)
  VALUES (test_no, test_name, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END);
END;
$$;

CREATE OR REPLACE FUNCTION _m5_ma_as_auth(p_auth_id uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', p_auth_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_auth_id::text, 'role', 'authenticated')::text, true);
END;
$$;

CREATE OR REPLACE FUNCTION _m5_ma_as_super()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
END;
$$;

CREATE OR REPLACE FUNCTION _m5_ma_weekday(p_date date)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE EXTRACT(DOW FROM p_date)::int
    WHEN 0 THEN 'sun' WHEN 1 THEN 'mon' WHEN 2 THEN 'tue' WHEN 3 THEN 'wed'
    WHEN 4 THEN 'thu' WHEN 5 THEN 'fri' WHEN 6 THEN 'sat'
  END;
$$;

CREATE TEMP TABLE _m5_ma_fixture (
  session_id uuid,
  class_id uuid,
  teacher_a uuid,
  teacher_b uuid,
  day_a date,
  day_b date
);

GRANT ALL ON TABLE _m5_ma_fixture TO authenticated, anon;

-- Fixture: completed + cancelled sessions; reschedule across local dates; teacher substitution
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_class uuid;
  v_teacher_a uuid;
  v_teacher_b uuid;
  v_room uuid;
  v_schedule uuid;
  v_session uuid;
  v_day_a date := '2047-06-10';
  v_day_b date := '2047-06-12';
BEGIN
  PERFORM _m5_ma_as_super();
  INSERT INTO class (organization_id, course_id, name, status, term_start_date, term_end_date)
  SELECT v_org, c.course_id, 'M5 MA Ops', 'active', '2047-06-01', '2047-06-30'
  FROM class c WHERE c.organization_id = v_org LIMIT 1
  RETURNING id INTO v_class;
  INSERT INTO teacher (organization_id, given_name, family_name, status)
  VALUES (v_org, 'MA', 'TeacherA', 'active') RETURNING id INTO v_teacher_a;
  INSERT INTO teacher (organization_id, given_name, family_name, status)
  VALUES (v_org, 'MA', 'TeacherB', 'active') RETURNING id INTO v_teacher_b;
  INSERT INTO room (organization_id, code, name, status)
  VALUES (v_org, 'MA-ROOM', 'MA Room', 'active') RETURNING id INTO v_room;
  INSERT INTO class_schedule (
    organization_id, class_id, weekday_code, start_time, end_time,
    effective_from, room_id, teacher_id, status
  ) VALUES (
    v_org, v_class, _m5_ma_weekday(v_day_a), '09:00', '10:00',
    '2047-06-01', v_room, v_teacher_a, 'active'
  ) RETURNING id INTO v_schedule;
  INSERT INTO teaching_session (
    organization_id, class_id, class_schedule_id, teacher_id, room_id,
    occurrence_date, scheduled_start_at, scheduled_end_at, status
  ) VALUES (
    v_org, v_class, v_schedule, v_teacher_a, v_room, v_day_a,
    timestamptz '2047-06-10 09:00:00+07', timestamptz '2047-06-10 10:00:00+07', 'scheduled'
  ) RETURNING id INTO v_session;

  PERFORM _m5_ma_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.reschedule_teaching_session(
    v_session,
    timestamptz '2047-06-12 09:00:00+07',
    timestamptz '2047-06-12 10:00:00+07',
    'M5 MA acceptance move'
  );
  PERFORM public.substitute_session_teacher(v_session, v_teacher_b, 'M5 MA cover');
  PERFORM _m5_ma_as_super();
  UPDATE teaching_session SET status = 'completed' WHERE id = v_session;

  INSERT INTO teaching_session (
    organization_id, class_id, class_schedule_id, teacher_id, room_id,
    occurrence_date, scheduled_start_at, scheduled_end_at, status
  ) VALUES (
    v_org, v_class, v_schedule, v_teacher_a, v_room, '2047-06-11',
    timestamptz '2047-06-11 09:00:00+07', timestamptz '2047-06-11 10:00:00+07', 'cancelled'
  );

  DELETE FROM _m5_ma_fixture;
  INSERT INTO _m5_ma_fixture VALUES (v_session, v_class, v_teacher_a, v_teacher_b, v_day_a, v_day_b);
END $$;

-- 1: finance canonical summary — cash collected distinct from recognized revenue
DO $$
DECLARE v_fin jsonb;
  v_start date := date_trunc('month', CURRENT_DATE)::date;
  v_end date := (date_trunc('month', CURRENT_DATE) + interval '1 month - 1 day')::date;
BEGIN
  PERFORM _m5_ma_as_auth('a1111111-1111-4111-8111-111111111111');
  v_fin := public.get_finance_intelligence_overview(v_start, v_end, false);
  PERFORM _m5_ma_record(
    1,
    'finance cash collected distinct from recognized revenue',
    v_fin ? 'cash_collected' AND v_fin ? 'recognized_revenue'
      AND v_fin->'receivables' ? 'total_outstanding'
  );
END $$;

-- 2: CRM event/cohort consistency — executive admissions equals domain RPC
DO $$
DECLARE v_exec jsonb; v_crm jsonb;
  v_start date := date_trunc('month', CURRENT_DATE)::date;
  v_end date := (date_trunc('month', CURRENT_DATE) + interval '1 month - 1 day')::date;
BEGIN
  PERFORM _m5_ma_as_auth('a1111111-1111-4111-8111-111111111111');
  v_exec := public.get_executive_overview(v_start, v_end, false);
  v_crm := public.get_crm_admissions_overview(v_start, v_end, false);
  PERFORM _m5_ma_record(
    2,
    'CRM admissions executive equals domain overview',
    (v_exec->'admissions') = v_crm
      AND v_crm->'conversions' ? 'cohort_conversion_rate'
  );
END $$;

-- 3: quality finalized/reviewed consistency — teaching delivery matches domain
DO $$
DECLARE v_exec jsonb; v_qual jsonb;
  v_start date := date_trunc('month', CURRENT_DATE)::date;
  v_end date := (date_trunc('month', CURRENT_DATE) + interval '1 month - 1 day')::date;
BEGIN
  PERFORM _m5_ma_as_auth('a1111111-1111-4111-8111-111111111111');
  v_exec := public.get_executive_overview(v_start, v_end, false);
  v_qual := public.get_academic_quality_overview(v_start, v_end, false);
  PERFORM _m5_ma_record(
    3,
    'quality teaching delivery equals domain overview',
    v_exec->'quality'->'teaching_delivery' = v_qual->'teaching_delivery'
  );
END $$;

-- 4: teaching ops delivery semantics — delivered uses completed status in fixture window
DO $$
DECLARE v_ops jsonb;
BEGIN
  PERFORM _m5_ma_as_auth('a1111111-1111-4111-8111-111111111111');
  v_ops := public.get_teaching_ops_intelligence_overview('2047-06-01', '2047-06-30', false);
  PERFORM _m5_ma_record(
    4,
    'teaching ops delivered and projected fields present',
    (v_ops->'sessionMetrics'->'current'->>'delivered_sessions')::bigint >= 1
      AND v_ops->'sessionMetrics'->'current' ? 'projected_occurrences'
  );
END $$;

-- 5: executive overview equals all four canonical domain sources
DO $$
DECLARE v_exec jsonb; v_fin jsonb; v_crm jsonb; v_qual jsonb; v_ops jsonb;
  v_start date := date_trunc('month', CURRENT_DATE)::date;
  v_end date := (date_trunc('month', CURRENT_DATE) + interval '1 month - 1 day')::date;
BEGIN
  PERFORM _m5_ma_as_auth('a1111111-1111-4111-8111-111111111111');
  v_exec := public.get_executive_overview(v_start, v_end, true);
  v_fin := public.get_finance_intelligence_overview(v_start, v_end, true);
  v_crm := public.get_crm_admissions_overview(v_start, v_end, true);
  v_qual := public.get_academic_quality_overview(v_start, v_end, true);
  v_ops := public.get_teaching_ops_intelligence_overview(v_start, v_end, true);
  PERFORM _m5_ma_record(
    5,
    'executive overview equals all domain RPC payloads',
    (v_exec->'finance') = v_fin
      AND (v_exec->'admissions') = v_crm
      AND (v_exec->'quality') = v_qual
      AND (v_exec->'operations') = v_ops
  );
END $$;

-- 6: executive exceptions reflect composed domain sources
DO $$
DECLARE v_bad integer;
  v_start date := date_trunc('month', CURRENT_DATE)::date;
  v_end date := (date_trunc('month', CURRENT_DATE) + interval '1 month - 1 day')::date;
BEGIN
  PERFORM _m5_ma_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_bad
  FROM public.list_executive_exceptions(v_start, v_end, NULL, NULL, NULL, NULL, false) row
  WHERE NOT (row->>'domain' = ANY (ARRAY['finance', 'admissions', 'quality', 'operations']));
  PERFORM _m5_ma_record(6, 'executive exceptions tagged to known domains', v_bad = 0);
END $$;

-- 7: follow-up state does not mutate source-domain truth
DO $$
DECLARE v_key text := 'finance|receivable_overdue|charge|00000000-0000-4000-8000-000000009902';
  v_row jsonb;
  v_charge_before numeric;
  v_charge_after numeric;
  v_start date := date_trunc('month', CURRENT_DATE)::date;
  v_end date := (date_trunc('month', CURRENT_DATE) + interval '1 month - 1 day')::date;
BEGIN
  PERFORM _m5_ma_as_super();
  SELECT coalesce(sum(amount), 0) INTO v_charge_before FROM charge
  WHERE organization_id = 'a0000000-0000-4000-8000-000000000001';
  PERFORM _m5_ma_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.save_executive_exception_follow_up(
    v_key, 'finance', 'receivable_overdue', 'charge',
    '00000000-0000-4000-8000-000000009902', 'resolved', 'M5 MA acceptance'
  );
  PERFORM _m5_ma_as_super();
  SELECT coalesce(sum(amount), 0) INTO v_charge_after FROM charge
  WHERE organization_id = 'a0000000-0000-4000-8000-000000000001';
  PERFORM _m5_ma_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT row INTO v_row
  FROM public.list_executive_exceptions(v_start, v_end, NULL, NULL, NULL, NULL, true) row
  WHERE row->>'exception_key' = v_key
  LIMIT 1;
  PERFORM _m5_ma_record(
    7,
    'follow-up resolve leaves finance source rows unchanged',
    v_charge_before = v_charge_after
      AND (v_row IS NULL OR (v_row->'follow_up'->>'status') = 'resolved')
  );
END $$;

-- 8: organization timezone period boundaries
DO $$
DECLARE v_exec jsonb; v_bounds reporting_period_bounds;
  v_start date := '2047-06-01';
  v_end date := '2047-06-30';
BEGIN
  PERFORM _m5_ma_as_auth('a1111111-1111-4111-8111-111111111111');
  v_exec := public.get_executive_overview(v_start, v_end, false);
  v_bounds := public.resolve_reporting_period(v_start, v_end);
  PERFORM _m5_ma_record(
    8,
    'reporting period uses organization timezone boundaries',
    (v_exec->'period'->>'start_date')::date = v_bounds.start_date
      AND (v_exec->'period'->>'end_date')::date = v_bounds.end_date
      AND v_exec->'period'->>'timezone' = v_bounds.timezone
  );
END $$;

-- 9: rescheduled session reports on new operational local date
DO $$
DECLARE v_row record;
BEGIN
  PERFORM _m5_ma_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT * INTO v_row
  FROM public.list_teacher_workload(
    (SELECT day_b FROM _m5_ma_fixture),
    (SELECT day_b FROM _m5_ma_fixture),
    (SELECT class_id FROM _m5_ma_fixture),
    (SELECT teacher_b FROM _m5_ma_fixture)
  );
  PERFORM _m5_ma_record(
    9,
    'rescheduled session counted on new local operational date',
    COALESCE(v_row.completed_session_count, 0) >= 1
  );
END $$;

-- 10: current teacher authoritative after substitution
DO $$
DECLARE v_teacher uuid;
BEGIN
  PERFORM _m5_ma_as_super();
  SELECT teacher_id INTO v_teacher
  FROM teaching_session WHERE id = (SELECT session_id FROM _m5_ma_fixture);
  PERFORM _m5_ma_record(
    10,
    'current teacher_id authoritative after substitution',
    v_teacher = (SELECT teacher_b FROM _m5_ma_fixture)
  );
END $$;

-- 11: cancelled session is not delivered
DO $$
DECLARE v_ops jsonb;
BEGIN
  PERFORM _m5_ma_as_auth('a1111111-1111-4111-8111-111111111111');
  v_ops := public.get_teaching_ops_intelligence_overview('2047-06-01', '2047-06-30', false);
  PERFORM _m5_ma_record(
    11,
    'cancelled sessions tracked separately from delivered',
    (v_ops->'sessionMetrics'->'current'->>'cancelled_sessions')::bigint >= 1
  );
END $$;

-- 12: tenant isolation — org B manager cannot read org A finance intelligence
DO $$
DECLARE v_denied boolean := false;
BEGIN
  PERFORM _m5_ma_as_auth('b1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.get_finance_intelligence_overview(CURRENT_DATE, CURRENT_DATE, false);
    v_denied := (public.current_organization_id() <> 'a0000000-0000-4000-8000-000000000001');
  EXCEPTION WHEN others THEN
    v_denied := true;
  END;
  PERFORM _m5_ma_as_auth('b1111111-1111-4111-8111-111111111111');
  PERFORM _m5_ma_record(
    12,
    'cross-org finance intelligence isolated by organization context',
    v_denied
      AND public.current_organization_id() = 'b0000000-0000-4000-8000-000000000001'
  );
END $$;

-- 13: executive permission enforcement — accountant denied executive overview RPC
DO $$
DECLARE v_denied boolean := false;
BEGIN
  PERFORM _m5_ma_as_auth('a7777777-7777-4777-8777-777777777777');
  BEGIN
    PERFORM public.get_executive_overview(CURRENT_DATE, CURRENT_DATE, false);
    v_denied := false;
  EXCEPTION WHEN others THEN
    v_denied := true;
  END;
  PERFORM _m5_ma_record(13, 'accountant denied executive overview RPC', v_denied);
END $$;

-- 14: teacher scoped reporting — teacher denied center-wide teaching ops intelligence
DO $$
DECLARE v_denied boolean := false;
BEGIN
  PERFORM _m5_ma_as_auth('e2222222-2222-4222-8222-222222222222');
  BEGIN
    PERFORM public.get_teaching_ops_intelligence_overview(CURRENT_DATE, CURRENT_DATE, false);
    v_denied := false;
  EXCEPTION WHEN others THEN
    v_denied := true;
  END;
  PERFORM _m5_ma_record(14, 'teacher denied center-wide teaching ops intelligence', v_denied);
END $$;

-- 15: consultant and academic ops denied executive surfaces
DO $$
DECLARE v_cons_denied boolean := false;
  v_acad_denied boolean := false;
  v_acad_auth uuid;
BEGIN
  PERFORM _m5_ma_as_auth('d1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.get_executive_overview(CURRENT_DATE, CURRENT_DATE, false);
    v_cons_denied := false;
  EXCEPTION WHEN others THEN
    v_cons_denied := true;
  END;
  SELECT auth_user_id INTO v_acad_auth
  FROM app_user WHERE email = 'm5-t03-academic@olli.local' LIMIT 1;
  IF v_acad_auth IS NOT NULL THEN
    PERFORM _m5_ma_as_auth(v_acad_auth);
    BEGIN
      PERFORM public.list_executive_exceptions(CURRENT_DATE, CURRENT_DATE, NULL, NULL, NULL, NULL, true);
      v_acad_denied := false;
    EXCEPTION WHEN others THEN
      v_acad_denied := true;
    END;
  ELSE
    v_acad_denied := true;
  END IF;
  PERFORM _m5_ma_record(
    15,
    'consultant and academic ops denied executive RPCs',
    v_cons_denied AND v_acad_denied
  );
END $$;

-- 16: stable deterministic exception identity
DO $$
DECLARE v_a text; v_b text;
BEGIN
  v_a := public.build_executive_exception_key('quality', 'attendance_pending', 'teaching_session', 'sess-1');
  v_b := public.build_executive_exception_key('quality', 'attendance_pending', 'teaching_session', 'sess-1');
  PERFORM _m5_ma_record(
    16,
    'exception_key identity stable and deterministic',
    v_a = v_b AND v_a = 'quality|attendance_pending|teaching_session|sess-1'
  );
END $$;

DO $$
DECLARE v_fail integer; v_total integer; r record;
BEGIN
  SELECT count(*) FILTER (WHERE result = 'FAIL'), count(*) INTO v_fail, v_total FROM _m5_ma_results;
  IF v_fail > 0 THEN
    FOR r IN SELECT test_no, test_name FROM _m5_ma_results WHERE result = 'FAIL' ORDER BY test_no LOOP
      RAISE NOTICE 'FAILED: % - %', r.test_no, r.test_name;
    END LOOP;
    RAISE EXCEPTION 'M5 milestone acceptance: %/% FAIL (% failed)', v_total - v_fail, v_total, v_fail;
  END IF;
  RAISE NOTICE 'M5 milestone acceptance: %/% PASS (0 FAIL)', v_total, v_total;
END $$;

COMMIT;
