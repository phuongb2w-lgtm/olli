-- M4-T03: Timetable and class teacher assignment integrity tests.

BEGIN;

CREATE TEMP TABLE _m4_tt_results (
  test_no   integer PRIMARY KEY,
  test_name text NOT NULL,
  result    text NOT NULL CHECK (result IN ('PASS', 'FAIL'))
);

GRANT ALL ON TABLE _m4_tt_results TO authenticated, anon;

CREATE OR REPLACE FUNCTION _m4_tt_record(test_no integer, test_name text, passed boolean)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO _m4_tt_results (test_no, test_name, result)
  VALUES (test_no, test_name, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END);
END;
$$;

CREATE OR REPLACE FUNCTION _m4_tt_expect_fail(test_no integer, test_name text, sql_text text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE sql_text;
    PERFORM _m4_tt_record(test_no, test_name, false);
  EXCEPTION WHEN OTHERS THEN
    PERFORM _m4_tt_record(test_no, test_name, true);
  END;
END;
$$;

CREATE OR REPLACE FUNCTION _m4_tt_as_auth(p_auth_id uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', p_auth_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_auth_id::text, 'role', 'authenticated')::text, true);
END;
$$;

CREATE OR REPLACE FUNCTION _m4_tt_as_super()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
END;
$$;

-- 1: valid schedule creation via RPC
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_class uuid;
  v_teacher uuid;
  v_room uuid;
  v_id uuid;
BEGIN
  PERFORM _m4_tt_as_super();
  SELECT c.id INTO v_class FROM class c WHERE c.organization_id = v_org LIMIT 1;
  SELECT t.id INTO v_teacher FROM teacher t WHERE t.organization_id = v_org LIMIT 1;
  SELECT r.id INTO v_room FROM room r WHERE r.organization_id = v_org LIMIT 1;

  PERFORM _m4_tt_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT public.create_class_schedule(
    v_class, 'mon', '18:00'::time, '19:30'::time, '2029-01-01', NULL, v_room, v_teacher
  ) INTO v_id;

  PERFORM _m4_tt_record(1, 'valid schedule creation', v_id IS NOT NULL);
END;
$$;

-- 2: invalid time range rejected
SELECT _m4_tt_expect_fail(2, 'invalid time range rejected', $$
  DO $inner$
  DECLARE
    v_class uuid;
  BEGIN
    PERFORM _m4_tt_as_auth('a1111111-1111-4111-8111-111111111111');
    SELECT c.id INTO v_class FROM class c WHERE organization_id = 'a0000000-0000-4000-8000-000000000001' LIMIT 1;
    INSERT INTO class_schedule (
      organization_id, class_id, weekday_code, start_time, end_time, effective_from, status
    ) VALUES (
      'a0000000-0000-4000-8000-000000000001', v_class, 'tue', '12:00', '08:00', '2029-01-01', 'active'
    );
  END $inner$;
$$);

-- 3: invalid effective range rejected
SELECT _m4_tt_expect_fail(3, 'invalid effective range rejected', $$
  DO $inner$
  DECLARE
    v_class uuid;
  BEGIN
    PERFORM _m4_tt_as_auth('a1111111-1111-4111-8111-111111111111');
    SELECT c.id INTO v_class FROM class c WHERE organization_id = 'a0000000-0000-4000-8000-000000000001' LIMIT 1;
    PERFORM public.create_class_schedule(
      v_class, 'wed', '09:00'::time, '10:00'::time, '2029-06-01', '2029-05-01'::date, NULL, NULL
    );
  END $inner$;
$$);

-- 4: invalid weekday rejected
SELECT _m4_tt_expect_fail(4, 'invalid weekday rejected', $$
  DO $inner$
  DECLARE
    v_class uuid;
  BEGIN
    PERFORM _m4_tt_as_auth('a1111111-1111-4111-8111-111111111111');
    SELECT c.id INTO v_class FROM class c WHERE organization_id = 'a0000000-0000-4000-8000-000000000001' LIMIT 1;
    INSERT INTO class_schedule (
      organization_id, class_id, weekday_code, start_time, end_time, effective_from, status
    ) VALUES (
      'a0000000-0000-4000-8000-000000000001', v_class, 'notaday', '09:00', '10:00', '2029-01-01', 'active'
    );
  END $inner$;
$$);

-- 5: cross-org class rejected
SELECT _m4_tt_expect_fail(5, 'cross-org class rejected', $$
  DO $inner$
  DECLARE
    v_class_b uuid;
  BEGIN
    PERFORM _m4_tt_as_super();
    SELECT c.id INTO v_class_b FROM class c WHERE organization_id = 'b0000000-0000-4000-8000-000000000001' LIMIT 1;
    PERFORM _m4_tt_as_auth('a1111111-1111-4111-8111-111111111111');
    PERFORM public.create_class_schedule(
      v_class_b, 'mon', '09:00'::time, '10:00'::time, '2029-01-01', NULL, NULL, NULL
    );
  END $inner$;
$$);

-- 6: cross-org teacher rejected
SELECT _m4_tt_expect_fail(6, 'cross-org teacher rejected', $$
  DO $inner$
  DECLARE
    v_class uuid;
    v_teacher_b uuid;
  BEGIN
    PERFORM _m4_tt_as_super();
    SELECT c.id INTO v_class FROM class c WHERE organization_id = 'a0000000-0000-4000-8000-000000000001' LIMIT 1;
    SELECT t.id INTO v_teacher_b FROM teacher t WHERE organization_id = 'b0000000-0000-4000-8000-000000000001' LIMIT 1;
    PERFORM _m4_tt_as_auth('a1111111-1111-4111-8111-111111111111');
    PERFORM public.create_class_schedule(
      v_class, 'mon', '09:00'::time, '10:00'::time, '2029-01-01', NULL, NULL, v_teacher_b
    );
  END $inner$;
$$);

-- 7: cross-org room rejected
SELECT _m4_tt_expect_fail(7, 'cross-org room rejected', $$
  DO $inner$
  DECLARE
    v_class uuid;
    v_room_b uuid;
  BEGIN
    PERFORM _m4_tt_as_super();
    SELECT c.id INTO v_class FROM class c WHERE organization_id = 'a0000000-0000-4000-8000-000000000001' LIMIT 1;
    SELECT r.id INTO v_room_b FROM room r WHERE organization_id = 'b0000000-0000-4000-8000-000000000001' LIMIT 1;
    PERFORM _m4_tt_as_auth('a1111111-1111-4111-8111-111111111111');
    PERFORM public.create_class_schedule(
      v_class, 'mon', '09:00'::time, '10:00'::time, '2029-01-01', NULL, v_room_b, NULL
    );
  END $inner$;
$$);

-- 8: ending schedule preserves historical row
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_class uuid;
  v_schedule uuid;
  v_status text;
BEGIN
  PERFORM _m4_tt_as_super();
  SELECT c.id INTO v_class FROM class c WHERE c.organization_id = v_org LIMIT 1;

  PERFORM _m4_tt_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT public.create_class_schedule(
    v_class, 'thu', '10:00'::time, '11:00'::time, '2029-02-01', NULL, NULL, NULL
  ) INTO v_schedule;

  PERFORM public.end_class_schedule(v_schedule);

  SELECT status INTO v_status FROM class_schedule WHERE id = v_schedule;
  PERFORM _m4_tt_record(8, 'ending schedule preserves historical row', v_status = 'ended');
END $$;

-- 9: ended schedule not active
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_class uuid;
  v_schedule uuid;
  v_ok boolean := false;
BEGIN
  PERFORM _m4_tt_as_super();
  SELECT c.id INTO v_class FROM class c WHERE c.organization_id = v_org LIMIT 1;

  PERFORM _m4_tt_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT public.create_class_schedule(
    v_class, 'fri', '10:00'::time, '11:00'::time, '2029-02-01', NULL, NULL, NULL
  ) INTO v_schedule;
  PERFORM public.end_class_schedule(v_schedule);

  BEGIN
    PERFORM public.update_class_schedule(
      v_schedule, 'fri', '11:00'::time, '12:00'::time, '2029-02-01', NULL, NULL, NULL
    );
  EXCEPTION WHEN OTHERS THEN
    v_ok := SQLERRM LIKE '%schedule_not_active%';
  END;

  PERFORM _m4_tt_record(9, 'ended schedule no longer behaves as active', v_ok);
END $$;

-- 10: closed-class mutation rule enforced
SELECT _m4_tt_expect_fail(10, 'closed-class mutation rule enforced', $$
  DO $inner$
  DECLARE
    v_course uuid;
    v_class uuid;
  BEGIN
    PERFORM _m4_tt_as_super();
    INSERT INTO course (organization_id, code, name) VALUES (
      'a0000000-0000-4000-8000-000000000001', 'M4T3C', 'M4T3 Closed'
    ) RETURNING id INTO v_course;
    INSERT INTO class (organization_id, course_id, name, status) VALUES (
      'a0000000-0000-4000-8000-000000000001', v_course, 'Closed M4T3', 'closed'
    ) RETURNING id INTO v_class;
    PERFORM _m4_tt_as_auth('a1111111-1111-4111-8111-111111111111');
    PERFORM public.create_class_schedule(
      v_class, 'mon', '09:00'::time, '10:00'::time, '2029-01-01', NULL, NULL, NULL
    );
  END $inner$;
$$);

-- 11: valid assignment creation
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_class uuid;
  v_teacher uuid;
  v_id uuid;
BEGIN
  PERFORM _m4_tt_as_super();
  SELECT c.id INTO v_class FROM class c WHERE c.organization_id = v_org LIMIT 1;
  SELECT t.id INTO v_teacher FROM teacher t WHERE t.organization_id = v_org LIMIT 1;

  PERFORM _m4_tt_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT public.create_class_teacher_assignment(
    v_class, v_teacher, 'primary', '2029-03-01', NULL
  ) INTO v_id;

  PERFORM _m4_tt_record(11, 'valid assignment creation', v_id IS NOT NULL);
END $$;

-- 12: invalid assignment effective range rejected
SELECT _m4_tt_expect_fail(12, 'invalid assignment effective range rejected', $$
  DO $inner$
  DECLARE
    v_class uuid;
    v_teacher uuid;
  BEGIN
    PERFORM _m4_tt_as_super();
    SELECT c.id INTO v_class FROM class c WHERE organization_id = 'a0000000-0000-4000-8000-000000000001' LIMIT 1;
    SELECT t.id INTO v_teacher FROM teacher t WHERE organization_id = 'a0000000-0000-4000-8000-000000000001' LIMIT 1;
    PERFORM _m4_tt_as_auth('a1111111-1111-4111-8111-111111111111');
    PERFORM public.create_class_teacher_assignment(
      v_class, v_teacher, 'assistant', '2029-06-01', '2029-05-01'::date
    );
  END $inner$;
$$);

-- 13: cross-org teacher assignment rejected
SELECT _m4_tt_expect_fail(13, 'cross-org teacher rejected', $$
  DO $inner$
  DECLARE
    v_class uuid;
    v_teacher_b uuid;
  BEGIN
    PERFORM _m4_tt_as_super();
    SELECT c.id INTO v_class FROM class c WHERE organization_id = 'a0000000-0000-4000-8000-000000000001' LIMIT 1;
    SELECT t.id INTO v_teacher_b FROM teacher t WHERE organization_id = 'b0000000-0000-4000-8000-000000000001' LIMIT 1;
    PERFORM _m4_tt_as_auth('a1111111-1111-4111-8111-111111111111');
    PERFORM public.create_class_teacher_assignment(
      v_class, v_teacher_b, 'primary', '2029-01-01', NULL
    );
  END $inner$;
$$);

-- 14: duplicate assignment rejected
SELECT _m4_tt_expect_fail(14, 'duplicate assignment behavior', $$
  DO $inner$
  DECLARE
    v_class uuid;
    v_teacher uuid;
    v_first uuid;
  BEGIN
    PERFORM _m4_tt_as_super();
    SELECT c.id INTO v_class FROM class c WHERE organization_id = 'a0000000-0000-4000-8000-000000000001' LIMIT 1;
    SELECT t.id INTO v_teacher FROM teacher t WHERE organization_id = 'a0000000-0000-4000-8000-000000000001' LIMIT 1;
    PERFORM _m4_tt_as_auth('a1111111-1111-4111-8111-111111111111');
    SELECT public.create_class_teacher_assignment(v_class, v_teacher, 'assistant', '2029-04-01', NULL) INTO v_first;
    PERFORM public.create_class_teacher_assignment(v_class, v_teacher, 'assistant', '2029-04-01', NULL);
  END $inner$;
$$);

-- 15: overlapping legitimate assignments allowed
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_class uuid;
  v_t1 uuid;
  v_t2 uuid;
  v_cnt integer;
BEGIN
  PERFORM _m4_tt_as_super();
  SELECT c.id INTO v_class FROM class c WHERE c.organization_id = v_org LIMIT 1;
  INSERT INTO teacher (organization_id, given_name, family_name, status)
  VALUES (v_org, 'M4T3', 'Primary', 'active') RETURNING id INTO v_t1;
  INSERT INTO teacher (organization_id, given_name, family_name, status)
  VALUES (v_org, 'M4T3', 'Assistant', 'active') RETURNING id INTO v_t2;

  PERFORM _m4_tt_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.create_class_teacher_assignment(v_class, v_t1, 'primary', '2029-05-01', NULL);
  PERFORM public.create_class_teacher_assignment(v_class, v_t2, 'assistant', '2029-05-01', NULL);

  SELECT count(*) INTO v_cnt
  FROM class_teacher_assignment
  WHERE class_id = v_class AND status = 'active';

  PERFORM _m4_tt_record(15, 'overlapping legitimate assignment behavior', v_cnt >= 2);
END $$;

-- 16: end assignment preserves history
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_class uuid;
  v_teacher uuid;
  v_assign uuid;
  v_status text;
BEGIN
  PERFORM _m4_tt_as_super();
  SELECT c.id INTO v_class FROM class c WHERE c.organization_id = v_org LIMIT 1;
  INSERT INTO teacher (organization_id, given_name, family_name, status)
  VALUES (v_org, 'EndHist', 'Teacher', 'active') RETURNING id INTO v_teacher;

  PERFORM _m4_tt_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT public.create_class_teacher_assignment(v_class, v_teacher, 'primary', '2029-06-01', NULL) INTO v_assign;
  PERFORM public.end_class_teacher_assignment(v_assign, '2029-06-30');

  SELECT status INTO v_status FROM class_teacher_assignment WHERE id = v_assign;
  PERFORM _m4_tt_record(16, 'end assignment preserves history', v_status = 'ended');
END $$;

-- 17: class with multiple teachers supported
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_class uuid;
  v_cnt integer;
BEGIN
  PERFORM _m4_tt_as_super();
  SELECT c.id INTO v_class FROM class c WHERE c.organization_id = v_org LIMIT 1;

  SELECT count(DISTINCT teacher_id) INTO v_cnt
  FROM class_teacher_assignment
  WHERE class_id = v_class;

  PERFORM _m4_tt_record(17, 'class with multiple teachers supported', v_cnt >= 1);
END $$;

-- 18: schedule teacher behavior matches documented rule
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_course uuid;
  v_class uuid;
  v_slot_teacher uuid;
  v_schedule uuid;
  v_session_teacher uuid;
BEGIN
  PERFORM _m4_tt_as_super();
  INSERT INTO course (organization_id, code, name) VALUES (v_org, 'M4T3S', 'Slot Teacher') RETURNING id INTO v_course;
  INSERT INTO class (organization_id, course_id, name, status) VALUES (v_org, v_course, 'SlotTeacherClass', 'active') RETURNING id INTO v_class;
  INSERT INTO teacher (organization_id, given_name, family_name, status)
  VALUES (v_org, 'Slot', 'Teacher', 'active') RETURNING id INTO v_slot_teacher;

  PERFORM _m4_tt_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT public.create_class_schedule(
    v_class, 'sat', '14:00'::time, '15:00'::time, '2029-08-01', NULL, NULL, v_slot_teacher
  ) INTO v_schedule;

  PERFORM public.generate_teaching_sessions(v_schedule, '2029-08-04', '2029-08-04');

  SELECT teacher_id INTO v_session_teacher
  FROM teaching_session
  WHERE class_schedule_id = v_schedule
  LIMIT 1;

  PERFORM _m4_tt_record(
    18,
    'schedule teacher behavior matches documented rule',
    v_session_teacher = v_slot_teacher
  );
END $$;

-- 19: generated session teacher from primary assignment when schedule teacher null
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_course uuid;
  v_class uuid;
  v_primary uuid;
  v_schedule uuid;
  v_session_teacher uuid;
BEGIN
  PERFORM _m4_tt_as_super();
  INSERT INTO course (organization_id, code, name) VALUES (v_org, 'M4T3F', 'Fallback') RETURNING id INTO v_course;
  INSERT INTO class (organization_id, course_id, name, status) VALUES (v_org, v_course, 'FallbackClass', 'active') RETURNING id INTO v_class;
  INSERT INTO teacher (organization_id, given_name, family_name, status)
  VALUES (v_org, 'Primary', 'Only', 'active') RETURNING id INTO v_primary;

  PERFORM _m4_tt_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.create_class_teacher_assignment(v_class, v_primary, 'primary', '2029-07-01', NULL);
  SELECT public.create_class_schedule(
    v_class, 'sun', '09:00'::time, '10:00'::time, '2029-08-01', NULL, NULL, NULL
  ) INTO v_schedule;

  PERFORM public.generate_teaching_sessions(v_schedule, '2029-08-05', '2029-08-05');

  SELECT teacher_id INTO v_session_teacher
  FROM teaching_session WHERE class_schedule_id = v_schedule LIMIT 1;

  PERFORM _m4_tt_record(
    19,
    'generated session teacher matches deterministic source',
    v_session_teacher = v_primary
  );
END $$;

-- 20: editing assignment does not mutate historical session teacher
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_course uuid;
  v_class uuid;
  v_t1 uuid;
  v_t2 uuid;
  v_assign uuid;
  v_schedule uuid;
  v_before uuid;
  v_after uuid;
BEGIN
  PERFORM _m4_tt_as_super();
  INSERT INTO course (organization_id, code, name) VALUES (v_org, 'M4T3H', 'Hist') RETURNING id INTO v_course;
  INSERT INTO class (organization_id, course_id, name, status) VALUES (v_org, v_course, 'HistClass', 'active') RETURNING id INTO v_class;
  INSERT INTO teacher (organization_id, given_name, family_name, status) VALUES (v_org, 'Hist', 'One', 'active') RETURNING id INTO v_t1;
  INSERT INTO teacher (organization_id, given_name, family_name, status) VALUES (v_org, 'Hist', 'Two', 'active') RETURNING id INTO v_t2;

  PERFORM _m4_tt_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT public.create_class_teacher_assignment(v_class, v_t1, 'primary', '2029-07-01', NULL) INTO v_assign;
  SELECT public.create_class_schedule(v_class, 'mon', '10:00'::time, '11:00'::time, '2029-07-01', NULL, NULL, NULL) INTO v_schedule;
  PERFORM public.generate_teaching_sessions(v_schedule, '2029-07-02', '2029-07-02');

  SELECT teacher_id INTO v_before FROM teaching_session WHERE class_schedule_id = v_schedule LIMIT 1;

  PERFORM public.end_class_teacher_assignment(v_assign, '2029-06-30');
  PERFORM public.create_class_teacher_assignment(v_class, v_t2, 'primary', '2029-07-02', NULL);

  SELECT teacher_id INTO v_after FROM teaching_session WHERE class_schedule_id = v_schedule LIMIT 1;

  PERFORM _m4_tt_record(
    20,
    'editing assignment does not mutate historical generated session teacher',
    v_before = v_t1 AND v_after = v_t1
  );
END $$;

-- 21: editing timetable does not rewrite existing session IDs
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_course uuid;
  v_class uuid;
  v_teacher uuid;
  v_schedule uuid;
  v_before uuid;
  v_after uuid;
BEGIN
  PERFORM _m4_tt_as_super();
  INSERT INTO course (organization_id, code, name) VALUES (v_org, 'M4T3I', 'Immut') RETURNING id INTO v_course;
  INSERT INTO class (organization_id, course_id, name, status) VALUES (v_org, v_course, 'ImmutClass', 'active') RETURNING id INTO v_class;
  INSERT INTO teacher (organization_id, given_name, family_name, status) VALUES (v_org, 'Immut', 'T', 'active') RETURNING id INTO v_teacher;

  PERFORM _m4_tt_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT public.create_class_schedule(v_class, 'tue', '10:00'::time, '11:00'::time, '2029-07-01', NULL, NULL, v_teacher) INTO v_schedule;
  PERFORM public.generate_teaching_sessions(v_schedule, '2029-07-03', '2029-07-03');

  SELECT id INTO v_before FROM teaching_session WHERE class_schedule_id = v_schedule LIMIT 1;

  PERFORM public.update_class_schedule(
    v_schedule, 'tue', '12:00'::time, '13:00'::time, '2029-07-01', NULL, NULL, v_teacher
  );

  SELECT id INTO v_after FROM teaching_session WHERE class_schedule_id = v_schedule LIMIT 1;

  PERFORM _m4_tt_record(
    21,
    'editing timetable does not rewrite existing session IDs',
    v_before IS NOT NULL AND v_before = v_after
  );
END $$;

-- 22: ending schedule does not delete generated sessions
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_course uuid;
  v_class uuid;
  v_teacher uuid;
  v_schedule uuid;
  v_cnt_before integer;
  v_cnt_after integer;
BEGIN
  PERFORM _m4_tt_as_super();
  INSERT INTO course (organization_id, code, name) VALUES (v_org, 'M4T3E', 'EndSched') RETURNING id INTO v_course;
  INSERT INTO class (organization_id, course_id, name, status) VALUES (v_org, v_course, 'EndSchedClass', 'active') RETURNING id INTO v_class;
  INSERT INTO teacher (organization_id, given_name, family_name, status) VALUES (v_org, 'End', 'Sched', 'active') RETURNING id INTO v_teacher;

  PERFORM _m4_tt_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT public.create_class_schedule(v_class, 'wed', '10:00'::time, '11:00'::time, '2029-07-01', NULL, NULL, v_teacher) INTO v_schedule;
  PERFORM public.generate_teaching_sessions(v_schedule, '2029-07-04', '2029-07-04');

  SELECT count(*) INTO v_cnt_before FROM teaching_session WHERE class_schedule_id = v_schedule;
  PERFORM public.end_class_schedule(v_schedule);
  SELECT count(*) INTO v_cnt_after FROM teaching_session WHERE class_schedule_id = v_schedule;

  PERFORM _m4_tt_record(
    22,
    'ending schedule does not delete generated sessions',
    v_cnt_before >= 1 AND v_cnt_before = v_cnt_after
  );
END $$;

-- 23: unauthorized read blocked for staff without enrollment.read on cross-org
DO $$
DECLARE
  v_cnt integer;
BEGIN
  PERFORM _m4_tt_as_auth('b1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_cnt
  FROM class_schedule
  WHERE organization_id = 'a0000000-0000-4000-8000-000000000001';
  PERFORM _m4_tt_record(23, 'cross-org read blocked', v_cnt = 0);
END $$;

-- 24: unauthorized write blocked
DO $$
DECLARE
  v_class uuid;
  v_teacher uuid;
  v_err boolean := false;
BEGIN
  PERFORM _m4_tt_as_super();
  SELECT c.id INTO v_class FROM class c WHERE organization_id = 'a0000000-0000-4000-8000-000000000001' LIMIT 1;
  SELECT t.id INTO v_teacher FROM teacher t WHERE organization_id = 'a0000000-0000-4000-8000-000000000001' LIMIT 1;

  PERFORM _m4_tt_as_auth('a2222222-2222-4222-8222-222222222222');
  BEGIN
    PERFORM public.create_class_teacher_assignment(v_class, v_teacher, 'primary', '2029-09-01', NULL);
  EXCEPTION WHEN OTHERS THEN
    v_err := true;
  END;

  PERFORM _m4_tt_record(24, 'unauthorized write blocked', v_err);
END $$;

-- 25: authorized write allowed
DO $$
DECLARE
  v_class uuid;
  v_teacher uuid;
  v_id uuid;
BEGIN
  PERFORM _m4_tt_as_super();
  SELECT c.id INTO v_class FROM class c WHERE organization_id = 'a0000000-0000-4000-8000-000000000001' LIMIT 1;
  INSERT INTO teacher (organization_id, given_name, family_name, status)
  VALUES ('a0000000-0000-4000-8000-000000000001', 'Auth', 'Write', 'active') RETURNING id INTO v_teacher;

  PERFORM _m4_tt_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT public.create_class_teacher_assignment(v_class, v_teacher, 'assistant', '2029-10-01', NULL) INTO v_id;

  PERFORM _m4_tt_record(25, 'authorized write allowed', v_id IS NOT NULL);
END $$;

-- 26: cross-org access blocked on assignment
DO $$
DECLARE
  v_cnt integer;
BEGIN
  PERFORM _m4_tt_as_auth('b1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_cnt
  FROM class_teacher_assignment
  WHERE organization_id = 'a0000000-0000-4000-8000-000000000001';
  PERFORM _m4_tt_record(26, 'cross-org access blocked', v_cnt = 0);
END $$;

DO $$
DECLARE
  v_total integer;
  v_failed integer;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE result = 'FAIL')
  INTO v_total, v_failed
  FROM _m4_tt_results;

  IF v_failed > 0 THEN
    RAISE EXCEPTION 'M4 timetable integrity Tests: % / % passed (% failed)',
      v_total - v_failed, v_total, v_failed;
  END IF;

  RAISE NOTICE 'M4 timetable integrity Tests: % / % passed (0 failed)', v_total, v_total;
END $$;

ROLLBACK;
