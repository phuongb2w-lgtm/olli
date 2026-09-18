-- M4-T06: Session reschedule / cancel / substitute / room change tests (44).

BEGIN;

CREATE TEMP TABLE _m4_sm_results (
  test_no   integer PRIMARY KEY,
  test_name text NOT NULL,
  result    text NOT NULL CHECK (result IN ('PASS', 'FAIL'))
);

GRANT ALL ON TABLE _m4_sm_results TO authenticated, anon;

CREATE TEMP TABLE _m4_sm_last (
  class_id    uuid,
  teacher_id  uuid,
  room_id     uuid,
  schedule_id uuid,
  session_id  uuid
);

CREATE OR REPLACE FUNCTION _m4_sm_record(test_no integer, test_name text, passed boolean)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO _m4_sm_results (test_no, test_name, result)
  VALUES (test_no, test_name, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END);
END;
$$;

CREATE OR REPLACE FUNCTION _m4_sm_expect_fail(test_no integer, test_name text, sql_text text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE sql_text;
    PERFORM _m4_sm_record(test_no, test_name, false);
  EXCEPTION WHEN OTHERS THEN
    PERFORM _m4_sm_record(test_no, test_name, true);
  END;
END;
$$;

CREATE OR REPLACE FUNCTION _m4_sm_as_auth(p_auth_id uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', p_auth_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_auth_id::text, 'role', 'authenticated')::text, true);
END;
$$;

CREATE OR REPLACE FUNCTION _m4_sm_as_super()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
END;
$$;

CREATE OR REPLACE FUNCTION _m4_sm_weekday(p_date date)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE EXTRACT(DOW FROM p_date)::int
    WHEN 0 THEN 'sun'
    WHEN 1 THEN 'mon'
    WHEN 2 THEN 'tue'
    WHEN 3 THEN 'wed'
    WHEN 4 THEN 'thu'
    WHEN 5 THEN 'fri'
    WHEN 6 THEN 'sat'
  END;
$$;

CREATE OR REPLACE FUNCTION _m4_sm_new_class(
  p_name text,
  p_term_start date,
  p_term_end date,
  p_org uuid DEFAULT 'a0000000-0000-4000-8000-000000000001'
)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
  v_id uuid;
BEGIN
  INSERT INTO class (organization_id, course_id, name, status, term_start_date, term_end_date)
  SELECT p_org, c.course_id, p_name, 'active', p_term_start, p_term_end
  FROM class c WHERE c.organization_id = p_org LIMIT 1
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION _m4_sm_new_teacher(
  p_label text,
  p_org uuid DEFAULT 'a0000000-0000-4000-8000-000000000001'
)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
  v_id uuid;
BEGIN
  INSERT INTO teacher (organization_id, given_name, family_name, status)
  VALUES (p_org, p_label, 'SM' || substr(gen_random_uuid()::text, 1, 8), 'active')
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION _m4_sm_new_room(
  p_label text,
  p_org uuid DEFAULT 'a0000000-0000-4000-8000-000000000001',
  p_status text DEFAULT 'active'
)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
  v_id uuid;
BEGIN
  INSERT INTO room (organization_id, code, name, status)
  VALUES (p_org, 'SM-' || substr(gen_random_uuid()::text, 1, 8), p_label, p_status)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

-- Creates class/teacher/room/schedule/session as current (super) role; stores in _m4_sm_last.
CREATE OR REPLACE FUNCTION _m4_sm_make_session(
  p_label text,
  p_occ date DEFAULT '2037-01-05',
  p_start timestamptz DEFAULT timestamptz '2037-01-05 09:00:00+07',
  p_end timestamptz DEFAULT timestamptz '2037-01-05 10:00:00+07',
  p_status text DEFAULT 'scheduled',
  p_org uuid DEFAULT 'a0000000-0000-4000-8000-000000000001',
  p_teacher_id uuid DEFAULT NULL,
  p_room_id uuid DEFAULT NULL
)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
  v_class uuid;
  v_teacher uuid;
  v_room uuid;
  v_schedule uuid;
  v_session uuid;
  v_wd text := _m4_sm_weekday(p_occ);
BEGIN
  v_class := _m4_sm_new_class(p_label, p_occ - 7, p_occ + 60, p_org);
  v_teacher := COALESCE(p_teacher_id, _m4_sm_new_teacher(p_label, p_org));
  v_room := COALESCE(p_room_id, _m4_sm_new_room(p_label || ' Room', p_org));

  INSERT INTO class_schedule (
    organization_id, class_id, weekday_code, start_time, end_time,
    effective_from, room_id, teacher_id, status
  ) VALUES (
    p_org, v_class, v_wd, (p_start AT TIME ZONE 'Asia/Ho_Chi_Minh')::time,
    (p_end AT TIME ZONE 'Asia/Ho_Chi_Minh')::time,
    p_occ - 7, v_room, v_teacher, 'active'
  ) RETURNING id INTO v_schedule;

  INSERT INTO teaching_session (
    organization_id, class_id, class_schedule_id, teacher_id, room_id,
    occurrence_date, scheduled_start_at, scheduled_end_at, status
  ) VALUES (
    p_org, v_class, v_schedule, v_teacher, v_room,
    p_occ, p_start, p_end, p_status
  ) RETURNING id INTO v_session;

  DELETE FROM _m4_sm_last;
  INSERT INTO _m4_sm_last (class_id, teacher_id, room_id, schedule_id, session_id)
  VALUES (v_class, v_teacher, v_room, v_schedule, v_session);

  RETURN v_session;
END;
$$;

-- =============================================================================
-- 1–13 RESCHEDULE
-- =============================================================================

-- 1: reschedule scheduled session succeeds
DO $$
DECLARE
  v_session uuid;
  v_ok boolean := false;
BEGIN
  PERFORM _m4_sm_as_super();
  v_session := _m4_sm_make_session('SM1 Reschedule');

  PERFORM _m4_sm_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.reschedule_teaching_session(
      v_session,
      timestamptz '2037-01-05 11:00:00+07',
      timestamptz '2037-01-05 12:00:00+07',
      'Moved to later morning'
    );
    v_ok := true;
  EXCEPTION WHEN OTHERS THEN
    v_ok := false;
  END;

  PERFORM _m4_sm_record(1, 'reschedule scheduled session succeeds', v_ok);
END $$;

-- 2: reschedule records history
DO $$
DECLARE
  v_session uuid;
  v_cnt integer;
BEGIN
  PERFORM _m4_sm_as_super();
  v_session := _m4_sm_make_session('SM2 History');

  PERFORM _m4_sm_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.reschedule_teaching_session(
    v_session,
    timestamptz '2037-01-05 13:00:00+07',
    timestamptz '2037-01-05 14:00:00+07',
    'Record history'
  );

  SELECT count(*) INTO v_cnt
  FROM public.list_teaching_session_changes(v_session)
  WHERE change_type = 'rescheduled';

  PERFORM _m4_sm_record(2, 'reschedule records history', v_cnt = 1);
END $$;

-- 3: previous/new timestamps correct
DO $$
DECLARE
  v_session uuid;
  v_row record;
BEGIN
  PERFORM _m4_sm_as_super();
  v_session := _m4_sm_make_session(
    'SM3 Timestamps',
    '2037-01-05',
    timestamptz '2037-01-05 09:00:00+07',
    timestamptz '2037-01-05 10:00:00+07'
  );

  PERFORM _m4_sm_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.reschedule_teaching_session(
    v_session,
    timestamptz '2037-01-05 15:00:00+07',
    timestamptz '2037-01-05 16:30:00+07',
    'Timestamp check'
  );

  SELECT * INTO v_row
  FROM public.list_teaching_session_changes(v_session)
  WHERE change_type = 'rescheduled'
  LIMIT 1;

  PERFORM _m4_sm_record(
    3,
    'previous/new timestamps correct',
    v_row.previous_scheduled_start_at = timestamptz '2037-01-05 09:00:00+07'
      AND v_row.previous_scheduled_end_at = timestamptz '2037-01-05 10:00:00+07'
      AND v_row.new_scheduled_start_at = timestamptz '2037-01-05 15:00:00+07'
      AND v_row.new_scheduled_end_at = timestamptz '2037-01-05 16:30:00+07'
  );
END $$;

-- 4: reschedule to unavailable teacher interval rejected
DO $$
DECLARE
  v_session uuid;
  v_teacher uuid;
  v_failed boolean := false;
BEGIN
  PERFORM _m4_sm_as_super();
  v_session := _m4_sm_make_session('SM4 Unavail');
  SELECT teacher_id INTO v_teacher FROM _m4_sm_last;

  INSERT INTO teacher_unavailability (
    organization_id, teacher_id, block_type,
    starts_at, ends_at, status
  ) VALUES (
    'a0000000-0000-4000-8000-000000000001',
    v_teacher, 'one_off',
    timestamptz '2037-01-06 09:00:00+07',
    timestamptz '2037-01-06 12:00:00+07',
    'active'
  );

  PERFORM _m4_sm_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.reschedule_teaching_session(
      v_session,
      timestamptz '2037-01-06 09:00:00+07',
      timestamptz '2037-01-06 10:00:00+07',
      'Into unavailability'
    );
  EXCEPTION WHEN OTHERS THEN
    v_failed := SQLERRM LIKE '%teacher_unavailable%';
  END;

  PERFORM _m4_sm_record(4, 'reschedule to unavailable teacher interval rejected', v_failed);
END $$;

-- 5: reschedule teacher overlap rejected
DO $$
DECLARE
  v_session uuid;
  v_teacher uuid;
  v_class2 uuid;
  v_room2 uuid;
  v_failed boolean := false;
BEGIN
  PERFORM _m4_sm_as_super();
  v_session := _m4_sm_make_session('SM5 Teacher Overlap');
  SELECT teacher_id INTO v_teacher FROM _m4_sm_last;

  v_class2 := _m4_sm_new_class('SM5 Other', '2037-01-01', '2037-03-31');
  v_room2 := _m4_sm_new_room('SM5 Other Room');
  INSERT INTO teaching_session (
    organization_id, class_id, teacher_id, room_id,
    scheduled_start_at, scheduled_end_at, status
  ) VALUES (
    'a0000000-0000-4000-8000-000000000001',
    v_class2, v_teacher, v_room2,
    timestamptz '2037-01-06 09:00:00+07',
    timestamptz '2037-01-06 10:00:00+07',
    'scheduled'
  );

  PERFORM _m4_sm_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.reschedule_teaching_session(
      v_session,
      timestamptz '2037-01-06 09:00:00+07',
      timestamptz '2037-01-06 10:00:00+07',
      'Teacher double'
    );
  EXCEPTION WHEN OTHERS THEN
    v_failed := SQLERRM LIKE '%teacher_double_booked%';
  END;

  PERFORM _m4_sm_record(5, 'reschedule teacher overlap rejected', v_failed);
END $$;

-- 6: reschedule room overlap rejected
DO $$
DECLARE
  v_session uuid;
  v_room uuid;
  v_class2 uuid;
  v_teacher2 uuid;
  v_failed boolean := false;
BEGIN
  PERFORM _m4_sm_as_super();
  v_session := _m4_sm_make_session('SM6 Room Overlap');
  SELECT room_id INTO v_room FROM _m4_sm_last;

  v_class2 := _m4_sm_new_class('SM6 Other', '2037-01-01', '2037-03-31');
  v_teacher2 := _m4_sm_new_teacher('SM6 Other');
  INSERT INTO teaching_session (
    organization_id, class_id, teacher_id, room_id,
    scheduled_start_at, scheduled_end_at, status
  ) VALUES (
    'a0000000-0000-4000-8000-000000000001',
    v_class2, v_teacher2, v_room,
    timestamptz '2037-01-06 09:00:00+07',
    timestamptz '2037-01-06 10:00:00+07',
    'scheduled'
  );

  PERFORM _m4_sm_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.reschedule_teaching_session(
      v_session,
      timestamptz '2037-01-06 09:00:00+07',
      timestamptz '2037-01-06 10:00:00+07',
      'Room double'
    );
  EXCEPTION WHEN OTHERS THEN
    v_failed := SQLERRM LIKE '%room_double_booked%';
  END;

  PERFORM _m4_sm_record(6, 'reschedule room overlap rejected', v_failed);
END $$;

-- 7: self-conflict excluded
DO $$
DECLARE
  v_session uuid;
  v_ok boolean := false;
BEGIN
  PERFORM _m4_sm_as_super();
  v_session := _m4_sm_make_session(
    'SM7 Self',
    '2037-01-05',
    timestamptz '2037-01-05 09:00:00+07',
    timestamptz '2037-01-05 10:00:00+07'
  );

  PERFORM _m4_sm_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    -- Overlaps own previous window; must not self-conflict.
    PERFORM public.reschedule_teaching_session(
      v_session,
      timestamptz '2037-01-05 09:30:00+07',
      timestamptz '2037-01-05 10:30:00+07',
      'Self overlap ok'
    );
    v_ok := true;
  EXCEPTION WHEN OTHERS THEN
    v_ok := false;
  END;

  PERFORM _m4_sm_record(7, 'self-conflict excluded', v_ok);
END $$;

-- 8: completed session reschedule blocked
SELECT _m4_sm_expect_fail(8, 'completed session reschedule blocked', $$
  DO $inner$
  DECLARE
    v_session uuid;
  BEGIN
    PERFORM _m4_sm_as_super();
    v_session := _m4_sm_make_session('SM8 Completed', '2037-01-05',
      timestamptz '2037-01-05 09:00:00+07', timestamptz '2037-01-05 10:00:00+07', 'completed');
    PERFORM _m4_sm_as_auth('a1111111-1111-4111-8111-111111111111');
    PERFORM public.reschedule_teaching_session(
      v_session,
      timestamptz '2037-01-05 11:00:00+07',
      timestamptz '2037-01-05 12:00:00+07',
      'Should fail'
    );
  END $inner$;
$$);

-- 9: cancelled session reschedule blocked
SELECT _m4_sm_expect_fail(9, 'cancelled session reschedule blocked', $$
  DO $inner$
  DECLARE
    v_session uuid;
  BEGIN
    PERFORM _m4_sm_as_super();
    v_session := _m4_sm_make_session('SM9 Cancelled', '2037-01-05',
      timestamptz '2037-01-05 09:00:00+07', timestamptz '2037-01-05 10:00:00+07', 'cancelled');
    PERFORM _m4_sm_as_auth('a1111111-1111-4111-8111-111111111111');
    PERFORM public.reschedule_teaching_session(
      v_session,
      timestamptz '2037-01-05 11:00:00+07',
      timestamptz '2037-01-05 12:00:00+07',
      'Should fail'
    );
  END $inner$;
$$);

-- 10: invalid time range rejected
SELECT _m4_sm_expect_fail(10, 'invalid time range rejected', $$
  DO $inner$
  DECLARE
    v_session uuid;
  BEGIN
    PERFORM _m4_sm_as_super();
    v_session := _m4_sm_make_session('SM10 Invalid Interval');
    PERFORM _m4_sm_as_auth('a1111111-1111-4111-8111-111111111111');
    PERFORM public.reschedule_teaching_session(
      v_session,
      timestamptz '2037-01-05 12:00:00+07',
      timestamptz '2037-01-05 11:00:00+07',
      'End before start'
    );
  END $inner$;
$$);

-- 11: rescheduled session retains original occurrence identity
DO $$
DECLARE
  v_session uuid;
  v_occ date;
BEGIN
  PERFORM _m4_sm_as_super();
  v_session := _m4_sm_make_session(
    'SM11 Occ Identity',
    '2037-01-05',
    timestamptz '2037-01-05 09:00:00+07',
    timestamptz '2037-01-05 10:00:00+07'
  );

  PERFORM _m4_sm_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.reschedule_teaching_session(
    v_session,
    timestamptz '2037-01-06 09:00:00+07',
    timestamptz '2037-01-06 10:00:00+07',
    'Move to Tuesday'
  );

  SELECT occurrence_date INTO v_occ FROM teaching_session WHERE id = v_session;
  PERFORM _m4_sm_record(11, 'rescheduled session retains original occurrence identity', v_occ = '2037-01-05');
END $$;

-- 12: original recurring occurrence does not re-project
DO $$
DECLARE
  v_session uuid;
  v_class uuid;
  v_schedule uuid;
  v_proj integer;
BEGIN
  PERFORM _m4_sm_as_super();
  v_session := _m4_sm_make_session(
    'SM12 No Reproject',
    '2037-01-05',
    timestamptz '2037-01-05 09:00:00+07',
    timestamptz '2037-01-05 10:00:00+07'
  );
  SELECT class_id, schedule_id INTO v_class, v_schedule FROM _m4_sm_last;

  PERFORM _m4_sm_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.reschedule_teaching_session(
    v_session,
    timestamptz '2037-01-06 14:00:00+07',
    timestamptz '2037-01-06 15:00:00+07',
    'Away from Monday'
  );

  SELECT count(*) INTO v_proj
  FROM public.list_operational_calendar('2037-01-05', '2037-01-05', v_class, NULL, NULL)
  WHERE entry_type = 'projected' AND class_schedule_id = v_schedule AND occurrence_date = '2037-01-05';

  PERFORM _m4_sm_record(12, 'original recurring occurrence does not re-project', v_proj = 0);
END $$;

-- 13: calendar shows rescheduled session on current scheduled date
DO $$
DECLARE
  v_session uuid;
  v_class uuid;
  v_on_new integer;
  v_on_old integer;
BEGIN
  PERFORM _m4_sm_as_super();
  v_session := _m4_sm_make_session(
    'SM13 Calendar Date',
    '2037-01-05',
    timestamptz '2037-01-05 09:00:00+07',
    timestamptz '2037-01-05 10:00:00+07'
  );
  SELECT class_id INTO v_class FROM _m4_sm_last;

  PERFORM _m4_sm_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.reschedule_teaching_session(
    v_session,
    timestamptz '2037-01-06 09:00:00+07',
    timestamptz '2037-01-06 10:00:00+07',
    'Calendar move'
  );

  SELECT count(*) INTO v_on_new
  FROM public.list_operational_calendar('2037-01-06', '2037-01-06', v_class, NULL, NULL)
  WHERE entry_type = 'session' AND teaching_session_id = v_session;

  SELECT count(*) INTO v_on_old
  FROM public.list_operational_calendar('2037-01-05', '2037-01-05', v_class, NULL, NULL)
  WHERE entry_type = 'session' AND teaching_session_id = v_session;

  PERFORM _m4_sm_record(
    13,
    'calendar shows rescheduled session on current scheduled date',
    v_on_new = 1 AND v_on_old = 0
  );
END $$;

-- =============================================================================
-- 14–19 CANCELLATION
-- =============================================================================

-- 14: cancellation succeeds
DO $$
DECLARE
  v_session uuid;
  v_status text;
BEGIN
  PERFORM _m4_sm_as_super();
  v_session := _m4_sm_make_session('SM14 Cancel');

  PERFORM _m4_sm_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.cancel_teaching_session(v_session, 'Teacher sick');

  SELECT status INTO v_status FROM teaching_session WHERE id = v_session;
  PERFORM _m4_sm_record(14, 'cancellation succeeds', v_status = 'cancelled');
END $$;

-- 15: cancellation records history
DO $$
DECLARE
  v_session uuid;
  v_cnt integer;
BEGIN
  PERFORM _m4_sm_as_super();
  v_session := _m4_sm_make_session('SM15 Cancel Hist');

  PERFORM _m4_sm_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.cancel_teaching_session(v_session, 'Cancel history');

  SELECT count(*) INTO v_cnt
  FROM public.list_teaching_session_changes(v_session)
  WHERE change_type = 'cancelled';

  PERFORM _m4_sm_record(15, 'cancellation records history', v_cnt = 1);
END $$;

-- 16: cancellation reason preserved
DO $$
DECLARE
  v_session uuid;
  v_reason text;
BEGIN
  PERFORM _m4_sm_as_super();
  v_session := _m4_sm_make_session('SM16 Reason');

  PERFORM _m4_sm_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.cancel_teaching_session(v_session, 'Power outage');

  SELECT reason INTO v_reason
  FROM public.list_teaching_session_changes(v_session)
  WHERE change_type = 'cancelled'
  LIMIT 1;

  PERFORM _m4_sm_record(16, 'cancellation reason preserved', v_reason = 'Power outage');
END $$;

-- 17: completed session cancellation blocked
SELECT _m4_sm_expect_fail(17, 'completed session cancellation blocked', $$
  DO $inner$
  DECLARE
    v_session uuid;
  BEGIN
    PERFORM _m4_sm_as_super();
    v_session := _m4_sm_make_session('SM17 Done', '2037-01-05',
      timestamptz '2037-01-05 09:00:00+07', timestamptz '2037-01-05 10:00:00+07', 'completed');
    PERFORM _m4_sm_as_auth('a1111111-1111-4111-8111-111111111111');
    PERFORM public.cancel_teaching_session(v_session, 'Should fail');
  END $inner$;
$$);

-- 18: cancelled session still suppresses projection
DO $$
DECLARE
  v_session uuid;
  v_class uuid;
  v_schedule uuid;
  v_proj integer;
  v_canc integer;
BEGIN
  PERFORM _m4_sm_as_super();
  v_session := _m4_sm_make_session('SM18 Suppress');
  SELECT class_id, schedule_id INTO v_class, v_schedule FROM _m4_sm_last;

  PERFORM _m4_sm_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.cancel_teaching_session(v_session, 'Suppress projection');

  SELECT
    count(*) FILTER (WHERE entry_type = 'projected' AND class_schedule_id = v_schedule),
    count(*) FILTER (WHERE entry_type = 'session' AND session_status = 'cancelled')
  INTO v_proj, v_canc
  FROM public.list_operational_calendar('2037-01-05', '2037-01-05', v_class, NULL, NULL);

  PERFORM _m4_sm_record(18, 'cancelled session still suppresses projection', v_proj = 0 AND v_canc = 1);
END $$;

-- 19: repeated cancellation handled deterministically
DO $$
DECLARE
  v_session uuid;
  v_failed boolean := false;
BEGIN
  PERFORM _m4_sm_as_super();
  v_session := _m4_sm_make_session('SM19 Repeat Cancel');

  PERFORM _m4_sm_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.cancel_teaching_session(v_session, 'First cancel');

  BEGIN
    PERFORM public.cancel_teaching_session(v_session, 'Second cancel');
  EXCEPTION WHEN OTHERS THEN
    v_failed := SQLERRM LIKE '%already_cancelled%';
  END;

  PERFORM _m4_sm_record(19, 'repeated cancellation handled deterministically', v_failed);
END $$;

-- =============================================================================
-- 20–26 TEACHER SUBSTITUTION
-- =============================================================================

-- 20: substitute teacher succeeds
DO $$
DECLARE
  v_session uuid;
  v_new uuid;
  v_teacher uuid;
BEGIN
  PERFORM _m4_sm_as_super();
  v_session := _m4_sm_make_session('SM20 Sub');
  v_new := _m4_sm_new_teacher('SM20 New');

  PERFORM _m4_sm_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.substitute_session_teacher(v_session, v_new, 'Cover teacher');

  SELECT teacher_id INTO v_teacher FROM teaching_session WHERE id = v_session;
  PERFORM _m4_sm_record(20, 'substitute teacher succeeds', v_teacher = v_new);
END $$;

-- 21: substitution history stores previous/new teacher
DO $$
DECLARE
  v_session uuid;
  v_old uuid;
  v_new uuid;
  v_row record;
BEGIN
  PERFORM _m4_sm_as_super();
  v_session := _m4_sm_make_session('SM21 Sub Hist');
  SELECT teacher_id INTO v_old FROM _m4_sm_last;
  v_new := _m4_sm_new_teacher('SM21 New');

  PERFORM _m4_sm_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.substitute_session_teacher(v_session, v_new, 'History teachers');

  SELECT * INTO v_row
  FROM public.list_teaching_session_changes(v_session)
  WHERE change_type = 'teacher_substituted'
  LIMIT 1;

  PERFORM _m4_sm_record(
    21,
    'substitution history stores previous/new teacher',
    v_row.previous_teacher_id = v_old AND v_row.new_teacher_id = v_new
  );
END $$;

-- 22: substitute unavailable teacher rejected
DO $$
DECLARE
  v_session uuid;
  v_new uuid;
  v_failed boolean := false;
BEGIN
  PERFORM _m4_sm_as_super();
  v_session := _m4_sm_make_session('SM22 Sub Unavail');
  v_new := _m4_sm_new_teacher('SM22 Unavail');

  INSERT INTO teacher_unavailability (
    organization_id, teacher_id, block_type,
    starts_at, ends_at, status
  ) VALUES (
    'a0000000-0000-4000-8000-000000000001',
    v_new, 'one_off',
    timestamptz '2037-01-05 08:00:00+07',
    timestamptz '2037-01-05 12:00:00+07',
    'active'
  );

  PERFORM _m4_sm_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.substitute_session_teacher(v_session, v_new, 'Unavailable sub');
  EXCEPTION WHEN OTHERS THEN
    v_failed := SQLERRM LIKE '%teacher_unavailable%';
  END;

  PERFORM _m4_sm_record(22, 'substitute unavailable teacher rejected', v_failed);
END $$;

-- 23: substitute double-booked teacher rejected
DO $$
DECLARE
  v_session uuid;
  v_new uuid;
  v_class2 uuid;
  v_room2 uuid;
  v_failed boolean := false;
BEGIN
  PERFORM _m4_sm_as_super();
  v_session := _m4_sm_make_session('SM23 Sub Double');
  v_new := _m4_sm_new_teacher('SM23 Busy');
  v_class2 := _m4_sm_new_class('SM23 Other', '2037-01-01', '2037-03-31');
  v_room2 := _m4_sm_new_room('SM23 Other Room');

  INSERT INTO teaching_session (
    organization_id, class_id, teacher_id, room_id,
    scheduled_start_at, scheduled_end_at, status
  ) VALUES (
    'a0000000-0000-4000-8000-000000000001',
    v_class2, v_new, v_room2,
    timestamptz '2037-01-05 09:00:00+07',
    timestamptz '2037-01-05 10:00:00+07',
    'scheduled'
  );

  PERFORM _m4_sm_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.substitute_session_teacher(v_session, v_new, 'Double booked');
  EXCEPTION WHEN OTHERS THEN
    v_failed := SQLERRM LIKE '%teacher_double_booked%';
  END;

  PERFORM _m4_sm_record(23, 'substitute double-booked teacher rejected', v_failed);
END $$;

-- 24: completed session substitution blocked
SELECT _m4_sm_expect_fail(24, 'completed session substitution blocked', $$
  DO $inner$
  DECLARE
    v_session uuid;
    v_new uuid;
  BEGIN
    PERFORM _m4_sm_as_super();
    v_session := _m4_sm_make_session('SM24 Done Sub', '2037-01-05',
      timestamptz '2037-01-05 09:00:00+07', timestamptz '2037-01-05 10:00:00+07', 'completed');
    v_new := _m4_sm_new_teacher('SM24 New');
    PERFORM _m4_sm_as_auth('a1111111-1111-4111-8111-111111111111');
    PERFORM public.substitute_session_teacher(v_session, v_new, 'Should fail');
  END $inner$;
$$);

-- 25: substitution does not modify timetable teacher
DO $$
DECLARE
  v_session uuid;
  v_schedule uuid;
  v_sched_teacher uuid;
  v_new uuid;
  v_after uuid;
BEGIN
  PERFORM _m4_sm_as_super();
  v_session := _m4_sm_make_session('SM25 Timetable Intact');
  SELECT schedule_id, teacher_id INTO v_schedule, v_sched_teacher FROM _m4_sm_last;
  v_new := _m4_sm_new_teacher('SM25 New');

  PERFORM _m4_sm_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.substitute_session_teacher(v_session, v_new, 'No timetable mutate');

  SELECT teacher_id INTO v_after FROM class_schedule WHERE id = v_schedule;
  PERFORM _m4_sm_record(25, 'substitution does not modify timetable teacher', v_after = v_sched_teacher);
END $$;

-- 26: substitution does not modify class teacher assignments
DO $$
DECLARE
  v_session uuid;
  v_class uuid;
  v_primary uuid;
  v_new uuid;
  v_cnt integer;
BEGIN
  PERFORM _m4_sm_as_super();
  v_session := _m4_sm_make_session('SM26 CTA Intact');
  SELECT class_id, teacher_id INTO v_class, v_primary FROM _m4_sm_last;

  INSERT INTO class_teacher_assignment (
    organization_id, class_id, teacher_id, role_code, effective_from, status
  ) VALUES (
    'a0000000-0000-4000-8000-000000000001',
    v_class, v_primary, 'primary', '2037-01-01', 'active'
  );

  v_new := _m4_sm_new_teacher('SM26 New');

  PERFORM _m4_sm_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.substitute_session_teacher(v_session, v_new, 'No CTA mutate');

  SELECT count(*) INTO v_cnt
  FROM class_teacher_assignment
  WHERE class_id = v_class AND teacher_id = v_primary AND status = 'active';

  PERFORM _m4_sm_record(
    26,
    'substitution does not modify class teacher assignments',
    v_cnt = 1
      AND NOT EXISTS (
        SELECT 1 FROM class_teacher_assignment
        WHERE class_id = v_class AND teacher_id = v_new
      )
  );
END $$;

-- =============================================================================
-- 27–31 ROOM CHANGE
-- =============================================================================

-- 27: room change succeeds
DO $$
DECLARE
  v_session uuid;
  v_new uuid;
  v_room uuid;
BEGIN
  PERFORM _m4_sm_as_super();
  v_session := _m4_sm_make_session('SM27 Room');
  v_new := _m4_sm_new_room('SM27 New Room');

  PERFORM _m4_sm_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.change_session_room(v_session, v_new, 'AV issue');

  SELECT room_id INTO v_room FROM teaching_session WHERE id = v_session;
  PERFORM _m4_sm_record(27, 'room change succeeds', v_room = v_new);
END $$;

-- 28: room history stores previous/new room
DO $$
DECLARE
  v_session uuid;
  v_old uuid;
  v_new uuid;
  v_row record;
BEGIN
  PERFORM _m4_sm_as_super();
  v_session := _m4_sm_make_session('SM28 Room Hist');
  SELECT room_id INTO v_old FROM _m4_sm_last;
  v_new := _m4_sm_new_room('SM28 New Room');

  PERFORM _m4_sm_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.change_session_room(v_session, v_new, 'History rooms');

  SELECT * INTO v_row
  FROM public.list_teaching_session_changes(v_session)
  WHERE change_type = 'room_changed'
  LIMIT 1;

  PERFORM _m4_sm_record(
    28,
    'room history stores previous/new room',
    v_row.previous_room_id = v_old AND v_row.new_room_id = v_new
  );
END $$;

-- 29: room conflict rejected
DO $$
DECLARE
  v_session uuid;
  v_target uuid;
  v_class2 uuid;
  v_teacher2 uuid;
  v_failed boolean := false;
BEGIN
  PERFORM _m4_sm_as_super();
  v_session := _m4_sm_make_session('SM29 Room Conflict');
  v_target := _m4_sm_new_room('SM29 Busy Room');
  v_class2 := _m4_sm_new_class('SM29 Other', '2037-01-01', '2037-03-31');
  v_teacher2 := _m4_sm_new_teacher('SM29 Other');

  INSERT INTO teaching_session (
    organization_id, class_id, teacher_id, room_id,
    scheduled_start_at, scheduled_end_at, status
  ) VALUES (
    'a0000000-0000-4000-8000-000000000001',
    v_class2, v_teacher2, v_target,
    timestamptz '2037-01-05 09:00:00+07',
    timestamptz '2037-01-05 10:00:00+07',
    'scheduled'
  );

  PERFORM _m4_sm_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.change_session_room(v_session, v_target, 'Into busy room');
  EXCEPTION WHEN OTHERS THEN
    v_failed := SQLERRM LIKE '%room_double_booked%';
  END;

  PERFORM _m4_sm_record(29, 'room conflict rejected', v_failed);
END $$;

-- 30: inactive/cross-org room rejected
DO $$
DECLARE
  v_session uuid;
  v_inactive uuid;
  v_org_b uuid := 'b0000000-0000-4000-8000-000000000001';
  v_room_b uuid;
  v_inactive_fail boolean := false;
  v_cross_fail boolean := false;
BEGIN
  PERFORM _m4_sm_as_super();
  v_session := _m4_sm_make_session('SM30 Bad Room');
  v_inactive := _m4_sm_new_room('SM30 Inactive', 'a0000000-0000-4000-8000-000000000001', 'inactive');
  v_room_b := _m4_sm_new_room('SM30 Org B Room', v_org_b);

  PERFORM _m4_sm_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.change_session_room(v_session, v_inactive, 'Inactive');
  EXCEPTION WHEN OTHERS THEN
    v_inactive_fail := SQLERRM LIKE '%room_inactive%' OR SQLERRM LIKE '%invalid_room%';
  END;

  BEGIN
    PERFORM public.change_session_room(v_session, v_room_b, 'Cross org');
  EXCEPTION WHEN OTHERS THEN
    v_cross_fail := SQLERRM LIKE '%invalid_room%';
  END;

  PERFORM _m4_sm_record(30, 'inactive/cross-org room rejected', v_inactive_fail AND v_cross_fail);
END $$;

-- 31: room change does not modify timetable room
DO $$
DECLARE
  v_session uuid;
  v_schedule uuid;
  v_sched_room uuid;
  v_new uuid;
  v_after uuid;
BEGIN
  PERFORM _m4_sm_as_super();
  v_session := _m4_sm_make_session('SM31 Timetable Room');
  SELECT schedule_id, room_id INTO v_schedule, v_sched_room FROM _m4_sm_last;
  v_new := _m4_sm_new_room('SM31 New');

  PERFORM _m4_sm_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.change_session_room(v_session, v_new, 'No schedule mutate');

  SELECT room_id INTO v_after FROM class_schedule WHERE id = v_schedule;
  PERFORM _m4_sm_record(31, 'room change does not modify timetable room', v_after = v_sched_room);
END $$;

-- =============================================================================
-- 32–37 HISTORY / AUTH / ORDERING
-- =============================================================================

-- 32: history UPDATE rejected
DO $$
DECLARE
  v_session uuid;
  v_change uuid;
  v_failed boolean := false;
BEGIN
  PERFORM _m4_sm_as_super();
  v_session := _m4_sm_make_session('SM32 Hist Update');

  PERFORM _m4_sm_as_auth('a1111111-1111-4111-8111-111111111111');
  v_change := public.cancel_teaching_session(v_session, 'For update reject');

  PERFORM _m4_sm_as_super();
  BEGIN
    UPDATE teaching_session_change SET reason = 'tampered' WHERE id = v_change;
  EXCEPTION WHEN OTHERS THEN
    v_failed := SQLERRM LIKE '%teaching_session_change_immutable%';
  END;

  PERFORM _m4_sm_record(32, 'history UPDATE rejected', v_failed);
END $$;

-- 33: history DELETE rejected
DO $$
DECLARE
  v_session uuid;
  v_change uuid;
  v_failed boolean := false;
BEGIN
  PERFORM _m4_sm_as_super();
  v_session := _m4_sm_make_session('SM33 Hist Delete');

  PERFORM _m4_sm_as_auth('a1111111-1111-4111-8111-111111111111');
  v_change := public.cancel_teaching_session(v_session, 'For delete reject');

  PERFORM _m4_sm_as_super();
  BEGIN
    DELETE FROM teaching_session_change WHERE id = v_change;
  EXCEPTION WHEN OTHERS THEN
    v_failed := SQLERRM LIKE '%teaching_session_change_immutable%';
  END;

  PERFORM _m4_sm_record(33, 'history DELETE rejected', v_failed);
END $$;

-- 34: cross-org history read blocked
DO $$
DECLARE
  v_session_b uuid;
  v_cnt integer;
BEGIN
  PERFORM _m4_sm_as_super();
  v_session_b := _m4_sm_make_session(
    'SM34 Org B',
    '2037-01-05',
    timestamptz '2037-01-05 09:00:00+07',
    timestamptz '2037-01-05 10:00:00+07',
    'scheduled',
    'b0000000-0000-4000-8000-000000000001'
  );

  PERFORM _m4_sm_as_auth('b1111111-1111-4111-8111-111111111111');
  PERFORM public.cancel_teaching_session(v_session_b, 'Org B cancel');

  PERFORM _m4_sm_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_cnt FROM public.list_teaching_session_changes(v_session_b);

  PERFORM _m4_sm_record(34, 'cross-org history read blocked', v_cnt = 0);
END $$;

-- 35: unauthorized mutation blocked
SELECT _m4_sm_expect_fail(35, 'unauthorized mutation blocked', $$
  DO $inner$
  DECLARE
    v_session uuid;
  BEGIN
    PERFORM _m4_sm_as_super();
    v_session := _m4_sm_make_session('SM35 Unauthorized');
    -- org-a-reader: no enrollment.update
    PERFORM _m4_sm_as_auth('a4444444-4444-4444-8444-444444444444');
    PERFORM public.cancel_teaching_session(v_session, 'Reader should fail');
  END $inner$;
$$);

-- 36: authorized mutation allowed
DO $$
DECLARE
  v_session uuid;
  v_ok boolean := false;
BEGIN
  PERFORM _m4_sm_as_super();
  v_session := _m4_sm_make_session('SM36 Authorized');

  PERFORM _m4_sm_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.reschedule_teaching_session(
      v_session,
      timestamptz '2037-01-05 16:00:00+07',
      timestamptz '2037-01-05 17:00:00+07',
      'Admin allowed'
    );
    v_ok := true;
  EXCEPTION WHEN OTHERS THEN
    v_ok := false;
  END;

  PERFORM _m4_sm_record(36, 'authorized mutation allowed', v_ok);
END $$;

-- 37: history ordered deterministically
DO $$
DECLARE
  v_session uuid;
  v_new_teacher uuid;
  v_new_room uuid;
  v_types text[];
BEGIN
  PERFORM _m4_sm_as_super();
  v_session := _m4_sm_make_session('SM37 Order');
  v_new_teacher := _m4_sm_new_teacher('SM37 T');
  v_new_room := _m4_sm_new_room('SM37 R');

  PERFORM _m4_sm_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.reschedule_teaching_session(
    v_session,
    timestamptz '2037-01-05 10:00:00+07',
    timestamptz '2037-01-05 11:00:00+07',
    'First'
  );
  PERFORM public.substitute_session_teacher(v_session, v_new_teacher, 'Second');
  PERFORM public.change_session_room(v_session, v_new_room, 'Third');

  SELECT array_agg(change_type ORDER BY occurred_at ASC, id ASC) INTO v_types
  FROM public.list_teaching_session_changes(v_session);

  PERFORM _m4_sm_record(
    37,
    'history ordered deterministically',
    v_types = ARRAY['rescheduled', 'teacher_substituted', 'room_changed']::text[]
  );
END $$;

-- =============================================================================
-- 38–40 CALENDAR REFLECTIONS
-- =============================================================================

-- 38: operational calendar reflects substitute teacher
DO $$
DECLARE
  v_session uuid;
  v_class uuid;
  v_new uuid;
  v_cal_teacher uuid;
BEGIN
  PERFORM _m4_sm_as_super();
  v_session := _m4_sm_make_session('SM38 Cal Teacher');
  SELECT class_id INTO v_class FROM _m4_sm_last;
  v_new := _m4_sm_new_teacher('SM38 Sub');

  PERFORM _m4_sm_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.substitute_session_teacher(v_session, v_new, 'Cal teacher');

  SELECT teacher_id INTO v_cal_teacher
  FROM public.list_operational_calendar('2037-01-05', '2037-01-05', v_class, NULL, NULL)
  WHERE teaching_session_id = v_session
  LIMIT 1;

  PERFORM _m4_sm_record(38, 'operational calendar reflects substitute teacher', v_cal_teacher = v_new);
END $$;

-- 39: operational calendar reflects changed room
DO $$
DECLARE
  v_session uuid;
  v_class uuid;
  v_new uuid;
  v_cal_room uuid;
BEGIN
  PERFORM _m4_sm_as_super();
  v_session := _m4_sm_make_session('SM39 Cal Room');
  SELECT class_id INTO v_class FROM _m4_sm_last;
  v_new := _m4_sm_new_room('SM39 Cal Room');

  PERFORM _m4_sm_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.change_session_room(v_session, v_new, 'Cal room');

  SELECT room_id INTO v_cal_room
  FROM public.list_operational_calendar('2037-01-05', '2037-01-05', v_class, NULL, NULL)
  WHERE teaching_session_id = v_session
  LIMIT 1;

  PERFORM _m4_sm_record(39, 'operational calendar reflects changed room', v_cal_room = v_new);
END $$;

-- 40: cancelled session remains visible
DO $$
DECLARE
  v_session uuid;
  v_class uuid;
  v_cnt integer;
BEGIN
  PERFORM _m4_sm_as_super();
  v_session := _m4_sm_make_session('SM40 Cancel Visible');
  SELECT class_id INTO v_class FROM _m4_sm_last;

  PERFORM _m4_sm_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.cancel_teaching_session(v_session, 'Still visible');

  SELECT count(*) INTO v_cnt
  FROM public.list_operational_calendar('2037-01-05', '2037-01-05', v_class, NULL, NULL)
  WHERE teaching_session_id = v_session AND session_status = 'cancelled';

  PERFORM _m4_sm_record(40, 'cancelled session remains visible', v_cnt = 1);
END $$;

-- =============================================================================
-- 41–44 FINANCIAL / ATTENDANCE / FK SURVIVAL
-- =============================================================================

-- 41: financial-effect rule enforced
DO $$
DECLARE
  v_session uuid;
  v_class uuid;
  v_teacher uuid;
  v_rule uuid;
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_admin uuid := 'a1000000-0000-4000-8000-000000000001';
  v_failed boolean := false;
  v_exists boolean;
BEGIN
  PERFORM _m4_sm_as_super();
  v_session := _m4_sm_make_session('SM41 Finance');
  SELECT class_id, teacher_id INTO v_class, v_teacher FROM _m4_sm_last;

  INSERT INTO staff_compensation_rule (
    organization_id, app_user_id, cost_domain_code, compensation_basis_code,
    amount, effective_from, status, created_by
  ) VALUES (
    v_org, v_admin, 'personnel', 'per_session',
    250000, '2037-01-01', 'active', v_admin
  ) RETURNING id INTO v_rule;

  INSERT INTO personnel_cost_entry (
    organization_id, app_user_id, staff_compensation_rule_id,
    cost_domain_code, compensation_basis_code, amount,
    accounting_period, incurred_date, source_type,
    teaching_session_id, class_id, teacher_id, status, created_by
  ) VALUES (
    v_org, v_admin, v_rule,
    'personnel', 'per_session', 250000,
    '2037-01-01', '2037-01-05', 'per_session',
    v_session, v_class, v_teacher, 'posted', v_admin
  );

  PERFORM _m4_sm_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.cancel_teaching_session(v_session, 'Has posted cost');
  EXCEPTION WHEN OTHERS THEN
    v_failed := SQLERRM LIKE '%financial_effect_exists%';
  END;

  SELECT EXISTS (SELECT 1 FROM teaching_session WHERE id = v_session AND status = 'scheduled')
    INTO v_exists;

  PERFORM _m4_sm_record(41, 'financial-effect rule enforced', v_failed AND v_exists);
END $$;

-- 42: attendance rule enforced
DO $$
DECLARE
  v_session uuid;
  v_class uuid;
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_student uuid;
  v_enrollment uuid;
  v_failed boolean := false;
BEGIN
  PERFORM _m4_sm_as_super();
  v_session := _m4_sm_make_session('SM42 Attendance');
  SELECT class_id INTO v_class FROM _m4_sm_last;

  INSERT INTO student (organization_id, given_name, family_name, status)
  VALUES (v_org, 'SM42', 'Student', 'active')
  RETURNING id INTO v_student;

  INSERT INTO enrollment (organization_id, student_id, class_id, start_date, status)
  VALUES (v_org, v_student, v_class, '2037-01-01', 'active')
  RETURNING id INTO v_enrollment;

  INSERT INTO attendance (organization_id, teaching_session_id, enrollment_id, status)
  VALUES (v_org, v_session, v_enrollment, 'present');

  PERFORM _m4_sm_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.cancel_teaching_session(v_session, 'Has attendance');
  EXCEPTION WHEN OTHERS THEN
    v_failed := SQLERRM LIKE '%attendance_already_recorded%';
  END;

  PERFORM _m4_sm_record(42, 'attendance rule enforced', v_failed);
END $$;

-- 43: M3 trial reference survives mutation
DO $$
DECLARE
  v_session uuid;
  v_class uuid;
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_admin uuid := 'a1000000-0000-4000-8000-000000000001';
  v_lead uuid := 'a6100000-0000-4000-8000-000000000001';
  v_candidate uuid;
  v_trial uuid;
  v_link uuid;
BEGIN
  PERFORM _m4_sm_as_super();
  v_session := _m4_sm_make_session('SM43 Trial FK');
  SELECT class_id INTO v_class FROM _m4_sm_last;

  SELECT id INTO v_candidate
  FROM lead_candidate
  WHERE lead_id = v_lead AND organization_id = v_org
  ORDER BY is_primary_candidate DESC
  LIMIT 1;

  BEGIN
    PERFORM set_config('olli.lead_trial_mutation', 'true', true);
    INSERT INTO lead_trial (
      organization_id, lead_id, lead_candidate_id, class_id, teaching_session_id,
      status, scheduled_start_at, scheduled_end_at, created_by
    ) VALUES (
      v_org, v_lead, v_candidate, v_class, v_session,
      'scheduled',
      timestamptz '2037-01-05 09:00:00+07',
      timestamptz '2037-01-05 10:00:00+07',
      v_admin
    ) RETURNING id INTO v_trial;
    PERFORM set_config('olli.lead_trial_mutation', 'false', true);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('olli.lead_trial_mutation', 'false', true);
    RAISE;
  END;

  PERFORM _m4_sm_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.cancel_teaching_session(v_session, 'Trial must survive');

  SELECT teaching_session_id INTO v_link FROM lead_trial WHERE id = v_trial;

  PERFORM _m4_sm_record(
    43,
    'M3 trial reference survives mutation',
    v_link = v_session
      AND EXISTS (SELECT 1 FROM teaching_session WHERE id = v_session AND status = 'cancelled')
  );
END $$;

-- 44: M2 session FK references survive mutation
DO $$
DECLARE
  v_session uuid;
  v_exists boolean;
BEGIN
  PERFORM _m4_sm_as_super();
  v_session := _m4_sm_make_session('SM44 Session Survives');

  PERFORM _m4_sm_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.cancel_teaching_session(v_session, 'Session row retained');

  SELECT EXISTS (
    SELECT 1 FROM teaching_session WHERE id = v_session AND status = 'cancelled'
  ) INTO v_exists;

  PERFORM _m4_sm_record(44, 'M2 session FK references survive mutation', v_exists);
END $$;

-- =============================================================================
-- Summary
-- =============================================================================
DO $$
DECLARE
  v_total integer;
  v_failed integer;
  v_passed integer;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE result = 'FAIL')
  INTO v_total, v_failed
  FROM _m4_sm_results;

  v_passed := v_total - v_failed;

  IF v_total <> 44 THEN
    RAISE EXCEPTION 'M4 session mutation Tests: expected 44 tests, found %', v_total;
  END IF;

  IF v_failed > 0 THEN
    RAISE NOTICE 'Failed tests: %', (
      SELECT string_agg(test_no::text || ':' || test_name, ', ' ORDER BY test_no)
      FROM _m4_sm_results WHERE result = 'FAIL'
    );
    RAISE EXCEPTION 'M4 session mutation Tests: % / % passed (% failed)',
      v_passed, v_total, v_failed;
  END IF;

  RAISE NOTICE 'M4 session mutation Tests: % / % passed (0 failed)', v_passed, v_total;
END $$;

ROLLBACK;
