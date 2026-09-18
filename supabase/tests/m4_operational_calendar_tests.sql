-- M4-T05: Operational calendar read-model tests.

BEGIN;

CREATE TEMP TABLE _m4_oc_results (
  test_no   integer PRIMARY KEY,
  test_name text NOT NULL,
  result    text NOT NULL CHECK (result IN ('PASS', 'FAIL'))
);

GRANT ALL ON TABLE _m4_oc_results TO authenticated, anon;

CREATE OR REPLACE FUNCTION _m4_oc_record(test_no integer, test_name text, passed boolean)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO _m4_oc_results (test_no, test_name, result)
  VALUES (test_no, test_name, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END);
END;
$$;

CREATE OR REPLACE FUNCTION _m4_oc_expect_fail(test_no integer, test_name text, sql_text text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE sql_text;
    PERFORM _m4_oc_record(test_no, test_name, false);
  EXCEPTION WHEN OTHERS THEN
    PERFORM _m4_oc_record(test_no, test_name, true);
  END;
END;
$$;

CREATE OR REPLACE FUNCTION _m4_oc_as_auth(p_auth_id uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', p_auth_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_auth_id::text, 'role', 'authenticated')::text, true);
END;
$$;

CREATE OR REPLACE FUNCTION _m4_oc_as_super()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
END;
$$;

CREATE OR REPLACE FUNCTION _m4_oc_new_class(p_name text, p_term_start date, p_term_end date, p_status text DEFAULT 'active')
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_id uuid;
BEGIN
  INSERT INTO class (organization_id, course_id, name, status, term_start_date, term_end_date)
  SELECT v_org, c.course_id, p_name, p_status, p_term_start, p_term_end
  FROM class c WHERE c.organization_id = v_org LIMIT 1
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION _m4_oc_new_teacher(p_label text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
  v_id uuid;
BEGIN
  INSERT INTO teacher (organization_id, given_name, family_name, status)
  VALUES ('a0000000-0000-4000-8000-000000000001', p_label, 'OC' || substr(gen_random_uuid()::text, 1, 8), 'active')
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION _m4_oc_new_room(p_label text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
  v_id uuid;
BEGIN
  INSERT INTO room (organization_id, code, name, status)
  VALUES ('a0000000-0000-4000-8000-000000000001', 'OC-' || substr(gen_random_uuid()::text, 1, 8), p_label, 'active')
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

-- 1: materialized session appears in calendar
-- 2033-01-03 is Monday
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_class uuid;
  v_teacher uuid;
  v_room uuid;
  v_schedule uuid;
  v_session uuid;
  v_cnt integer;
BEGIN
  PERFORM _m4_oc_as_super();
  v_class := _m4_oc_new_class('OC1 Session', '2033-01-01', '2033-03-31');
  v_teacher := _m4_oc_new_teacher('OC1');
  v_room := _m4_oc_new_room('OC1 Room');

  INSERT INTO class_schedule (
    organization_id, class_id, weekday_code, start_time, end_time,
    effective_from, room_id, teacher_id, status
  ) VALUES (
    v_org, v_class, 'mon', '09:00', '10:00', '2033-01-01', v_room, v_teacher, 'active'
  ) RETURNING id INTO v_schedule;

  INSERT INTO teaching_session (
    organization_id, class_id, class_schedule_id, teacher_id, room_id,
    occurrence_date, scheduled_start_at, scheduled_end_at, status
  ) VALUES (
    v_org, v_class, v_schedule, v_teacher, v_room,
    '2033-01-03',
    timestamptz '2033-01-03 09:00:00+07',
    timestamptz '2033-01-03 10:00:00+07',
    'scheduled'
  ) RETURNING id INTO v_session;

  PERFORM _m4_oc_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_cnt
  FROM public.list_operational_calendar('2033-01-03', '2033-01-03', v_class, NULL, NULL)
  WHERE entry_type = 'session' AND teaching_session_id = v_session;

  PERFORM _m4_oc_record(1, 'materialized session appears in calendar', v_cnt = 1);
END $$;

-- 2: future unmaterialized schedule occurrence appears as projected
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_class uuid;
  v_teacher uuid;
  v_room uuid;
  v_cnt integer;
BEGIN
  PERFORM _m4_oc_as_super();
  v_class := _m4_oc_new_class('OC2 Projected', '2033-02-01', '2033-03-31');
  v_teacher := _m4_oc_new_teacher('OC2');
  v_room := _m4_oc_new_room('OC2 Room');

  INSERT INTO class_schedule (
    organization_id, class_id, weekday_code, start_time, end_time,
    effective_from, room_id, teacher_id, status
  ) VALUES (
    v_org, v_class, 'tue', '14:00', '15:00', '2033-02-01', v_room, v_teacher, 'active'
  );

  PERFORM _m4_oc_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_cnt
  FROM public.list_operational_calendar('2033-02-01', '2033-02-08', v_class, NULL, NULL)
  WHERE entry_type = 'projected' AND occurrence_date = '2033-02-01';

  PERFORM _m4_oc_record(2, 'unmaterialized occurrence appears as projected', v_cnt = 1);
END $$;

-- 3: materialized session suppresses projection
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_class uuid;
  v_teacher uuid;
  v_room uuid;
  v_schedule uuid;
  v_sess integer;
  v_proj integer;
BEGIN
  PERFORM _m4_oc_as_super();
  v_class := _m4_oc_new_class('OC3 Dedup', '2033-03-01', '2033-03-31');
  v_teacher := _m4_oc_new_teacher('OC3');
  v_room := _m4_oc_new_room('OC3 Room');

  INSERT INTO class_schedule (
    organization_id, class_id, weekday_code, start_time, end_time,
    effective_from, room_id, teacher_id, status
  ) VALUES (
    v_org, v_class, 'wed', '10:00', '11:00', '2033-03-01', v_room, v_teacher, 'active'
  ) RETURNING id INTO v_schedule;

  INSERT INTO teaching_session (
    organization_id, class_id, class_schedule_id, teacher_id, room_id,
    occurrence_date, scheduled_start_at, scheduled_end_at, status
  ) VALUES (
    v_org, v_class, v_schedule, v_teacher, v_room,
    '2033-03-02',
    timestamptz '2033-03-02 10:00:00+07',
    timestamptz '2033-03-02 11:00:00+07',
    'scheduled'
  );

  PERFORM _m4_oc_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT
    count(*) FILTER (WHERE entry_type = 'session'),
    count(*) FILTER (WHERE entry_type = 'projected' AND occurrence_date = '2033-03-02')
  INTO v_sess, v_proj
  FROM public.list_operational_calendar('2033-03-02', '2033-03-02', v_class, NULL, NULL);

  PERFORM _m4_oc_record(3, 'materialized session suppresses projection', v_sess = 1 AND v_proj = 0);
END $$;

-- 4: cancelled session suppresses projection and remains visible
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_class uuid;
  v_teacher uuid;
  v_room uuid;
  v_schedule uuid;
  v_sess integer;
  v_proj integer;
BEGIN
  PERFORM _m4_oc_as_super();
  v_class := _m4_oc_new_class('OC4 Cancelled', '2033-04-01', '2033-04-30');
  v_teacher := _m4_oc_new_teacher('OC4');
  v_room := _m4_oc_new_room('OC4 Room');

  INSERT INTO class_schedule (
    organization_id, class_id, weekday_code, start_time, end_time,
    effective_from, room_id, teacher_id, status
  ) VALUES (
    v_org, v_class, 'thu', '09:00', '10:00', '2033-04-01', v_room, v_teacher, 'active'
  ) RETURNING id INTO v_schedule;

  INSERT INTO teaching_session (
    organization_id, class_id, class_schedule_id, teacher_id, room_id,
    occurrence_date, scheduled_start_at, scheduled_end_at, status
  ) VALUES (
    v_org, v_class, v_schedule, v_teacher, v_room,
    '2033-04-07',
    timestamptz '2033-04-07 09:00:00+07',
    timestamptz '2033-04-07 10:00:00+07',
    'cancelled'
  );

  PERFORM _m4_oc_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT
    count(*) FILTER (WHERE entry_type = 'session' AND session_status = 'cancelled'),
    count(*) FILTER (WHERE entry_type = 'projected' AND occurrence_date = '2033-04-07')
  INTO v_sess, v_proj
  FROM public.list_operational_calendar('2033-04-07', '2033-04-07', v_class, NULL, NULL);

  PERFORM _m4_oc_record(4, 'cancelled session visible and suppresses projection', v_sess = 1 AND v_proj = 0);
END $$;

-- 5: completed session appears correctly
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_class uuid;
  v_teacher uuid;
  v_cnt integer;
  v_schedule uuid;
BEGIN
  PERFORM _m4_oc_as_super();
  v_class := _m4_oc_new_class('OC5 Completed', '2033-05-01', '2033-05-31');
  v_teacher := _m4_oc_new_teacher('OC5');

  INSERT INTO class_schedule (
    organization_id, class_id, weekday_code, start_time, end_time,
    effective_from, teacher_id, status
  ) VALUES (
    v_org, v_class, 'fri', '11:00', '12:00', '2033-05-01', v_teacher, 'active'
  ) RETURNING id INTO v_schedule;

  INSERT INTO teaching_session (
    organization_id, class_id, class_schedule_id, teacher_id,
    occurrence_date, scheduled_start_at, scheduled_end_at, status
  ) VALUES (
    v_org, v_class, v_schedule, v_teacher,
    '2033-05-06',
    timestamptz '2033-05-06 11:00:00+07',
    timestamptz '2033-05-06 12:00:00+07',
    'completed'
  );

  PERFORM _m4_oc_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_cnt
  FROM public.list_operational_calendar('2033-05-06', '2033-05-06', v_class, NULL, NULL)
  WHERE entry_type = 'session' AND session_status = 'completed';

  PERFORM _m4_oc_record(5, 'completed session appears correctly', v_cnt = 1);
END $$;

-- 6: in-progress session appears correctly
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_class uuid;
  v_teacher uuid;
  v_schedule uuid;
  v_cnt integer;
BEGIN
  PERFORM _m4_oc_as_super();
  v_class := _m4_oc_new_class('OC6 InProgress', '2033-06-01', '2033-06-30');
  v_teacher := _m4_oc_new_teacher('OC6');

  INSERT INTO class_schedule (
    organization_id, class_id, weekday_code, start_time, end_time,
    effective_from, teacher_id, status
  ) VALUES (
    v_org, v_class, 'sat', '08:00', '09:00', '2033-06-01', v_teacher, 'active'
  ) RETURNING id INTO v_schedule;

  INSERT INTO teaching_session (
    organization_id, class_id, class_schedule_id, teacher_id,
    occurrence_date, scheduled_start_at, scheduled_end_at, status
  ) VALUES (
    v_org, v_class, v_schedule, v_teacher,
    '2033-06-04',
    timestamptz '2033-06-04 08:00:00+07',
    timestamptz '2033-06-04 09:00:00+07',
    'in_progress'
  );

  PERFORM _m4_oc_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_cnt
  FROM public.list_operational_calendar('2033-06-04', '2033-06-04', v_class, NULL, NULL)
  WHERE entry_type = 'session' AND session_status = 'in_progress';

  PERFORM _m4_oc_record(6, 'in-progress session appears correctly', v_cnt = 1);
END $$;

-- 7: ended schedule does not project future occurrence
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_class uuid;
  v_teacher uuid;
  v_cnt integer;
BEGIN
  PERFORM _m4_oc_as_super();
  v_class := _m4_oc_new_class('OC7 Ended Sched', '2033-07-01', '2033-12-31');
  v_teacher := _m4_oc_new_teacher('OC7');

  INSERT INTO class_schedule (
    organization_id, class_id, weekday_code, start_time, end_time,
    effective_from, effective_to, teacher_id, status
  ) VALUES (
    v_org, v_class, 'mon', '09:00', '10:00', '2033-07-01', '2033-07-31', v_teacher, 'ended'
  );

  PERFORM _m4_oc_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_cnt
  FROM public.list_operational_calendar('2033-08-01', '2033-08-07', v_class, NULL, NULL)
  WHERE entry_type = 'projected';

  PERFORM _m4_oc_record(7, 'ended schedule does not project future', v_cnt = 0);
END $$;

-- 8: historical session from ended schedule remains visible
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_class uuid;
  v_teacher uuid;
  v_schedule uuid;
  v_cnt integer;
BEGIN
  PERFORM _m4_oc_as_super();
  v_class := _m4_oc_new_class('OC8 Hist Ended', '2033-08-01', '2033-12-31');
  v_teacher := _m4_oc_new_teacher('OC8');

  INSERT INTO class_schedule (
    organization_id, class_id, weekday_code, start_time, end_time,
    effective_from, effective_to, teacher_id, status
  ) VALUES (
    v_org, v_class, 'tue', '09:00', '10:00', '2033-08-01', '2033-08-15', v_teacher, 'ended'
  ) RETURNING id INTO v_schedule;

  INSERT INTO teaching_session (
    organization_id, class_id, class_schedule_id, teacher_id,
    occurrence_date, scheduled_start_at, scheduled_end_at, status
  ) VALUES (
    v_org, v_class, v_schedule, v_teacher,
    '2033-08-08',
    timestamptz '2033-08-08 09:00:00+07',
    timestamptz '2033-08-08 10:00:00+07',
    'completed'
  );

  PERFORM _m4_oc_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_cnt
  FROM public.list_operational_calendar('2033-08-08', '2033-08-08', v_class, NULL, NULL)
  WHERE entry_type = 'session' AND session_status = 'completed';

  PERFORM _m4_oc_record(8, 'historical session from ended schedule visible', v_cnt = 1);
END $$;

-- 9: closed class does not create invalid future projection
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_class uuid;
  v_teacher uuid;
  v_cnt integer;
BEGIN
  PERFORM _m4_oc_as_super();
  v_class := _m4_oc_new_class('OC9 Closed', '2033-09-01', '2033-12-31', 'closed');
  v_teacher := _m4_oc_new_teacher('OC9');

  INSERT INTO class_schedule (
    organization_id, class_id, weekday_code, start_time, end_time,
    effective_from, teacher_id, status
  ) VALUES (
    v_org, v_class, 'wed', '09:00', '10:00', '2033-09-01', v_teacher, 'active'
  );

  PERFORM _m4_oc_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_cnt
  FROM public.list_operational_calendar('2033-09-01', '2033-09-14', v_class, NULL, NULL)
  WHERE entry_type = 'projected';

  PERFORM _m4_oc_record(9, 'closed class does not project future', v_cnt = 0);
END $$;

-- 10: historical session for closed class remains visible
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_class uuid;
  v_teacher uuid;
  v_schedule uuid;
  v_cnt integer;
BEGIN
  PERFORM _m4_oc_as_super();
  v_class := _m4_oc_new_class('OC10 Closed Hist', '2033-10-01', '2033-12-31', 'closed');
  v_teacher := _m4_oc_new_teacher('OC10');

  INSERT INTO class_schedule (
    organization_id, class_id, weekday_code, start_time, end_time,
    effective_from, teacher_id, status
  ) VALUES (
    v_org, v_class, 'thu', '09:00', '10:00', '2033-10-01', v_teacher, 'ended'
  ) RETURNING id INTO v_schedule;

  INSERT INTO teaching_session (
    organization_id, class_id, class_schedule_id, teacher_id,
    occurrence_date, scheduled_start_at, scheduled_end_at, status
  ) VALUES (
    v_org, v_class, v_schedule, v_teacher,
    '2033-10-05',
    timestamptz '2033-10-05 09:00:00+07',
    timestamptz '2033-10-05 10:00:00+07',
    'completed'
  );

  PERFORM _m4_oc_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_cnt
  FROM public.list_operational_calendar('2033-10-05', '2033-10-05', v_class, NULL, NULL)
  WHERE entry_type = 'session';

  PERFORM _m4_oc_record(10, 'historical session for closed class visible', v_cnt = 1);
END $$;

-- 11: schedule teacher resolves correctly
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_class uuid;
  v_teacher uuid;
  v_row record;
BEGIN
  PERFORM _m4_oc_as_super();
  v_class := _m4_oc_new_class('OC11 Sched Teacher', '2033-11-01', '2033-11-30');
  v_teacher := _m4_oc_new_teacher('OC11');

  INSERT INTO class_schedule (
    organization_id, class_id, weekday_code, start_time, end_time,
    effective_from, teacher_id, status
  ) VALUES (
    v_org, v_class, 'fri', '13:00', '14:00', '2033-11-01', v_teacher, 'active'
  );

  PERFORM _m4_oc_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT * INTO v_row
  FROM public.list_operational_calendar('2033-11-04', '2033-11-04', v_class, NULL, NULL)
  WHERE entry_type = 'projected'
  LIMIT 1;

  PERFORM _m4_oc_record(
    11,
    'schedule teacher resolves correctly',
    v_row.teacher_id = v_teacher AND v_row.teacher_resolution_status = 'resolved'
  );
END $$;

-- 12: unique primary fallback resolves correctly
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_class uuid;
  v_teacher uuid;
  v_row record;
BEGIN
  PERFORM _m4_oc_as_super();
  v_class := _m4_oc_new_class('OC12 Primary', '2033-12-01', '2033-12-31');
  v_teacher := _m4_oc_new_teacher('OC12');

  INSERT INTO class_teacher_assignment (
    organization_id, class_id, teacher_id, role_code, effective_from, status
  ) VALUES (
    v_org, v_class, v_teacher, 'primary', '2033-12-01', 'active'
  );

  INSERT INTO class_schedule (
    organization_id, class_id, weekday_code, start_time, end_time,
    effective_from, teacher_id, status
  ) VALUES (
    v_org, v_class, 'sat', '10:00', '11:00', '2033-12-01', NULL, 'active'
  );

  PERFORM _m4_oc_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT * INTO v_row
  FROM public.list_operational_calendar('2033-12-03', '2033-12-03', v_class, NULL, NULL)
  WHERE entry_type = 'projected'
  LIMIT 1;

  PERFORM _m4_oc_record(
    12,
    'unique primary fallback resolves correctly',
    v_row.teacher_id = v_teacher AND v_row.teacher_resolution_status = 'resolved'
  );
END $$;

-- 13: assistant does not resolve as fallback
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_class uuid;
  v_assistant uuid;
  v_row record;
BEGIN
  PERFORM _m4_oc_as_super();
  v_class := _m4_oc_new_class('OC13 Assistant', '2034-01-01', '2034-01-31');
  v_assistant := _m4_oc_new_teacher('OC13A');

  INSERT INTO class_teacher_assignment (
    organization_id, class_id, teacher_id, role_code, effective_from, status
  ) VALUES (
    v_org, v_class, v_assistant, 'assistant', '2034-01-01', 'active'
  );

  INSERT INTO class_schedule (
    organization_id, class_id, weekday_code, start_time, end_time,
    effective_from, teacher_id, status
  ) VALUES (
    v_org, v_class, 'mon', '09:00', '10:00', '2034-01-01', NULL, 'active'
  );

  PERFORM _m4_oc_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT * INTO v_row
  FROM public.list_operational_calendar('2034-01-02', '2034-01-02', v_class, NULL, NULL)
  WHERE entry_type = 'projected'
  LIMIT 1;

  PERFORM _m4_oc_record(
    13,
    'assistant does not resolve as fallback',
    v_row.teacher_id IS NULL AND v_row.teacher_resolution_status = 'teacher_not_resolved'
  );
END $$;

-- 14: no primary produces unresolved state
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_class uuid;
  v_row record;
BEGIN
  PERFORM _m4_oc_as_super();
  v_class := _m4_oc_new_class('OC14 No Primary', '2034-02-01', '2034-02-28');

  INSERT INTO class_schedule (
    organization_id, class_id, weekday_code, start_time, end_time,
    effective_from, teacher_id, status
  ) VALUES (
    v_org, v_class, 'tue', '09:00', '10:00', '2034-02-01', NULL, 'active'
  );

  PERFORM _m4_oc_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT * INTO v_row
  FROM public.list_operational_calendar('2034-02-07', '2034-02-07', v_class, NULL, NULL)
  WHERE entry_type = 'projected'
  LIMIT 1;

  PERFORM _m4_oc_record(
    14,
    'no primary produces unresolved state',
    v_row.teacher_resolution_status = 'teacher_not_resolved' AND v_row.entry_type = 'projected'
  );
END $$;

-- 15: multiple primary produces ambiguous state
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_class uuid;
  v_t1 uuid;
  v_t2 uuid;
  v_row record;
BEGIN
  PERFORM _m4_oc_as_super();
  v_class := _m4_oc_new_class('OC15 Multi Primary', '2034-03-01', '2034-03-31');
  v_t1 := _m4_oc_new_teacher('OC15A');
  v_t2 := _m4_oc_new_teacher('OC15B');

  INSERT INTO class_teacher_assignment (
    organization_id, class_id, teacher_id, role_code, effective_from, status
  ) VALUES
    (v_org, v_class, v_t1, 'primary', '2034-03-01', 'active'),
    (v_org, v_class, v_t2, 'primary', '2034-03-01', 'active');

  INSERT INTO class_schedule (
    organization_id, class_id, weekday_code, start_time, end_time,
    effective_from, teacher_id, status
  ) VALUES (
    v_org, v_class, 'wed', '09:00', '10:00', '2034-03-01', NULL, 'active'
  );

  PERFORM _m4_oc_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT * INTO v_row
  FROM public.list_operational_calendar('2034-03-01', '2034-03-01', v_class, NULL, NULL)
  WHERE entry_type = 'projected'
  LIMIT 1;

  PERFORM _m4_oc_record(
    15,
    'multiple primary produces ambiguous state',
    v_row.teacher_resolution_status = 'multiple_primary_teachers' AND v_row.teacher_id IS NULL
  );
END $$;

-- 16: teacher filter works on projected occurrence
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_class uuid;
  v_t1 uuid;
  v_t2 uuid;
  v_cnt integer;
BEGIN
  PERFORM _m4_oc_as_super();
  v_class := _m4_oc_new_class('OC16 Teacher Filt Proj', '2034-04-01', '2034-04-30');
  v_t1 := _m4_oc_new_teacher('OC16A');
  v_t2 := _m4_oc_new_teacher('OC16B');

  INSERT INTO class_schedule (
    organization_id, class_id, weekday_code, start_time, end_time,
    effective_from, teacher_id, status
  ) VALUES (
    v_org, v_class, 'thu', '09:00', '10:00', '2034-04-01', v_t1, 'active'
  );

  PERFORM _m4_oc_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_cnt
  FROM public.list_operational_calendar('2034-04-06', '2034-04-06', v_class, v_t2, NULL);

  PERFORM _m4_oc_record(16, 'teacher filter works on projected occurrence', v_cnt = 0);
END $$;

-- 17: teacher filter works on materialized session snapshot
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_class uuid;
  v_t1 uuid;
  v_t2 uuid;
  v_schedule uuid;
  v_cnt integer;
BEGIN
  PERFORM _m4_oc_as_super();
  v_class := _m4_oc_new_class('OC17 Teacher Filt Sess', '2034-05-01', '2034-05-31');
  v_t1 := _m4_oc_new_teacher('OC17A');
  v_t2 := _m4_oc_new_teacher('OC17B');

  INSERT INTO class_schedule (
    organization_id, class_id, weekday_code, start_time, end_time,
    effective_from, teacher_id, status
  ) VALUES (
    v_org, v_class, 'fri', '09:00', '10:00', '2034-05-01', v_t2, 'active'
  ) RETURNING id INTO v_schedule;

  -- Session snapshot keeps t1 even if schedule now says t2
  INSERT INTO teaching_session (
    organization_id, class_id, class_schedule_id, teacher_id,
    occurrence_date, scheduled_start_at, scheduled_end_at, status
  ) VALUES (
    v_org, v_class, v_schedule, v_t1,
    '2034-05-05',
    timestamptz '2034-05-05 09:00:00+07',
    timestamptz '2034-05-05 10:00:00+07',
    'scheduled'
  );

  PERFORM _m4_oc_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_cnt
  FROM public.list_operational_calendar('2034-05-05', '2034-05-05', v_class, v_t1, NULL)
  WHERE entry_type = 'session';

  PERFORM _m4_oc_record(17, 'teacher filter uses session snapshot', v_cnt = 1);
END $$;

-- 18: room filter works on projected occurrence
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_class uuid;
  v_teacher uuid;
  v_room1 uuid;
  v_room2 uuid;
  v_cnt integer;
BEGIN
  PERFORM _m4_oc_as_super();
  v_class := _m4_oc_new_class('OC18 Room Filt Proj', '2034-06-01', '2034-06-30');
  v_teacher := _m4_oc_new_teacher('OC18');
  v_room1 := _m4_oc_new_room('OC18A');
  v_room2 := _m4_oc_new_room('OC18B');

  INSERT INTO class_schedule (
    organization_id, class_id, weekday_code, start_time, end_time,
    effective_from, room_id, teacher_id, status
  ) VALUES (
    v_org, v_class, 'sat', '09:00', '10:00', '2034-06-01', v_room1, v_teacher, 'active'
  );

  PERFORM _m4_oc_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_cnt
  FROM public.list_operational_calendar('2034-06-03', '2034-06-03', v_class, NULL, v_room2);

  PERFORM _m4_oc_record(18, 'room filter works on projected occurrence', v_cnt = 0);
END $$;

-- 19: room filter works on materialized session
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_class uuid;
  v_teacher uuid;
  v_room1 uuid;
  v_room2 uuid;
  v_schedule uuid;
  v_cnt integer;
BEGIN
  PERFORM _m4_oc_as_super();
  v_class := _m4_oc_new_class('OC19 Room Filt Sess', '2034-07-01', '2034-07-31');
  v_teacher := _m4_oc_new_teacher('OC19');
  v_room1 := _m4_oc_new_room('OC19A');
  v_room2 := _m4_oc_new_room('OC19B');

  INSERT INTO class_schedule (
    organization_id, class_id, weekday_code, start_time, end_time,
    effective_from, room_id, teacher_id, status
  ) VALUES (
    v_org, v_class, 'sun', '09:00', '10:00', '2034-07-01', v_room2, v_teacher, 'active'
  ) RETURNING id INTO v_schedule;

  INSERT INTO teaching_session (
    organization_id, class_id, class_schedule_id, teacher_id, room_id,
    occurrence_date, scheduled_start_at, scheduled_end_at, status
  ) VALUES (
    v_org, v_class, v_schedule, v_teacher, v_room1,
    '2034-07-02',
    timestamptz '2034-07-02 09:00:00+07',
    timestamptz '2034-07-02 10:00:00+07',
    'scheduled'
  );

  PERFORM _m4_oc_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_cnt
  FROM public.list_operational_calendar('2034-07-02', '2034-07-02', v_class, NULL, v_room1)
  WHERE entry_type = 'session';

  PERFORM _m4_oc_record(19, 'room filter works on materialized session', v_cnt = 1);
END $$;

-- 20: class filter works
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_class1 uuid;
  v_class2 uuid;
  v_teacher uuid;
  v_cnt integer;
BEGIN
  PERFORM _m4_oc_as_super();
  v_class1 := _m4_oc_new_class('OC20 Class A', '2034-08-01', '2034-08-31');
  v_class2 := _m4_oc_new_class('OC20 Class B', '2034-08-01', '2034-08-31');
  v_teacher := _m4_oc_new_teacher('OC20');

  INSERT INTO class_schedule (
    organization_id, class_id, weekday_code, start_time, end_time,
    effective_from, teacher_id, status
  ) VALUES
    (v_org, v_class1, 'mon', '09:00', '10:00', '2034-08-01', v_teacher, 'active'),
    (v_org, v_class2, 'mon', '11:00', '12:00', '2034-08-01', v_teacher, 'active');

  PERFORM _m4_oc_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_cnt
  FROM public.list_operational_calendar('2034-08-07', '2034-08-07', v_class1, NULL, NULL);

  PERFORM _m4_oc_record(20, 'class filter works', v_cnt = 1);
END $$;

-- 21: cross-org data excluded
DO $$
DECLARE
  v_cnt integer;
BEGIN
  PERFORM _m4_oc_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_cnt
  FROM public.list_operational_calendar('2034-09-01', '2034-09-07', NULL, NULL, NULL) cal
  JOIN class c ON c.id = cal.class_id
  WHERE c.organization_id <> 'a0000000-0000-4000-8000-000000000001';

  PERFORM _m4_oc_record(21, 'cross-org data excluded', v_cnt = 0);
END $$;

-- 22 recorded later (after fixtures for org B class)

-- 23: organization timezone projection correct
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_class uuid;
  v_teacher uuid;
  v_starts timestamptz;
BEGIN
  PERFORM _m4_oc_as_super();
  v_class := _m4_oc_new_class('OC23 TZ', '2034-10-01', '2034-10-31');
  v_teacher := _m4_oc_new_teacher('OC23');

  INSERT INTO class_schedule (
    organization_id, class_id, weekday_code, start_time, end_time,
    effective_from, teacher_id, status
  ) VALUES (
    v_org, v_class, 'wed', '18:00', '19:30', '2034-10-01', v_teacher, 'active'
  );

  PERFORM _m4_oc_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT starts_at INTO v_starts
  FROM public.list_operational_calendar('2034-10-04', '2034-10-04', v_class, NULL, NULL)
  WHERE entry_type = 'projected'
  LIMIT 1;

  PERFORM _m4_oc_record(
    23,
    'organization timezone projection correct',
    v_starts = timestamptz '2034-10-04 18:00:00+07'
  );
END $$;

-- 24: weekday projection correct
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_class uuid;
  v_teacher uuid;
  v_dates date[];
BEGIN
  PERFORM _m4_oc_as_super();
  v_class := _m4_oc_new_class('OC24 Weekday', '2034-11-01', '2034-11-14');
  v_teacher := _m4_oc_new_teacher('OC24');

  INSERT INTO class_schedule (
    organization_id, class_id, weekday_code, start_time, end_time,
    effective_from, teacher_id, status
  ) VALUES (
    v_org, v_class, 'thu', '09:00', '10:00', '2034-11-01', v_teacher, 'active'
  );

  PERFORM _m4_oc_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT array_agg(occurrence_date ORDER BY occurrence_date) INTO v_dates
  FROM public.list_operational_calendar('2034-11-01', '2034-11-14', v_class, NULL, NULL)
  WHERE entry_type = 'projected';

  PERFORM _m4_oc_record(
    24,
    'weekday projection correct',
    v_dates = ARRAY['2034-11-02'::date, '2034-11-09'::date]
  );
END $$;

-- 25: effective date start boundary correct
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_class uuid;
  v_teacher uuid;
  v_cnt_before integer;
  v_cnt_on integer;
BEGIN
  PERFORM _m4_oc_as_super();
  v_class := _m4_oc_new_class('OC25 Eff Start', '2034-12-01', '2034-12-31');
  v_teacher := _m4_oc_new_teacher('OC25');

  INSERT INTO class_schedule (
    organization_id, class_id, weekday_code, start_time, end_time,
    effective_from, teacher_id, status
  ) VALUES (
    v_org, v_class, 'fri', '09:00', '10:00', '2034-12-15', v_teacher, 'active'
  );

  PERFORM _m4_oc_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_cnt_before
  FROM public.list_operational_calendar('2034-12-08', '2034-12-08', v_class, NULL, NULL);
  SELECT count(*) INTO v_cnt_on
  FROM public.list_operational_calendar('2034-12-15', '2034-12-15', v_class, NULL, NULL);

  PERFORM _m4_oc_record(25, 'effective date start boundary correct', v_cnt_before = 0 AND v_cnt_on = 1);
END $$;

-- 26: effective date end boundary correct
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_class uuid;
  v_teacher uuid;
  v_cnt_on integer;
  v_cnt_after integer;
BEGIN
  PERFORM _m4_oc_as_super();
  v_class := _m4_oc_new_class('OC26 Eff End', '2035-01-01', '2035-01-31');
  v_teacher := _m4_oc_new_teacher('OC26');

  INSERT INTO class_schedule (
    organization_id, class_id, weekday_code, start_time, end_time,
    effective_from, effective_to, teacher_id, status
  ) VALUES (
    v_org, v_class, 'sat', '09:00', '10:00', '2035-01-01', '2035-01-13', v_teacher, 'active'
  );

  PERFORM _m4_oc_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_cnt_on
  FROM public.list_operational_calendar('2035-01-13', '2035-01-13', v_class, NULL, NULL);
  SELECT count(*) INTO v_cnt_after
  FROM public.list_operational_calendar('2035-01-20', '2035-01-20', v_class, NULL, NULL);

  PERFORM _m4_oc_record(26, 'effective date end boundary correct', v_cnt_on = 1 AND v_cnt_after = 0);
END $$;

-- 27: bounded range enforced
SELECT _m4_oc_expect_fail(27, 'bounded range enforced', $$
  DO $inner$
  BEGIN
    PERFORM _m4_oc_as_auth('a1111111-1111-4111-8111-111111111111');
    PERFORM 1 FROM public.list_operational_calendar('2035-02-01', '2035-05-15', NULL, NULL, NULL);
  END $inner$;
$$);

-- 28: dedup returns one row per schedule occurrence
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_class uuid;
  v_teacher uuid;
  v_schedule uuid;
  v_cnt integer;
BEGIN
  PERFORM _m4_oc_as_super();
  v_class := _m4_oc_new_class('OC28 Dedup One', '2035-03-01', '2035-03-31');
  v_teacher := _m4_oc_new_teacher('OC28');

  INSERT INTO class_schedule (
    organization_id, class_id, weekday_code, start_time, end_time,
    effective_from, teacher_id, status
  ) VALUES (
    v_org, v_class, 'sun', '09:00', '10:00', '2035-03-01', v_teacher, 'active'
  ) RETURNING id INTO v_schedule;

  INSERT INTO teaching_session (
    organization_id, class_id, class_schedule_id, teacher_id,
    occurrence_date, scheduled_start_at, scheduled_end_at, status
  ) VALUES (
    v_org, v_class, v_schedule, v_teacher,
    '2035-03-02',
    timestamptz '2035-03-02 09:00:00+07',
    timestamptz '2035-03-02 10:00:00+07',
    'scheduled'
  );

  PERFORM _m4_oc_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_cnt
  FROM public.list_operational_calendar('2035-03-02', '2035-03-02', v_class, NULL, NULL)
  WHERE class_schedule_id = v_schedule AND occurrence_date = '2035-03-02';

  PERFORM _m4_oc_record(28, 'dedup returns one row per schedule occurrence', v_cnt = 1);
END $$;

-- 29: session modified values take precedence over source schedule
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_class uuid;
  v_t_sched uuid;
  v_t_sess uuid;
  v_room_sched uuid;
  v_room_sess uuid;
  v_schedule uuid;
  v_row record;
BEGIN
  PERFORM _m4_oc_as_super();
  v_class := _m4_oc_new_class('OC29 Snapshot', '2035-04-01', '2035-04-30');
  v_t_sched := _m4_oc_new_teacher('OC29Sched');
  v_t_sess := _m4_oc_new_teacher('OC29Sess');
  v_room_sched := _m4_oc_new_room('OC29SchedRoom');
  v_room_sess := _m4_oc_new_room('OC29SessRoom');

  INSERT INTO class_schedule (
    organization_id, class_id, weekday_code, start_time, end_time,
    effective_from, room_id, teacher_id, status
  ) VALUES (
    v_org, v_class, 'mon', '09:00', '10:00', '2035-04-01', v_room_sched, v_t_sched, 'active'
  ) RETURNING id INTO v_schedule;

  INSERT INTO teaching_session (
    organization_id, class_id, class_schedule_id, teacher_id, room_id,
    occurrence_date, scheduled_start_at, scheduled_end_at, status
  ) VALUES (
    v_org, v_class, v_schedule, v_t_sess, v_room_sess,
    '2035-04-07',
    timestamptz '2035-04-07 11:00:00+07',
    timestamptz '2035-04-07 12:30:00+07',
    'scheduled'
  );

  PERFORM _m4_oc_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT * INTO v_row
  FROM public.list_operational_calendar('2035-04-07', '2035-04-07', v_class, NULL, NULL)
  WHERE entry_type = 'session'
  LIMIT 1;

  PERFORM _m4_oc_record(
    29,
    'session modified values take precedence',
    v_row.teacher_id = v_t_sess
      AND v_row.room_id = v_room_sess
      AND v_row.starts_at = timestamptz '2035-04-07 11:00:00+07'
      AND v_row.ends_at = timestamptz '2035-04-07 12:30:00+07'
  );
END $$;

-- 30: cancelled occurrence is not regenerated as projection
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_class uuid;
  v_teacher uuid;
  v_schedule uuid;
  v_proj integer;
  v_canc integer;
BEGIN
  PERFORM _m4_oc_as_super();
  v_class := _m4_oc_new_class('OC30 No Regen', '2035-05-01', '2035-05-31');
  v_teacher := _m4_oc_new_teacher('OC30');

  INSERT INTO class_schedule (
    organization_id, class_id, weekday_code, start_time, end_time,
    effective_from, teacher_id, status
  ) VALUES (
    v_org, v_class, 'tue', '15:00', '16:00', '2035-05-01', v_teacher, 'active'
  ) RETURNING id INTO v_schedule;

  INSERT INTO teaching_session (
    organization_id, class_id, class_schedule_id, teacher_id,
    occurrence_date, scheduled_start_at, scheduled_end_at, status
  ) VALUES (
    v_org, v_class, v_schedule, v_teacher,
    '2035-05-06',
    timestamptz '2035-05-06 15:00:00+07',
    timestamptz '2035-05-06 16:00:00+07',
    'cancelled'
  );

  PERFORM _m4_oc_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT
    count(*) FILTER (WHERE entry_type = 'projected'),
    count(*) FILTER (WHERE entry_type = 'session' AND session_status = 'cancelled')
  INTO v_proj, v_canc
  FROM public.list_operational_calendar('2035-05-06', '2035-05-06', v_class, NULL, NULL);

  PERFORM _m4_oc_record(30, 'cancelled occurrence not regenerated as projection', v_proj = 0 AND v_canc = 1);
END $$;

-- 22: cross-org filter IDs do not leak data
DO $$
DECLARE
  v_class_b uuid;
  v_failed boolean := false;
BEGIN
  PERFORM _m4_oc_as_super();
  SELECT id INTO v_class_b FROM class
  WHERE organization_id = 'b0000000-0000-4000-8000-000000000001' LIMIT 1;

  IF v_class_b IS NULL THEN
    INSERT INTO class (organization_id, course_id, name, status)
    SELECT 'b0000000-0000-4000-8000-000000000001', c.course_id, 'OC22 B Class', 'active'
    FROM course c WHERE c.organization_id = 'b0000000-0000-4000-8000-000000000001' LIMIT 1
    RETURNING id INTO v_class_b;
  END IF;

  PERFORM _m4_oc_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM 1 FROM public.list_operational_calendar('2034-09-01', '2034-09-07', v_class_b, NULL, NULL);
  EXCEPTION WHEN OTHERS THEN
    v_failed := SQLERRM LIKE '%invalid_class%';
  END;

  PERFORM _m4_oc_record(22, 'cross-org class filter rejected', v_failed AND v_class_b IS NOT NULL);
END $$;

-- Summary
DO $$
DECLARE
  v_total integer;
  v_failed integer;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE result = 'FAIL')
  INTO v_total, v_failed
  FROM _m4_oc_results;

  IF v_failed > 0 THEN
    RAISE EXCEPTION 'M4 operational calendar Tests: % / % passed (% failed)',
      v_total - v_failed, v_total, v_failed;
  END IF;

  RAISE NOTICE 'M4 operational calendar Tests: % / % passed (0 failed)', v_total, v_total;
END $$;

ROLLBACK;
