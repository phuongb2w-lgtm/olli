-- M4-T08: Daily operations read-model tests (20).

BEGIN;

CREATE TEMP TABLE _m4_do_results (
  test_no   integer PRIMARY KEY,
  test_name text NOT NULL,
  result    text NOT NULL CHECK (result IN ('PASS', 'FAIL'))
);

GRANT ALL ON TABLE _m4_do_results TO authenticated, anon;

CREATE TEMP TABLE _m4_do_last (
  class_id    uuid,
  teacher_id  uuid,
  room_id     uuid,
  schedule_id uuid,
  session_id  uuid
);

CREATE OR REPLACE FUNCTION _m4_do_record(test_no integer, test_name text, passed boolean)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO _m4_do_results (test_no, test_name, result)
  VALUES (test_no, test_name, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END);
END;
$$;

CREATE OR REPLACE FUNCTION _m4_do_expect_fail(test_no integer, test_name text, sql_text text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE sql_text;
    PERFORM _m4_do_record(test_no, test_name, false);
  EXCEPTION WHEN OTHERS THEN
    PERFORM _m4_do_record(test_no, test_name, true);
  END;
END;
$$;

CREATE OR REPLACE FUNCTION _m4_do_as_auth(p_auth_id uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', p_auth_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_auth_id::text, 'role', 'authenticated')::text, true);
END;
$$;

CREATE OR REPLACE FUNCTION _m4_do_as_super()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
END;
$$;

CREATE OR REPLACE FUNCTION _m4_do_weekday(p_date date)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE EXTRACT(DOW FROM p_date)::int
    WHEN 0 THEN 'sun' WHEN 1 THEN 'mon' WHEN 2 THEN 'tue' WHEN 3 THEN 'wed'
    WHEN 4 THEN 'thu' WHEN 5 THEN 'fri' WHEN 6 THEN 'sat'
  END;
$$;

CREATE OR REPLACE FUNCTION _m4_do_new_class(
  p_name text, p_term_start date, p_term_end date,
  p_org uuid DEFAULT 'a0000000-0000-4000-8000-000000000001'
)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_id uuid;
BEGIN
  INSERT INTO class (organization_id, course_id, name, status, term_start_date, term_end_date)
  SELECT p_org, c.course_id, p_name, 'active', p_term_start, p_term_end
  FROM class c WHERE c.organization_id = p_org LIMIT 1
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION _m4_do_new_teacher(
  p_label text, p_org uuid DEFAULT 'a0000000-0000-4000-8000-000000000001'
)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_id uuid;
BEGIN
  INSERT INTO teacher (organization_id, given_name, family_name, status)
  VALUES (p_org, p_label, 'DO' || substr(gen_random_uuid()::text, 1, 8), 'active')
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION _m4_do_new_room(
  p_label text, p_org uuid DEFAULT 'a0000000-0000-4000-8000-000000000001'
)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_id uuid;
BEGIN
  INSERT INTO room (organization_id, code, name, status)
  VALUES (p_org, 'DO-' || substr(gen_random_uuid()::text, 1, 8), p_label, 'active')
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION _m4_do_make_session(
  p_label text,
  p_occ date DEFAULT '2041-01-07',
  p_start timestamptz DEFAULT timestamptz '2041-01-07 09:00:00+07',
  p_end timestamptz DEFAULT timestamptz '2041-01-07 10:00:00+07',
  p_status text DEFAULT 'scheduled',
  p_org uuid DEFAULT 'a0000000-0000-4000-8000-000000000001',
  p_teacher_id uuid DEFAULT NULL,
  p_room_id uuid DEFAULT NULL
)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
  v_class uuid; v_teacher uuid; v_room uuid; v_schedule uuid; v_session uuid;
  v_wd text := _m4_do_weekday(p_occ);
BEGIN
  v_class := _m4_do_new_class(p_label, p_occ - 7, p_occ + 60, p_org);
  v_teacher := COALESCE(p_teacher_id, _m4_do_new_teacher(p_label || 'T', p_org));
  v_room := COALESCE(p_room_id, _m4_do_new_room(p_label || 'R', p_org));
  INSERT INTO class_schedule (
    organization_id, class_id, weekday_code, start_time, end_time,
    effective_from, room_id, teacher_id, status
  ) VALUES (
    p_org, v_class, v_wd,
    (p_start AT TIME ZONE 'Asia/Ho_Chi_Minh')::time,
    (p_end AT TIME ZONE 'Asia/Ho_Chi_Minh')::time,
    p_occ - 7, v_room, v_teacher, 'active'
  ) RETURNING id INTO v_schedule;
  INSERT INTO teaching_session (
    organization_id, class_id, class_schedule_id, teacher_id, room_id,
    occurrence_date, scheduled_start_at, scheduled_end_at, status
  ) VALUES (
    p_org, v_class, v_schedule, v_teacher, v_room, p_occ, p_start, p_end, p_status
  ) RETURNING id INTO v_session;
  DELETE FROM _m4_do_last;
  INSERT INTO _m4_do_last VALUES (v_class, v_teacher, v_room, v_schedule, v_session);
  RETURN v_session;
END;
$$;

-- 1: materialized session appears on scheduled local day
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_class uuid; v_teacher uuid; v_room uuid; v_schedule uuid; v_session uuid; v_daily integer;
BEGIN
  PERFORM _m4_do_as_super();
  v_class := _m4_do_new_class('DO1 Session', '2041-02-01', '2041-02-28');
  v_teacher := _m4_do_new_teacher('DO1');
  v_room := _m4_do_new_room('DO1 Room');
  INSERT INTO class_schedule (
    organization_id, class_id, weekday_code, start_time, end_time,
    effective_from, room_id, teacher_id, status
  ) VALUES (
    v_org, v_class, 'mon', '09:00', '10:00', '2041-02-01', v_room, v_teacher, 'active'
  ) RETURNING id INTO v_schedule;
  INSERT INTO teaching_session (
    organization_id, class_id, class_schedule_id, teacher_id, room_id,
    occurrence_date, scheduled_start_at, scheduled_end_at, status
  ) VALUES (
    v_org, v_class, v_schedule, v_teacher, v_room,
    '2041-02-03', timestamptz '2041-02-03 09:00:00+07', timestamptz '2041-02-03 10:00:00+07', 'scheduled'
  ) RETURNING id INTO v_session;
  PERFORM _m4_do_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_daily FROM public.list_daily_operations('2041-02-03', v_class, NULL, NULL)
  WHERE entry_type = 'session' AND teaching_session_id = v_session;
  PERFORM _m4_do_record(1, 'materialized session appears on scheduled local day', v_daily = 1);
END $$;

-- 2: session supersedes projection (dedup)
DO $$
DECLARE v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_class uuid; v_teacher uuid; v_room uuid; v_schedule uuid; v_session uuid; v_cnt integer;
BEGIN
  PERFORM _m4_do_as_super();
  v_class := _m4_do_new_class('DO2 Dedup', '2041-03-01', '2041-03-31');
  v_teacher := _m4_do_new_teacher('DO2');
  v_room := _m4_do_new_room('DO2');
  INSERT INTO class_schedule (
    organization_id, class_id, weekday_code, start_time, end_time,
    effective_from, room_id, teacher_id, status
  ) VALUES (v_org, v_class, 'mon', '09:00', '10:00', '2041-03-01', v_room, v_teacher, 'active')
  RETURNING id INTO v_schedule;
  INSERT INTO teaching_session (
    organization_id, class_id, class_schedule_id, teacher_id, room_id,
    occurrence_date, scheduled_start_at, scheduled_end_at, status
  ) VALUES (
    v_org, v_class, v_schedule, v_teacher, v_room,
    '2041-03-03', timestamptz '2041-03-03 09:00:00+07', timestamptz '2041-03-03 10:00:00+07', 'scheduled'
  ) RETURNING id INTO v_session;
  PERFORM _m4_do_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_cnt FROM public.list_daily_operations('2041-03-03', v_class, NULL, NULL);
  PERFORM _m4_do_record(2, 'session supersedes projection dedup', v_cnt = 1);
END $$;

-- 3: completed session
DO $$
DECLARE v_class uuid; v_session uuid; v_cnt integer;
BEGIN
  PERFORM _m4_do_as_super();
  v_session := _m4_do_make_session('DO3', '2041-04-07', timestamptz '2041-04-07 09:00:00+07', timestamptz '2041-04-07 10:00:00+07', 'completed');
  SELECT class_id INTO v_class FROM _m4_do_last;
  PERFORM _m4_do_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_cnt FROM public.list_daily_operations('2041-04-07', v_class, NULL, NULL)
  WHERE entry_type = 'session' AND session_status = 'completed';
  PERFORM _m4_do_record(3, 'completed session', v_cnt = 1);
END $$;

-- 4: in-progress session
DO $$
DECLARE v_class uuid; v_cnt integer;
BEGIN
  PERFORM _m4_do_as_super();
  PERFORM _m4_do_make_session('DO4', '2041-05-05', timestamptz '2041-05-05 09:00:00+07', timestamptz '2041-05-05 10:00:00+07', 'in_progress');
  SELECT class_id INTO v_class FROM _m4_do_last;
  PERFORM _m4_do_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_cnt FROM public.list_daily_operations('2041-05-05', v_class, NULL, NULL)
  WHERE entry_type = 'session' AND session_status = 'in_progress';
  PERFORM _m4_do_record(4, 'in-progress session', v_cnt = 1);
END $$;

-- 5: scheduled session
DO $$
DECLARE v_class uuid; v_cnt integer;
BEGIN
  PERFORM _m4_do_as_super();
  PERFORM _m4_do_make_session('DO5', '2041-06-02', timestamptz '2041-06-02 09:00:00+07', timestamptz '2041-06-02 10:00:00+07', 'scheduled');
  SELECT class_id INTO v_class FROM _m4_do_last;
  PERFORM _m4_do_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_cnt FROM public.list_daily_operations('2041-06-02', v_class, NULL, NULL)
  WHERE entry_type = 'session' AND session_status = 'scheduled';
  PERFORM _m4_do_record(5, 'scheduled session', v_cnt = 1);
END $$;

-- 6: cancelled session
DO $$
DECLARE v_class uuid; v_cnt integer;
BEGIN
  PERFORM _m4_do_as_super();
  PERFORM _m4_do_make_session('DO6', '2041-07-07', timestamptz '2041-07-07 09:00:00+07', timestamptz '2041-07-07 10:00:00+07', 'cancelled');
  SELECT class_id INTO v_class FROM _m4_do_last;
  PERFORM _m4_do_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_cnt FROM public.list_daily_operations('2041-07-07', v_class, NULL, NULL)
  WHERE entry_type = 'session' AND session_status = 'cancelled';
  PERFORM _m4_do_record(6, 'cancelled session', v_cnt = 1);
END $$;

-- 7: projected occurrence
DO $$
DECLARE v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_class uuid; v_teacher uuid; v_cnt integer;
BEGIN
  PERFORM _m4_do_as_super();
  v_class := _m4_do_new_class('DO7 Proj', '2041-08-01', '2041-08-31');
  v_teacher := _m4_do_new_teacher('DO7');
  INSERT INTO class_schedule (
    organization_id, class_id, weekday_code, start_time, end_time,
    effective_from, teacher_id, status
  ) VALUES (v_org, v_class, 'tue', '14:00', '15:00', '2041-08-01', v_teacher, 'active');
  PERFORM _m4_do_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_cnt FROM public.list_daily_operations('2041-08-06', v_class, NULL, NULL)
  WHERE entry_type = 'projected';
  PERFORM _m4_do_record(7, 'projected occurrence', v_cnt = 1);
END $$;

-- 8: unresolved projected teacher
DO $$
DECLARE v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_class uuid; v_cnt integer;
BEGIN
  PERFORM _m4_do_as_super();
  v_class := _m4_do_new_class('DO8 NoTeach', '2040-03-01', '2040-03-31');
  INSERT INTO class_schedule (
    organization_id, class_id, weekday_code, start_time, end_time,
    effective_from, teacher_id, status
  ) VALUES (v_org, v_class, 'tue', '09:00', '10:00', '2040-03-01', NULL, 'active');
  PERFORM _m4_do_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_cnt FROM public.list_daily_operations('2040-03-06', v_class, NULL, NULL)
  WHERE entry_type = 'projected' AND teacher_resolution_status <> 'resolved';
  PERFORM _m4_do_record(8, 'unresolved projected teacher', v_cnt = 1);
END $$;

-- 9: roomless projected occurrence
DO $$
DECLARE v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_class uuid; v_teacher uuid; v_cnt integer;
BEGIN
  PERFORM _m4_do_as_super();
  v_class := _m4_do_new_class('DO9 NoRoom', '2041-10-01', '2041-10-31');
  v_teacher := _m4_do_new_teacher('DO9');
  INSERT INTO class_schedule (
    organization_id, class_id, weekday_code, start_time, end_time,
    effective_from, teacher_id, status
  ) VALUES (v_org, v_class, 'thu', '09:00', '10:00', '2041-10-01', v_teacher, 'active');
  PERFORM _m4_do_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_cnt FROM public.list_daily_operations('2041-10-03', v_class, NULL, NULL)
  WHERE entry_type = 'projected' AND room_id IS NULL;
  PERFORM _m4_do_record(9, 'roomless projected occurrence', v_cnt = 1);
END $$;

-- 10: rescheduled session leaves original day
DO $$
DECLARE v_session uuid; v_class uuid; v_cnt integer;
BEGIN
  PERFORM _m4_do_as_super();
  v_session := _m4_do_make_session('DO10', '2041-11-03');
  SELECT class_id INTO v_class FROM _m4_do_last;
  PERFORM _m4_do_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.reschedule_teaching_session(
    v_session,
    timestamptz '2041-11-10 09:00:00+07',
    timestamptz '2041-11-10 10:00:00+07',
    'move'
  );
  SELECT count(*) INTO v_cnt FROM public.list_daily_operations('2041-11-03', v_class, NULL, NULL)
  WHERE entry_type = 'session' AND teaching_session_id = v_session;
  PERFORM _m4_do_record(10, 'rescheduled session leaves original day', v_cnt = 0);
END $$;

-- 11: rescheduled session appears on new day
DO $$
DECLARE v_session uuid; v_class uuid; v_cnt integer;
BEGIN
  PERFORM _m4_do_as_super();
  v_session := _m4_do_make_session('DO11', '2041-12-01');
  SELECT class_id INTO v_class FROM _m4_do_last;
  PERFORM _m4_do_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.reschedule_teaching_session(
    v_session,
    timestamptz '2041-12-08 09:00:00+07',
    timestamptz '2041-12-08 10:00:00+07',
    'move'
  );
  SELECT count(*) INTO v_cnt FROM public.list_daily_operations('2041-12-08', v_class, NULL, NULL)
  WHERE entry_type = 'session' AND teaching_session_id = v_session;
  PERFORM _m4_do_record(11, 'rescheduled session appears on new day', v_cnt = 1);
END $$;

-- 12: teacher substitution uses current teacher
DO $$
DECLARE v_session uuid; v_class uuid; v_t2 uuid; v_cnt integer;
BEGIN
  PERFORM _m4_do_as_super();
  v_session := _m4_do_make_session('DO12', '2050-03-06',
    timestamptz '2050-03-06 14:00:00+07', timestamptz '2050-03-06 15:00:00+07', 'scheduled');
  SELECT class_id INTO v_class FROM _m4_do_last;
  v_t2 := _m4_do_new_teacher('DO12Sub');
  PERFORM _m4_do_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.substitute_session_teacher(v_session, v_t2, 'sub');
  SELECT count(*) INTO v_cnt FROM public.list_daily_operations('2050-03-06', v_class, NULL, NULL)
  WHERE teaching_session_id = v_session AND teacher_id = v_t2;
  PERFORM _m4_do_record(12, 'teacher substitution uses current teacher', v_cnt = 1);
END $$;

-- 13: room change uses current room
DO $$
DECLARE v_session uuid; v_class uuid; v_r2 uuid; v_cnt integer;
BEGIN
  PERFORM _m4_do_as_super();
  v_session := _m4_do_make_session('DO13', '2050-03-07',
    timestamptz '2050-03-07 14:00:00+07', timestamptz '2050-03-07 15:00:00+07', 'scheduled');
  SELECT class_id INTO v_class FROM _m4_do_last;
  v_r2 := _m4_do_new_room('DO13New');
  PERFORM _m4_do_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.change_session_room(v_session, v_r2, 'move');
  SELECT count(*) INTO v_cnt FROM public.list_daily_operations('2050-03-07', v_class, NULL, NULL)
  WHERE teaching_session_id = v_session AND room_id = v_r2;
  PERFORM _m4_do_record(13, 'room change uses current room', v_cnt = 1);
END $$;

-- 14: cancelled session does not reappear as projection
DO $$
DECLARE v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_class uuid; v_teacher uuid; v_room uuid; v_schedule uuid; v_session uuid;
  v_sess_cnt integer; v_proj_cnt integer;
BEGIN
  PERFORM _m4_do_as_super();
  v_class := _m4_do_new_class('DO14 Cancel', '2042-03-01', '2042-03-31');
  v_teacher := _m4_do_new_teacher('DO14');
  v_room := _m4_do_new_room('DO14');
  INSERT INTO class_schedule (
    organization_id, class_id, weekday_code, start_time, end_time,
    effective_from, room_id, teacher_id, status
  ) VALUES (v_org, v_class, 'mon', '09:00', '10:00', '2042-03-01', v_room, v_teacher, 'active')
  RETURNING id INTO v_schedule;
  INSERT INTO teaching_session (
    organization_id, class_id, class_schedule_id, teacher_id, room_id,
    occurrence_date, scheduled_start_at, scheduled_end_at, status
  ) VALUES (
    v_org, v_class, v_schedule, v_teacher, v_room,
    '2042-03-07', timestamptz '2042-03-07 09:00:00+07', timestamptz '2042-03-07 10:00:00+07', 'cancelled'
  ) RETURNING id INTO v_session;
  PERFORM _m4_do_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_sess_cnt FROM public.list_daily_operations('2042-03-07', v_class, NULL, NULL)
  WHERE entry_type = 'session';
  SELECT count(*) INTO v_proj_cnt FROM public.list_daily_operations('2042-03-07', v_class, NULL, NULL)
  WHERE entry_type = 'projected';
  PERFORM _m4_do_record(14, 'cancelled session does not reappear as projection', v_sess_cnt = 1 AND v_proj_cnt = 0);
END $$;

-- 15-17: cross-org filters rejected
DO $$
DECLARE v_class_b uuid; v_failed boolean := false;
BEGIN
  PERFORM _m4_do_as_super();
  SELECT id INTO v_class_b FROM class
  WHERE organization_id = 'b0000000-0000-4000-8000-000000000001' LIMIT 1;
  IF v_class_b IS NULL THEN
    INSERT INTO class (organization_id, course_id, name, status)
    SELECT 'b0000000-0000-4000-8000-000000000001', c.course_id, 'DO15 B Class', 'active'
    FROM course c WHERE c.organization_id = 'b0000000-0000-4000-8000-000000000001' LIMIT 1
    RETURNING id INTO v_class_b;
  END IF;
  PERFORM _m4_do_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM 1 FROM public.list_daily_operations('2042-04-01', v_class_b, NULL, NULL);
  EXCEPTION WHEN OTHERS THEN
    v_failed := SQLERRM LIKE '%invalid_class%';
  END;
  PERFORM _m4_do_record(15, 'cross-org class filter rejected', v_failed);
END $$;

DO $$
DECLARE v_teacher_b uuid; v_failed boolean := false;
BEGIN
  PERFORM _m4_do_as_super();
  SELECT id INTO v_teacher_b FROM teacher
  WHERE organization_id = 'b0000000-0000-4000-8000-000000000001' LIMIT 1;
  IF v_teacher_b IS NULL THEN
    INSERT INTO teacher (organization_id, given_name, family_name, status)
    VALUES ('b0000000-0000-4000-8000-000000000001', 'DO16', 'TeacherB', 'active')
    RETURNING id INTO v_teacher_b;
  END IF;
  PERFORM _m4_do_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM 1 FROM public.list_daily_operations('2042-04-01', NULL, v_teacher_b, NULL);
  EXCEPTION WHEN OTHERS THEN
    v_failed := SQLERRM LIKE '%invalid_teacher%';
  END;
  PERFORM _m4_do_record(16, 'cross-org teacher filter rejected', v_failed);
END $$;

DO $$
DECLARE v_room_b uuid; v_failed boolean := false;
BEGIN
  PERFORM _m4_do_as_super();
  SELECT id INTO v_room_b FROM room
  WHERE organization_id = 'b0000000-0000-4000-8000-000000000001' LIMIT 1;
  IF v_room_b IS NULL THEN
    INSERT INTO room (organization_id, code, name, status)
    VALUES ('b0000000-0000-4000-8000-000000000001', 'DO17-B', 'DO17 Room', 'active')
    RETURNING id INTO v_room_b;
  END IF;
  PERFORM _m4_do_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM 1 FROM public.list_daily_operations('2042-04-01', NULL, NULL, v_room_b);
  EXCEPTION WHEN OTHERS THEN
    v_failed := SQLERRM LIKE '%invalid_room%';
  END;
  PERFORM _m4_do_record(17, 'cross-org room filter rejected', v_failed);
END $$;

-- 18: empty day for class with no timetable
DO $$
DECLARE v_class uuid; v_cnt integer;
BEGIN
  PERFORM _m4_do_as_super();
  v_class := _m4_do_new_class('DO18 Empty', '2099-01-01', '2099-01-31');
  PERFORM _m4_do_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_cnt FROM public.list_daily_operations('2099-06-15', v_class, NULL, NULL);
  PERFORM _m4_do_record(18, 'empty day', v_cnt = 0);
END $$;

-- 19: zero planning gaps on fully assigned day
DO $$
DECLARE v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_class uuid; v_teacher uuid; v_room uuid; v_gaps record;
BEGIN
  PERFORM _m4_do_as_super();
  v_class := _m4_do_new_class('DO19 Gaps', '2042-06-01', '2042-06-30');
  v_teacher := _m4_do_new_teacher('DO19');
  v_room := _m4_do_new_room('DO19');
  INSERT INTO class_schedule (
    organization_id, class_id, weekday_code, start_time, end_time,
    effective_from, room_id, teacher_id, status
  ) VALUES (v_org, v_class, 'tue', '09:00', '10:00', '2042-06-01', v_room, v_teacher, 'active');
  PERFORM _m4_do_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT * INTO v_gaps FROM public.get_operational_planning_gaps('2042-06-02', '2042-06-02', v_class);
  PERFORM _m4_do_record(19, 'zero planning gaps on fully assigned day',
    v_gaps.unresolved_projected_session_count = 0 AND v_gaps.roomless_projected_session_count = 0);
END $$;

-- 20: invalid null date rejected
DO $$
BEGIN
  PERFORM _m4_do_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM _m4_do_expect_fail(20, 'invalid null date rejected',
    'SELECT 1 FROM public.list_daily_operations(NULL, NULL, NULL, NULL)');
END $$;

DO $$
DECLARE
  v_fail integer;
  r record;
BEGIN
  SELECT count(*) INTO v_fail FROM _m4_do_results WHERE result = 'FAIL';
  IF v_fail > 0 THEN
    FOR r IN SELECT test_no, test_name FROM _m4_do_results WHERE result = 'FAIL' ORDER BY test_no LOOP
      RAISE NOTICE 'FAIL %: %', r.test_no, r.test_name;
    END LOOP;
    RAISE EXCEPTION 'M4-T08 daily operations tests failed: % failure(s)', v_fail;
  END IF;
  RAISE NOTICE 'M4-T08 daily operations: all % tests passed', (SELECT count(*) FROM _m4_do_results);
END $$;

ROLLBACK;
