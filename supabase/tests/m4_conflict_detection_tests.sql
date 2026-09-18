-- M4-T04: Scheduling conflict detection tests.

BEGIN;

CREATE TEMP TABLE _m4_cd_results (
  test_no   integer PRIMARY KEY,
  test_name text NOT NULL,
  result    text NOT NULL CHECK (result IN ('PASS', 'FAIL'))
);

GRANT ALL ON TABLE _m4_cd_results TO authenticated, anon;

CREATE OR REPLACE FUNCTION _m4_cd_record(test_no integer, test_name text, passed boolean)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO _m4_cd_results (test_no, test_name, result)
  VALUES (test_no, test_name, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END);
END;
$$;

CREATE OR REPLACE FUNCTION _m4_cd_expect_fail(test_no integer, test_name text, sql_text text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE sql_text;
    PERFORM _m4_cd_record(test_no, test_name, false);
  EXCEPTION WHEN OTHERS THEN
    PERFORM _m4_cd_record(test_no, test_name, true);
  END;
END;
$$;

CREATE OR REPLACE FUNCTION _m4_cd_as_auth(p_auth_id uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', p_auth_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_auth_id::text, 'role', 'authenticated')::text, true);
END;
$$;

CREATE OR REPLACE FUNCTION _m4_cd_as_super()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
END;
$$;

CREATE OR REPLACE FUNCTION _m4_cd_new_class(p_name text, p_term_start date, p_term_end date)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_id uuid;
BEGIN
  INSERT INTO class (
    organization_id, course_id, name, status, term_start_date, term_end_date
  )
  SELECT v_org, c.course_id, p_name, 'active', p_term_start, p_term_end
  FROM class c WHERE c.organization_id = v_org LIMIT 1
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION _m4_cd_new_teacher(p_label text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
  v_id uuid;
BEGIN
  INSERT INTO teacher (organization_id, given_name, family_name, status)
  VALUES (
    'a0000000-0000-4000-8000-000000000001',
    p_label,
    'CD' || substr(gen_random_uuid()::text, 1, 8),
    'active'
  )
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION _m4_cd_new_room(p_label text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
  v_id uuid;
BEGIN
  INSERT INTO room (organization_id, code, name, status)
  VALUES (
    'a0000000-0000-4000-8000-000000000001',
    'CD-' || substr(gen_random_uuid()::text, 1, 8),
    p_label,
    'active'
  )
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

-- 1: teacher unavailability blocks generation
-- 2030-01-07 is Monday
DO $$
DECLARE
  v_class uuid;
  v_teacher uuid;
  v_schedule uuid;
  v_failed boolean := false;
BEGIN
  PERFORM _m4_cd_as_super();
  v_class := _m4_cd_new_class('CD1 Unavail Gen', '2030-01-01', '2030-03-31');
  v_teacher := _m4_cd_new_teacher('CD1');

  INSERT INTO teacher_unavailability (
    organization_id, teacher_id, block_type,
    weekday_code, start_time, end_time, effective_from, status
  ) VALUES (
    'a0000000-0000-4000-8000-000000000001',
    v_teacher, 'recurring', 'mon', '00:00', '23:59', '2030-01-01', 'active'
  );

  INSERT INTO class_schedule (
    organization_id, class_id, weekday_code, start_time, end_time,
    effective_from, teacher_id, status
  ) VALUES (
    'a0000000-0000-4000-8000-000000000001',
    v_class, 'mon', '18:00', '19:30', '2030-01-01', v_teacher, 'active'
  ) RETURNING id INTO v_schedule;

  PERFORM _m4_cd_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.generate_teaching_sessions(v_schedule, '2030-01-07', '2030-01-07');
  EXCEPTION WHEN OTHERS THEN
    v_failed := SQLERRM LIKE '%teacher_unavailable%';
  END;

  PERFORM _m4_cd_record(1, 'teacher unavailability blocks generation', v_failed);
END $$;

-- 2: teacher availability outside block allows generation
-- 2030-02-05 is Tuesday
DO $$
DECLARE
  v_class uuid;
  v_teacher uuid;
  v_schedule uuid;
  v_inserted integer;
BEGIN
  PERFORM _m4_cd_as_super();
  v_class := _m4_cd_new_class('CD2 Outside Block', '2030-02-01', '2030-03-31');
  v_teacher := _m4_cd_new_teacher('CD2');

  INSERT INTO teacher_unavailability (
    organization_id, teacher_id, block_type,
    weekday_code, start_time, end_time, effective_from, status
  ) VALUES (
    'a0000000-0000-4000-8000-000000000001',
    v_teacher, 'recurring', 'tue', '18:00', '19:30', '2030-02-01', 'active'
  );

  INSERT INTO class_schedule (
    organization_id, class_id, weekday_code, start_time, end_time,
    effective_from, teacher_id, status
  ) VALUES (
    'a0000000-0000-4000-8000-000000000001',
    v_class, 'tue', '20:00', '21:00', '2030-02-01', v_teacher, 'active'
  ) RETURNING id INTO v_schedule;

  PERFORM _m4_cd_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT public.generate_teaching_sessions(v_schedule, '2030-02-05', '2030-02-05') INTO v_inserted;

  PERFORM _m4_cd_record(2, 'teacher availability outside block allows generation', v_inserted >= 1);
END $$;

-- 3: recurring unavailability respected in organization timezone
-- 2030-03-05 is Wednesday
DO $$
DECLARE
  v_class uuid;
  v_teacher uuid;
  v_cnt integer;
BEGIN
  PERFORM _m4_cd_as_super();
  v_class := _m4_cd_new_class('CD3 Recurring TZ', '2030-03-01', '2030-03-31');
  v_teacher := _m4_cd_new_teacher('CD3');

  INSERT INTO teacher_unavailability (
    organization_id, teacher_id, block_type,
    weekday_code, start_time, end_time, effective_from, status
  ) VALUES (
    'a0000000-0000-4000-8000-000000000001',
    v_teacher, 'recurring', 'wed', '18:00', '20:00', '2030-03-01', 'active'
  );

  PERFORM _m4_cd_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_cnt
  FROM public.check_class_schedule_conflicts(
    v_class, 'wed', '18:30'::time, '19:00'::time, '2030-03-01', '2030-03-31', NULL, v_teacher, NULL
  )
  WHERE conflict_type = 'teacher_unavailable';

  PERFORM _m4_cd_record(3, 'recurring unavailability in org timezone', v_cnt >= 1);
END $$;

-- 4: one-off unavailability respected
-- 2030-04-15 is Monday
DO $$
DECLARE
  v_class uuid;
  v_teacher uuid;
  v_cnt integer;
BEGIN
  PERFORM _m4_cd_as_super();
  v_class := _m4_cd_new_class('CD4 One Off', '2030-04-01', '2030-04-30');
  v_teacher := _m4_cd_new_teacher('CD4');

  INSERT INTO teacher_unavailability (
    organization_id, teacher_id, block_type, starts_at, ends_at, status
  ) VALUES (
    'a0000000-0000-4000-8000-000000000001',
    v_teacher, 'one_off',
    timestamptz '2030-04-15 14:00:00+07',
    timestamptz '2030-04-15 16:00:00+07',
    'active'
  );

  PERFORM _m4_cd_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_cnt
  FROM public.check_class_schedule_conflicts(
    v_class, 'mon', '14:30'::time, '15:00'::time, '2030-04-15', '2030-04-15', NULL, v_teacher, NULL
  )
  WHERE conflict_type = 'teacher_unavailable';

  PERFORM _m4_cd_record(4, 'one-off unavailability respected', v_cnt >= 1);
END $$;

-- 5: ended unavailability ignored
DO $$
DECLARE
  v_class uuid;
  v_teacher uuid;
  v_cnt integer;
BEGIN
  PERFORM _m4_cd_as_super();
  v_class := _m4_cd_new_class('CD5 Ended Unavail', '2030-05-01', '2030-05-31');
  v_teacher := _m4_cd_new_teacher('CD5');

  INSERT INTO teacher_unavailability (
    organization_id, teacher_id, block_type,
    weekday_code, start_time, end_time, effective_from, effective_to, status
  ) VALUES (
    'a0000000-0000-4000-8000-000000000001',
    v_teacher, 'recurring', 'thu', '09:00', '17:00',
    '2030-05-01', '2030-05-31', 'ended'
  );

  PERFORM _m4_cd_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_cnt
  FROM public.check_class_schedule_conflicts(
    v_class, 'thu', '10:00'::time, '11:00'::time, '2030-05-01', '2030-05-31', NULL, v_teacher, NULL
  )
  WHERE conflict_type = 'teacher_unavailable';

  PERFORM _m4_cd_record(5, 'ended unavailability ignored', v_cnt = 0);
END $$;

-- 6: teacher double-book conflict detected
DO $$
DECLARE
  v_class uuid;
  v_teacher uuid;
  v_room uuid;
  v_cnt integer;
BEGIN
  PERFORM _m4_cd_as_super();
  v_class := _m4_cd_new_class('CD6 Teacher Double', '2030-06-01', '2030-06-30');
  v_teacher := _m4_cd_new_teacher('CD6');
  v_room := _m4_cd_new_room('CD6 Room');

  INSERT INTO class_schedule (
    organization_id, class_id, weekday_code, start_time, end_time,
    effective_from, room_id, teacher_id, status
  ) VALUES (
    'a0000000-0000-4000-8000-000000000001',
    v_class, 'fri', '10:00', '11:00', '2030-06-01', v_room, v_teacher, 'active'
  );

  PERFORM _m4_cd_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_cnt
  FROM public.check_class_schedule_conflicts(
    v_class, 'fri', '10:30'::time, '11:30'::time, '2030-06-01', '2030-06-30',
    v_room, v_teacher, NULL
  )
  WHERE conflict_type = 'teacher_double_booked';

  PERFORM _m4_cd_record(6, 'teacher double-book conflict detected', v_cnt >= 1);
END $$;

-- 7: room double-book conflict detected
DO $$
DECLARE
  v_class uuid;
  v_teacher uuid;
  v_teacher2 uuid;
  v_room uuid;
  v_cnt integer;
BEGIN
  PERFORM _m4_cd_as_super();
  v_class := _m4_cd_new_class('CD7 Room Double', '2030-07-01', '2030-07-31');
  v_teacher := _m4_cd_new_teacher('CD7A');
  v_teacher2 := _m4_cd_new_teacher('CD7B');
  v_room := _m4_cd_new_room('CD7 Room');

  INSERT INTO class_schedule (
    organization_id, class_id, weekday_code, start_time, end_time,
    effective_from, room_id, teacher_id, status
  ) VALUES (
    'a0000000-0000-4000-8000-000000000001',
    v_class, 'sat', '08:00', '09:00', '2030-07-01', v_room, v_teacher, 'active'
  );

  PERFORM _m4_cd_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_cnt
  FROM public.check_class_schedule_conflicts(
    v_class, 'sat', '08:30'::time, '09:30'::time, '2030-07-01', '2030-07-31',
    v_room, v_teacher2, NULL
  )
  WHERE conflict_type = 'room_double_booked';

  PERFORM _m4_cd_record(7, 'room double-book conflict detected', v_cnt >= 1);
END $$;

-- 8: cancelled session does not conflict
-- 2030-08-10 is Sunday
DO $$
DECLARE
  v_class uuid;
  v_teacher uuid;
  v_room uuid;
  v_schedule uuid;
  v_cnt integer;
BEGIN
  PERFORM _m4_cd_as_super();
  v_class := _m4_cd_new_class('CD8 Cancelled', '2030-08-01', '2030-08-31');
  v_teacher := _m4_cd_new_teacher('CD8');
  v_room := _m4_cd_new_room('CD8 Room');

  INSERT INTO class_schedule (
    organization_id, class_id, weekday_code, start_time, end_time,
    effective_from, room_id, teacher_id, status
  ) VALUES (
    'a0000000-0000-4000-8000-000000000001',
    v_class, 'sun', '08:00', '09:00', '2030-08-10', v_room, v_teacher, 'active'
  ) RETURNING id INTO v_schedule;

  INSERT INTO teaching_session (
    organization_id, class_id, class_schedule_id, teacher_id, room_id,
    occurrence_date, scheduled_start_at, scheduled_end_at, status
  ) VALUES (
    'a0000000-0000-4000-8000-000000000001',
    v_class, v_schedule, v_teacher, v_room,
    '2030-08-10',
    timestamptz '2030-08-10 08:00:00+07',
    timestamptz '2030-08-10 09:00:00+07',
    'cancelled'
  );

  -- End the source timetable so only the cancelled session remains as a candidate blocker.
  UPDATE class_schedule SET status = 'ended', effective_to = '2030-08-10' WHERE id = v_schedule;

  PERFORM _m4_cd_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_cnt
  FROM public.check_class_schedule_conflicts(
    v_class, 'sun', '08:00'::time, '09:00'::time, '2030-08-10', '2030-08-10',
    v_room, v_teacher, NULL
  )
  WHERE conflict_type IN ('teacher_double_booked', 'room_double_booked');

  PERFORM _m4_cd_record(8, 'cancelled session does not conflict', v_cnt = 0);
END $$;

-- 9: ended timetable does not create future recurring conflict
DO $$
DECLARE
  v_class uuid;
  v_teacher uuid;
  v_room uuid;
  v_cnt integer;
BEGIN
  PERFORM _m4_cd_as_super();
  v_class := _m4_cd_new_class('CD9 Ended TT', '2030-09-01', '2030-12-31');
  v_teacher := _m4_cd_new_teacher('CD9');
  v_room := _m4_cd_new_room('CD9 Room');

  INSERT INTO class_schedule (
    organization_id, class_id, weekday_code, start_time, end_time,
    effective_from, effective_to, room_id, teacher_id, status
  ) VALUES (
    'a0000000-0000-4000-8000-000000000001',
    v_class, 'mon', '09:00', '10:00', '2030-09-01', '2030-09-30', v_room, v_teacher, 'ended'
  );

  PERFORM _m4_cd_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_cnt
  FROM public.check_class_schedule_conflicts(
    v_class, 'mon', '09:00'::time, '10:00'::time, '2030-10-01', '2030-10-31',
    v_room, v_teacher, NULL
  )
  WHERE conflict_type IN ('teacher_double_booked', 'room_double_booked');

  PERFORM _m4_cd_record(9, 'ended timetable no future recurring conflict', v_cnt = 0);
END $$;

-- 10: different teachers same room/time → room conflict only
DO $$
DECLARE
  v_class uuid;
  v_teacher uuid;
  v_teacher2 uuid;
  v_room uuid;
  v_types text[];
BEGIN
  PERFORM _m4_cd_as_super();
  v_class := _m4_cd_new_class('CD10 Room Only', '2030-10-01', '2030-10-31');
  v_teacher := _m4_cd_new_teacher('CD10A');
  v_teacher2 := _m4_cd_new_teacher('CD10B');
  v_room := _m4_cd_new_room('CD10 Room');

  INSERT INTO class_schedule (
    organization_id, class_id, weekday_code, start_time, end_time,
    effective_from, room_id, teacher_id, status
  ) VALUES (
    'a0000000-0000-4000-8000-000000000001',
    v_class, 'tue', '14:00', '15:00', '2030-10-01', v_room, v_teacher, 'active'
  );

  PERFORM _m4_cd_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT array_agg(DISTINCT conflict_type ORDER BY conflict_type) INTO v_types
  FROM public.check_class_schedule_conflicts(
    v_class, 'tue', '14:00'::time, '15:00'::time, '2030-10-01', '2030-10-31',
    v_room, v_teacher2, NULL
  );

  PERFORM _m4_cd_record(
    10,
    'different teachers same room room conflict only',
    v_types = ARRAY['room_double_booked']::text[]
  );
END $$;

-- 11: same teacher different rooms/time overlap → teacher conflict only
DO $$
DECLARE
  v_class uuid;
  v_teacher uuid;
  v_room uuid;
  v_room2 uuid;
  v_types text[];
BEGIN
  PERFORM _m4_cd_as_super();
  v_class := _m4_cd_new_class('CD11 Teacher Only', '2030-11-01', '2030-11-30');
  v_teacher := _m4_cd_new_teacher('CD11');
  v_room := _m4_cd_new_room('CD11 Room A');
  v_room2 := _m4_cd_new_room('CD11 Room B');

  INSERT INTO class_schedule (
    organization_id, class_id, weekday_code, start_time, end_time,
    effective_from, room_id, teacher_id, status
  ) VALUES (
    'a0000000-0000-4000-8000-000000000001',
    v_class, 'wed', '10:00', '11:00', '2030-11-01', v_room, v_teacher, 'active'
  );

  PERFORM _m4_cd_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT array_agg(DISTINCT conflict_type ORDER BY conflict_type) INTO v_types
  FROM public.check_class_schedule_conflicts(
    v_class, 'wed', '10:30'::time, '11:30'::time, '2030-11-01', '2030-11-30',
    v_room2, v_teacher, NULL
  );

  PERFORM _m4_cd_record(
    11,
    'same teacher different rooms teacher conflict only',
    v_types = ARRAY['teacher_double_booked']::text[]
  );
END $$;

-- 12: different teacher and room → no conflict
DO $$
DECLARE
  v_class uuid;
  v_teacher uuid;
  v_teacher2 uuid;
  v_room uuid;
  v_room2 uuid;
  v_cnt integer;
BEGIN
  PERFORM _m4_cd_as_super();
  v_class := _m4_cd_new_class('CD12 No Conflict', '2030-12-01', '2030-12-31');
  v_teacher := _m4_cd_new_teacher('CD12A');
  v_teacher2 := _m4_cd_new_teacher('CD12B');
  v_room := _m4_cd_new_room('CD12 Room A');
  v_room2 := _m4_cd_new_room('CD12 Room B');

  INSERT INTO class_schedule (
    organization_id, class_id, weekday_code, start_time, end_time,
    effective_from, room_id, teacher_id, status
  ) VALUES (
    'a0000000-0000-4000-8000-000000000001',
    v_class, 'thu', '16:00', '17:00', '2030-12-01', v_room, v_teacher, 'active'
  );

  PERFORM _m4_cd_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_cnt
  FROM public.check_class_schedule_conflicts(
    v_class, 'thu', '16:00'::time, '17:00'::time, '2030-12-01', '2030-12-31',
    v_room2, v_teacher2, NULL
  );

  PERFORM _m4_cd_record(12, 'different teacher and room no conflict', v_cnt = 0);
END $$;

-- 13: schedule without room skips room conflict
DO $$
DECLARE
  v_class uuid;
  v_teacher uuid;
  v_teacher2 uuid;
  v_room uuid;
  v_cnt integer;
BEGIN
  PERFORM _m4_cd_as_super();
  v_class := _m4_cd_new_class('CD13 No Room', '2031-01-01', '2031-01-31');
  v_teacher := _m4_cd_new_teacher('CD13A');
  v_teacher2 := _m4_cd_new_teacher('CD13B');
  v_room := _m4_cd_new_room('CD13 Room');

  INSERT INTO class_schedule (
    organization_id, class_id, weekday_code, start_time, end_time,
    effective_from, room_id, teacher_id, status
  ) VALUES (
    'a0000000-0000-4000-8000-000000000001',
    v_class, 'fri', '11:00', '12:00', '2031-01-01', v_room, v_teacher, 'active'
  );

  PERFORM _m4_cd_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_cnt
  FROM public.check_class_schedule_conflicts(
    v_class, 'fri', '11:00'::time, '12:00'::time, '2031-01-01', '2031-01-31',
    NULL, v_teacher2, NULL
  )
  WHERE conflict_type = 'room_double_booked';

  PERFORM _m4_cd_record(13, 'schedule without room skips room conflict', v_cnt = 0);
END $$;

-- 14: schedule without explicit teacher resolves unique active primary
DO $$
DECLARE
  v_class uuid;
  v_teacher uuid;
  v_room uuid;
  v_cnt integer;
BEGIN
  PERFORM _m4_cd_as_super();
  v_class := _m4_cd_new_class('CD14 Primary Resolve', '2031-02-01', '2031-06-30');
  v_teacher := _m4_cd_new_teacher('CD14');
  v_room := _m4_cd_new_room('CD14 Room');

  INSERT INTO class_teacher_assignment (
    organization_id, class_id, teacher_id, role_code, effective_from, status
  ) VALUES (
    'a0000000-0000-4000-8000-000000000001',
    v_class, v_teacher, 'primary', '2031-02-01', 'active'
  );

  INSERT INTO class_schedule (
    organization_id, class_id, weekday_code, start_time, end_time,
    effective_from, room_id, teacher_id, status
  ) VALUES (
    'a0000000-0000-4000-8000-000000000001',
    v_class, 'mon', '09:00', '10:00', '2031-02-01', v_room, v_teacher, 'active'
  );

  PERFORM _m4_cd_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_cnt
  FROM public.check_class_schedule_conflicts(
    v_class, 'mon', '09:00'::time, '10:00'::time, '2031-02-01', '2031-02-28',
    v_room, NULL, NULL
  )
  WHERE conflict_type = 'teacher_double_booked';

  PERFORM _m4_cd_record(14, 'null teacher resolves unique primary', v_cnt >= 1);
END $$;

-- 15: assistant is not used as fallback → teacher_not_resolved
DO $$
DECLARE
  v_class uuid;
  v_assistant uuid;
  v_room uuid;
  v_cnt integer;
BEGIN
  PERFORM _m4_cd_as_super();
  v_class := _m4_cd_new_class('CD15 Assistant Skip', '2031-03-01', '2031-06-30');
  v_assistant := _m4_cd_new_teacher('CD15 Assist');
  v_room := _m4_cd_new_room('CD15 Room');

  INSERT INTO class_teacher_assignment (
    organization_id, class_id, teacher_id, role_code, effective_from, status
  ) VALUES (
    'a0000000-0000-4000-8000-000000000001',
    v_class, v_assistant, 'assistant', '2031-03-01', 'active'
  );

  PERFORM _m4_cd_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_cnt
  FROM public.check_class_schedule_conflicts(
    v_class, 'tue', '09:00'::time, '10:00'::time, '2031-03-01', '2031-03-31',
    v_room, NULL, NULL
  )
  WHERE conflict_type = 'teacher_not_resolved';

  PERFORM _m4_cd_record(15, 'assistant not used as fallback', v_cnt >= 1);
END $$;

-- 16: multiple primary fallback reported deterministically
DO $$
DECLARE
  v_class uuid;
  v_t1 uuid;
  v_t2 uuid;
  v_cnt integer;
BEGIN
  PERFORM _m4_cd_as_super();
  v_class := _m4_cd_new_class('CD16 Multi Primary', '2031-04-01', '2031-06-30');
  v_t1 := _m4_cd_new_teacher('CD16A');
  v_t2 := _m4_cd_new_teacher('CD16B');

  INSERT INTO class_teacher_assignment (
    organization_id, class_id, teacher_id, role_code, effective_from, status
  ) VALUES
    ('a0000000-0000-4000-8000-000000000001', v_class, v_t1, 'primary', '2031-04-01', 'active'),
    ('a0000000-0000-4000-8000-000000000001', v_class, v_t2, 'primary', '2031-04-01', 'active');

  PERFORM _m4_cd_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_cnt
  FROM public.check_class_schedule_conflicts(
    v_class, 'wed', '09:00'::time, '10:00'::time, '2031-04-01', '2031-04-30', NULL, NULL, NULL
  )
  WHERE conflict_type = 'multiple_primary_teachers';

  PERFORM _m4_cd_record(16, 'multiple primary reported deterministically', v_cnt >= 1);
END $$;

-- 17: self-edit does not conflict with itself
DO $$
DECLARE
  v_class uuid;
  v_teacher uuid;
  v_room uuid;
  v_schedule uuid;
  v_cnt integer;
BEGIN
  PERFORM _m4_cd_as_super();
  v_class := _m4_cd_new_class('CD17 Self Edit', '2031-05-01', '2031-05-31');
  v_teacher := _m4_cd_new_teacher('CD17');
  v_room := _m4_cd_new_room('CD17 Room');

  INSERT INTO class_schedule (
    organization_id, class_id, weekday_code, start_time, end_time,
    effective_from, room_id, teacher_id, status
  ) VALUES (
    'a0000000-0000-4000-8000-000000000001',
    v_class, 'thu', '13:00', '14:00', '2031-05-01', v_room, v_teacher, 'active'
  ) RETURNING id INTO v_schedule;

  PERFORM _m4_cd_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_cnt
  FROM public.check_class_schedule_conflicts(
    v_class, 'thu', '13:00'::time, '14:00'::time, '2031-05-01', '2031-05-31',
    v_room, v_teacher, v_schedule
  );

  PERFORM _m4_cd_record(17, 'self-edit does not conflict with itself', v_cnt = 0);
END $$;

-- 18: overlapping effective date ranges evaluated correctly
DO $$
DECLARE
  v_class uuid;
  v_teacher uuid;
  v_room uuid;
  v_cnt integer;
BEGIN
  PERFORM _m4_cd_as_super();
  v_class := _m4_cd_new_class('CD18 Overlap Eff', '2031-06-01', '2031-07-31');
  v_teacher := _m4_cd_new_teacher('CD18');
  v_room := _m4_cd_new_room('CD18 Room');

  INSERT INTO class_schedule (
    organization_id, class_id, weekday_code, start_time, end_time,
    effective_from, effective_to, room_id, teacher_id, status
  ) VALUES (
    'a0000000-0000-4000-8000-000000000001',
    v_class, 'fri', '15:00', '16:00', '2031-06-01', '2031-06-30', v_room, v_teacher, 'active'
  );

  PERFORM _m4_cd_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_cnt
  FROM public.check_class_schedule_conflicts(
    v_class, 'fri', '15:00'::time, '16:00'::time, '2031-06-15', '2031-07-15',
    v_room, v_teacher, NULL
  )
  WHERE conflict_type IN ('teacher_double_booked', 'room_double_booked');

  PERFORM _m4_cd_record(18, 'overlapping effective ranges evaluated', v_cnt >= 1);
END $$;

-- 19: non-overlapping effective ranges do not conflict
DO $$
DECLARE
  v_class uuid;
  v_teacher uuid;
  v_room uuid;
  v_cnt integer;
BEGIN
  PERFORM _m4_cd_as_super();
  v_class := _m4_cd_new_class('CD19 Non Overlap', '2031-07-01', '2031-08-31');
  v_teacher := _m4_cd_new_teacher('CD19');
  v_room := _m4_cd_new_room('CD19 Room');

  INSERT INTO class_schedule (
    organization_id, class_id, weekday_code, start_time, end_time,
    effective_from, effective_to, room_id, teacher_id, status
  ) VALUES (
    'a0000000-0000-4000-8000-000000000001',
    v_class, 'sat', '10:00', '11:00', '2031-07-01', '2031-07-31', v_room, v_teacher, 'active'
  );

  PERFORM _m4_cd_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_cnt
  FROM public.check_class_schedule_conflicts(
    v_class, 'sat', '10:00'::time, '11:00'::time, '2031-08-01', '2031-08-31',
    v_room, v_teacher, NULL
  );

  PERFORM _m4_cd_record(19, 'non-overlapping effective ranges no conflict', v_cnt = 0);
END $$;

-- 20: weekday mismatch does not conflict
DO $$
DECLARE
  v_class uuid;
  v_teacher uuid;
  v_room uuid;
  v_cnt integer;
BEGIN
  PERFORM _m4_cd_as_super();
  v_class := _m4_cd_new_class('CD20 Weekday', '2031-08-01', '2031-08-31');
  v_teacher := _m4_cd_new_teacher('CD20');
  v_room := _m4_cd_new_room('CD20 Room');

  INSERT INTO class_schedule (
    organization_id, class_id, weekday_code, start_time, end_time,
    effective_from, room_id, teacher_id, status
  ) VALUES (
    'a0000000-0000-4000-8000-000000000001',
    v_class, 'mon', '09:00', '10:00', '2031-08-01', v_room, v_teacher, 'active'
  );

  PERFORM _m4_cd_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_cnt
  FROM public.check_class_schedule_conflicts(
    v_class, 'tue', '09:00'::time, '10:00'::time, '2031-08-01', '2031-08-31',
    v_room, v_teacher, NULL
  );

  PERFORM _m4_cd_record(20, 'weekday mismatch does not conflict', v_cnt = 0);
END $$;

-- 21: timezone conversion around local schedule is correct
-- 2031-09-03 is Wednesday
DO $$
DECLARE
  v_class uuid;
  v_teacher uuid;
  v_starts timestamptz;
BEGIN
  PERFORM _m4_cd_as_super();
  v_class := _m4_cd_new_class('CD21 TZ', '2031-09-01', '2031-09-30');
  v_teacher := _m4_cd_new_teacher('CD21');

  INSERT INTO teacher_unavailability (
    organization_id, teacher_id, block_type,
    weekday_code, start_time, end_time, effective_from, status
  ) VALUES (
    'a0000000-0000-4000-8000-000000000001',
    v_teacher, 'recurring', 'wed', '18:00', '20:00', '2031-09-01', 'active'
  );

  PERFORM _m4_cd_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT starts_at INTO v_starts
  FROM public.check_class_schedule_conflicts(
    v_class, 'wed', '18:30'::time, '19:00'::time, '2031-09-03', '2031-09-03', NULL, v_teacher, NULL
  )
  WHERE conflict_type = 'teacher_unavailable'
  LIMIT 1;

  PERFORM _m4_cd_record(
    21,
    'timezone conversion around local schedule correct',
    v_starts = timestamptz '2031-09-03 18:30:00+07'
  );
END $$;

-- 22: idempotent generation remains intact
-- 2031-10-02 is Thursday
DO $$
DECLARE
  v_class uuid;
  v_teacher uuid;
  v_schedule uuid;
  v_first integer;
  v_second integer;
  v_count integer;
BEGIN
  PERFORM _m4_cd_as_super();
  v_class := _m4_cd_new_class('CD22 Idempotent', '2031-10-01', '2031-10-31');
  v_teacher := _m4_cd_new_teacher('CD22');

  INSERT INTO class_schedule (
    organization_id, class_id, weekday_code, start_time, end_time,
    effective_from, teacher_id, status
  ) VALUES (
    'a0000000-0000-4000-8000-000000000001',
    v_class, 'thu', '20:00', '21:00', '2031-10-01', v_teacher, 'active'
  ) RETURNING id INTO v_schedule;

  PERFORM _m4_cd_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT public.generate_teaching_sessions(v_schedule, '2031-10-02', '2031-10-02') INTO v_first;
  SELECT public.generate_teaching_sessions(v_schedule, '2031-10-02', '2031-10-02') INTO v_second;

  SELECT count(*) INTO v_count
  FROM teaching_session
  WHERE class_schedule_id = v_schedule AND occurrence_date = '2031-10-02';

  PERFORM _m4_cd_record(
    22,
    'idempotent generation remains intact',
    v_first >= 1 AND v_second = 0 AND v_count = 1
  );
END $$;

-- 23: existing GiST exclusions remain effective
-- 2031-11-07 is Friday
DO $$
DECLARE
  v_class uuid;
  v_teacher uuid;
  v_room uuid;
  v_s1 uuid;
  v_s2 uuid;
  v_failed boolean := false;
BEGIN
  PERFORM _m4_cd_as_super();
  v_class := _m4_cd_new_class('CD23 GiST', '2031-11-01', '2031-11-30');
  v_teacher := _m4_cd_new_teacher('CD23');
  v_room := _m4_cd_new_room('CD23 Room');

  INSERT INTO class_schedule (
    organization_id, class_id, weekday_code, start_time, end_time,
    effective_from, room_id, teacher_id, status
  ) VALUES (
    'a0000000-0000-4000-8000-000000000001',
    v_class, 'fri', '08:00', '09:00', '2031-11-01', v_room, v_teacher, 'active'
  ) RETURNING id INTO v_s1;

  INSERT INTO class_schedule (
    organization_id, class_id, weekday_code, start_time, end_time,
    effective_from, room_id, teacher_id, status
  ) VALUES (
    'a0000000-0000-4000-8000-000000000001',
    v_class, 'fri', '08:30', '09:30', '2031-11-01', v_room, v_teacher, 'active'
  ) RETURNING id INTO v_s2;

  PERFORM _m4_cd_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.generate_teaching_sessions(v_s1, '2031-11-07', '2031-11-07');
  BEGIN
    PERFORM public.generate_teaching_sessions(v_s2, '2031-11-07', '2031-11-07');
  EXCEPTION WHEN OTHERS THEN
    v_failed := SQLERRM LIKE '%schedule_conflict%' OR SQLSTATE = '23P01'
      OR SQLERRM LIKE '%teacher_double_booked%' OR SQLERRM LIKE '%room_double_booked%';
  END;

  PERFORM _m4_cd_record(23, 'GiST exclusions remain effective', v_failed);
END $$;

-- 24: cross-org schedules never interfere
DO $$
DECLARE
  v_class_a uuid;
  v_teacher_a uuid;
  v_teacher_b uuid;
  v_room_b uuid;
  v_cnt integer;
BEGIN
  PERFORM _m4_cd_as_super();
  v_class_a := _m4_cd_new_class('CD24 Cross Org', '2031-12-01', '2031-12-31');
  v_teacher_a := _m4_cd_new_teacher('CD24A');
  SELECT t.id INTO v_teacher_b FROM teacher t
  WHERE t.organization_id = 'b0000000-0000-4000-8000-000000000001' LIMIT 1;
  SELECT r.id INTO v_room_b FROM room r
  WHERE r.organization_id = 'b0000000-0000-4000-8000-000000000001' LIMIT 1;

  IF v_room_b IS NULL THEN
    INSERT INTO room (organization_id, code, name, status)
    VALUES ('b0000000-0000-4000-8000-000000000001', 'B-CD24', 'Org B CD Room', 'active')
    RETURNING id INTO v_room_b;
  END IF;

  IF v_teacher_b IS NULL THEN
    INSERT INTO teacher (organization_id, given_name, family_name, status)
    VALUES ('b0000000-0000-4000-8000-000000000001', 'OrgB', 'CD24', 'active')
    RETURNING id INTO v_teacher_b;
  END IF;

  INSERT INTO class_schedule (
    organization_id, class_id, weekday_code, start_time, end_time,
    effective_from, room_id, teacher_id, status
  )
  SELECT
    'b0000000-0000-4000-8000-000000000001', c.id, 'mon', '09:00', '10:00',
    '2031-12-01', v_room_b, v_teacher_b, 'active'
  FROM class c
  WHERE c.organization_id = 'b0000000-0000-4000-8000-000000000001'
  LIMIT 1;

  PERFORM _m4_cd_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_cnt
  FROM public.check_class_schedule_conflicts(
    v_class_a, 'mon', '09:00'::time, '10:00'::time, '2031-12-01', '2031-12-31',
    v_room_b, v_teacher_a, NULL
  );

  PERFORM _m4_cd_record(24, 'cross-org schedules never interfere', v_cnt = 0);
END $$;

-- 25: preview returns structured conflict information
DO $$
DECLARE
  v_class uuid;
  v_teacher uuid;
  v_room uuid;
  v_row schedule_conflict_entry;
BEGIN
  PERFORM _m4_cd_as_super();
  v_class := _m4_cd_new_class('CD25 Structured', '2032-01-01', '2032-01-31');
  v_teacher := _m4_cd_new_teacher('CD25');
  v_room := _m4_cd_new_room('CD25 Room');

  INSERT INTO class_schedule (
    organization_id, class_id, weekday_code, start_time, end_time,
    effective_from, room_id, teacher_id, status
  ) VALUES (
    'a0000000-0000-4000-8000-000000000001',
    v_class, 'tue', '17:00', '18:00', '2032-01-01', v_room, v_teacher, 'active'
  );

  PERFORM _m4_cd_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT * INTO v_row
  FROM public.check_class_schedule_conflicts(
    v_class, 'tue', '17:00'::time, '18:00'::time, '2032-01-01', '2032-01-31',
    v_room, v_teacher, NULL
  )
  LIMIT 1;

  PERFORM _m4_cd_record(
    25,
    'preview returns structured conflict information',
    v_row.conflict_type IS NOT NULL
      AND v_row.occurrence_date IS NOT NULL
      AND v_row.starts_at IS NOT NULL
      AND v_row.ends_at IS NOT NULL
  );
END $$;

-- 26: open-ended schedule uses bounded evaluation horizon
DO $$
DECLARE
  v_eval_end date;
BEGIN
  PERFORM _m4_cd_as_super();
  SELECT public._schedule_conflict_eval_end('2032-02-01'::date, NULL, NULL) INTO v_eval_end;

  PERFORM _m4_cd_record(
    26,
    'open-ended schedule uses bounded evaluation horizon',
    v_eval_end = '2032-02-01'::date + 179
  );
END $$;

-- 27: closed class behavior remains consistent with T03
SELECT _m4_cd_expect_fail(27, 'closed class rejects new timetable via RPC', $$
  DO $inner$
  DECLARE
    v_class uuid;
  BEGIN
    PERFORM _m4_cd_as_super();
    INSERT INTO class (organization_id, course_id, name, status)
    SELECT 'a0000000-0000-4000-8000-000000000001', c.course_id, 'CD27 Closed', 'closed'
    FROM class c WHERE c.organization_id = 'a0000000-0000-4000-8000-000000000001' LIMIT 1
    RETURNING id INTO v_class;
    PERFORM _m4_cd_as_auth('a1111111-1111-4111-8111-111111111111');
    PERFORM public.create_class_schedule(
      v_class, 'mon', '09:00'::time, '10:00'::time, '2032-03-01', NULL, NULL, NULL
    );
  END $inner$;
$$);

-- 28: materialized session not double-counted against source schedule
-- 2032-04-07 is Wednesday
DO $$
DECLARE
  v_class uuid;
  v_teacher uuid;
  v_room uuid;
  v_schedule uuid;
  v_cnt integer;
BEGIN
  PERFORM _m4_cd_as_super();
  v_class := _m4_cd_new_class('CD28 Dedup', '2032-04-01', '2032-04-30');
  v_teacher := _m4_cd_new_teacher('CD28');
  v_room := _m4_cd_new_room('CD28 Room');

  INSERT INTO class_schedule (
    organization_id, class_id, weekday_code, start_time, end_time,
    effective_from, room_id, teacher_id, status
  ) VALUES (
    'a0000000-0000-4000-8000-000000000001',
    v_class, 'wed', '11:00', '12:00', '2032-04-01', v_room, v_teacher, 'active'
  ) RETURNING id INTO v_schedule;

  INSERT INTO teaching_session (
    organization_id, class_id, class_schedule_id, teacher_id, room_id,
    occurrence_date, scheduled_start_at, scheduled_end_at, status
  ) VALUES (
    'a0000000-0000-4000-8000-000000000001',
    v_class, v_schedule, v_teacher, v_room,
    '2032-04-07',
    timestamptz '2032-04-07 11:00:00+07',
    timestamptz '2032-04-07 12:00:00+07',
    'scheduled'
  );

  PERFORM _m4_cd_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_cnt
  FROM public.check_class_schedule_conflicts(
    v_class, 'wed', '11:00'::time, '12:00'::time, '2032-04-07', '2032-04-07',
    v_room, v_teacher, NULL
  )
  WHERE conflict_type IN ('teacher_double_booked', 'room_double_booked');

  PERFORM _m4_cd_record(28, 'materialized session dedup no double count', v_cnt = 2);
END $$;

-- Summary
DO $$
DECLARE
  v_total integer;
  v_failed integer;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE result = 'FAIL')
  INTO v_total, v_failed
  FROM _m4_cd_results;

  IF v_failed > 0 THEN
    RAISE EXCEPTION 'M4 conflict detection Tests: % / % passed (% failed)',
      v_total - v_failed, v_total, v_failed;
  END IF;

  RAISE NOTICE 'M4 conflict detection Tests: % / % passed (0 failed)', v_total, v_total;
END $$;

ROLLBACK;
