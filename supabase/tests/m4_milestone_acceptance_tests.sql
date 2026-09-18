-- M4 milestone acceptance: cross-surface operational consistency (8 tests).

BEGIN;

CREATE TEMP TABLE _m4_ma_results (
  test_no   integer PRIMARY KEY,
  test_name text NOT NULL,
  result    text NOT NULL CHECK (result IN ('PASS', 'FAIL'))
);

GRANT ALL ON TABLE _m4_ma_results TO authenticated, anon;

CREATE OR REPLACE FUNCTION _m4_ma_record(test_no integer, test_name text, passed boolean)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO _m4_ma_results (test_no, test_name, result)
  VALUES (test_no, test_name, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END);
END;
$$;

CREATE OR REPLACE FUNCTION _m4_ma_as_auth(p_auth_id uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', p_auth_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_auth_id::text, 'role', 'authenticated')::text, true);
END;
$$;

CREATE OR REPLACE FUNCTION _m4_ma_as_super()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
END;
$$;

CREATE OR REPLACE FUNCTION _m4_ma_weekday(p_date date)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE EXTRACT(DOW FROM p_date)::int
    WHEN 0 THEN 'sun' WHEN 1 THEN 'mon' WHEN 2 THEN 'tue' WHEN 3 THEN 'wed'
    WHEN 4 THEN 'thu' WHEN 5 THEN 'fri' WHEN 6 THEN 'sat'
  END;
$$;

CREATE TEMP TABLE _m4_ma_fixture (
  class_id uuid,
  teacher_id uuid,
  room_id uuid,
  schedule_id uuid,
  session_id uuid,
  day_a date,
  day_b date
);

GRANT ALL ON TABLE _m4_ma_fixture TO authenticated, anon;

-- Setup: materialized session on Day A, rescheduled to Day B
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_class uuid;
  v_teacher uuid;
  v_room uuid;
  v_schedule uuid;
  v_session uuid;
  v_day_a date := '2043-09-10';
  v_day_b date := '2043-09-12';
BEGIN
  PERFORM _m4_ma_as_super();
  INSERT INTO class (organization_id, course_id, name, status, term_start_date, term_end_date)
  SELECT v_org, c.course_id, 'MA Cross Surface', 'active', '2043-09-01', '2043-09-30'
  FROM class c WHERE c.organization_id = v_org LIMIT 1
  RETURNING id INTO v_class;
  INSERT INTO teacher (organization_id, given_name, family_name, status)
  VALUES (v_org, 'MA', 'Teacher', 'active') RETURNING id INTO v_teacher;
  INSERT INTO room (organization_id, code, name, status)
  VALUES (v_org, 'MA-R1', 'MA Room', 'active') RETURNING id INTO v_room;
  INSERT INTO class_schedule (
    organization_id, class_id, weekday_code, start_time, end_time,
    effective_from, room_id, teacher_id, status
  ) VALUES (
    v_org, v_class, _m4_ma_weekday(v_day_a), '09:00', '10:00',
    '2043-09-01', v_room, v_teacher, 'active'
  ) RETURNING id INTO v_schedule;
  INSERT INTO teaching_session (
    organization_id, class_id, class_schedule_id, teacher_id, room_id,
    occurrence_date, scheduled_start_at, scheduled_end_at, status
  ) VALUES (
    v_org, v_class, v_schedule, v_teacher, v_room, v_day_a,
    timestamptz '2043-09-10 09:00:00+07', timestamptz '2043-09-10 10:00:00+07', 'scheduled'
  ) RETURNING id INTO v_session;

  PERFORM _m4_ma_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.reschedule_teaching_session(
    v_session,
    timestamptz '2043-09-12 09:00:00+07',
    timestamptz '2043-09-12 10:00:00+07',
    'Cross-surface move'
  );

  DELETE FROM _m4_ma_fixture;
  INSERT INTO _m4_ma_fixture VALUES (v_class, v_teacher, v_room, v_schedule, v_session, v_day_a, v_day_b);
END $$;

-- 1: Daily Operations absent on original day after reschedule
DO $$
DECLARE v_cnt integer;
BEGIN
  PERFORM _m4_ma_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_cnt
  FROM public.list_daily_operations(
    (SELECT day_a FROM _m4_ma_fixture),
    (SELECT class_id FROM _m4_ma_fixture), NULL, NULL
  )
  WHERE entry_type = 'session'
    AND teaching_session_id = (SELECT session_id FROM _m4_ma_fixture);
  PERFORM _m4_ma_record(1, 'daily operations absent on original day after reschedule', v_cnt = 0);
END $$;

-- 2: Daily Operations present on new scheduled day
DO $$
DECLARE v_cnt integer;
BEGIN
  PERFORM _m4_ma_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_cnt
  FROM public.list_daily_operations(
    (SELECT day_b FROM _m4_ma_fixture),
    (SELECT class_id FROM _m4_ma_fixture), NULL, NULL
  )
  WHERE entry_type = 'session'
    AND teaching_session_id = (SELECT session_id FROM _m4_ma_fixture);
  PERFORM _m4_ma_record(2, 'daily operations present on new scheduled day', v_cnt = 1);
END $$;

-- 3: Operational Calendar absent on original day
DO $$
DECLARE v_cnt integer;
BEGIN
  PERFORM _m4_ma_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_cnt
  FROM public.list_operational_calendar(
    (SELECT day_a FROM _m4_ma_fixture), (SELECT day_a FROM _m4_ma_fixture),
    (SELECT class_id FROM _m4_ma_fixture), NULL, NULL
  )
  WHERE entry_type = 'session'
    AND teaching_session_id = (SELECT session_id FROM _m4_ma_fixture);
  PERFORM _m4_ma_record(3, 'operational calendar absent on original day', v_cnt = 0);
END $$;

-- 4: Operational Calendar present on new scheduled day
DO $$
DECLARE v_cnt integer;
BEGIN
  PERFORM _m4_ma_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_cnt
  FROM public.list_operational_calendar(
    (SELECT day_b FROM _m4_ma_fixture), (SELECT day_b FROM _m4_ma_fixture),
    (SELECT class_id FROM _m4_ma_fixture), NULL, NULL
  )
  WHERE entry_type = 'session'
    AND teaching_session_id = (SELECT session_id FROM _m4_ma_fixture);
  PERFORM _m4_ma_record(4, 'operational calendar present on new scheduled day', v_cnt = 1);
END $$;

-- 5: Workload no longer counts session on original day
DO $$
DECLARE v_row record;
BEGIN
  PERFORM _m4_ma_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT * INTO v_row FROM public.list_teacher_workload(
    (SELECT day_a FROM _m4_ma_fixture), (SELECT day_a FROM _m4_ma_fixture),
    (SELECT class_id FROM _m4_ma_fixture),
    (SELECT teacher_id FROM _m4_ma_fixture)
  );
  PERFORM _m4_ma_record(
    5, 'workload excludes rescheduled session from original day',
    COALESCE(v_row.materialized_session_count, 0) = 0
  );
END $$;

-- 6: Workload counts session on new scheduled day
DO $$
DECLARE v_row record;
BEGIN
  PERFORM _m4_ma_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT * INTO v_row FROM public.list_teacher_workload(
    (SELECT day_b FROM _m4_ma_fixture), (SELECT day_b FROM _m4_ma_fixture),
    (SELECT class_id FROM _m4_ma_fixture),
    (SELECT teacher_id FROM _m4_ma_fixture)
  );
  PERFORM _m4_ma_record(
    6, 'workload includes rescheduled session on new day',
    v_row.materialized_session_count = 1 AND v_row.materialized_scheduled_minutes = 60
  );
END $$;

-- 7: Original timetable slot does not re-project after reschedule
DO $$
DECLARE v_proj integer;
BEGIN
  PERFORM _m4_ma_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_proj
  FROM public.list_operational_calendar(
    (SELECT day_a FROM _m4_ma_fixture), (SELECT day_a FROM _m4_ma_fixture),
    (SELECT class_id FROM _m4_ma_fixture), NULL, NULL
  )
  WHERE entry_type = 'projected'
    AND class_schedule_id = (SELECT schedule_id FROM _m4_ma_fixture)
    AND occurrence_date = (SELECT day_a FROM _m4_ma_fixture);
  PERFORM _m4_ma_record(7, 'original occurrence does not re-project after reschedule', v_proj = 0);
END $$;

-- 8: Reschedule preserved in append-only change history
DO $$
DECLARE v_cnt integer;
BEGIN
  PERFORM _m4_ma_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_cnt
  FROM public.list_teaching_session_changes((SELECT session_id FROM _m4_ma_fixture))
  WHERE change_type = 'rescheduled';
  PERFORM _m4_ma_record(8, 'reschedule recorded in session change history', v_cnt = 1);
END $$;

DO $$
DECLARE v_fail integer;
BEGIN
  SELECT count(*) INTO v_fail FROM _m4_ma_results WHERE result = 'FAIL';
  IF v_fail > 0 THEN
    RAISE EXCEPTION 'M4 milestone acceptance tests failed: % failure(s)', v_fail;
  END IF;
  RAISE NOTICE 'M4 milestone acceptance: all % tests passed', (SELECT count(*) FROM _m4_ma_results);
END $$;

ROLLBACK;
