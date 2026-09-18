-- M4-T07: Teacher workload and room usage analytics tests (35).

BEGIN;

CREATE TEMP TABLE _m4_wl_results (
  test_no   integer PRIMARY KEY,
  test_name text NOT NULL,
  result    text NOT NULL CHECK (result IN ('PASS', 'FAIL'))
);

GRANT ALL ON TABLE _m4_wl_results TO authenticated, anon;

CREATE TEMP TABLE _m4_wl_last (
  class_id    uuid,
  teacher_id  uuid,
  room_id     uuid,
  schedule_id uuid,
  session_id  uuid
);

CREATE OR REPLACE FUNCTION _m4_wl_record(test_no integer, test_name text, passed boolean)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO _m4_wl_results (test_no, test_name, result)
  VALUES (test_no, test_name, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END);
END;
$$;

CREATE OR REPLACE FUNCTION _m4_wl_expect_fail(test_no integer, test_name text, sql_text text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE sql_text;
    PERFORM _m4_wl_record(test_no, test_name, false);
  EXCEPTION WHEN OTHERS THEN
    PERFORM _m4_wl_record(test_no, test_name, true);
  END;
END;
$$;

CREATE OR REPLACE FUNCTION _m4_wl_as_auth(p_auth_id uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', p_auth_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_auth_id::text, 'role', 'authenticated')::text, true);
END;
$$;

CREATE OR REPLACE FUNCTION _m4_wl_as_super()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
END;
$$;

CREATE OR REPLACE FUNCTION _m4_wl_weekday(p_date date)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE EXTRACT(DOW FROM p_date)::int
    WHEN 0 THEN 'sun' WHEN 1 THEN 'mon' WHEN 2 THEN 'tue' WHEN 3 THEN 'wed'
    WHEN 4 THEN 'thu' WHEN 5 THEN 'fri' WHEN 6 THEN 'sat'
  END;
$$;

CREATE OR REPLACE FUNCTION _m4_wl_new_class(
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

CREATE OR REPLACE FUNCTION _m4_wl_new_teacher(
  p_label text, p_org uuid DEFAULT 'a0000000-0000-4000-8000-000000000001'
)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_id uuid;
BEGIN
  INSERT INTO teacher (organization_id, given_name, family_name, status)
  VALUES (p_org, p_label, 'WL' || substr(gen_random_uuid()::text, 1, 8), 'active')
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION _m4_wl_new_room(
  p_label text, p_org uuid DEFAULT 'a0000000-0000-4000-8000-000000000001'
)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_id uuid;
BEGIN
  INSERT INTO room (organization_id, code, name, status)
  VALUES (p_org, 'WL-' || substr(gen_random_uuid()::text, 1, 8), p_label, 'active')
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION _m4_wl_make_session(
  p_label text,
  p_occ date DEFAULT '2040-01-07',
  p_start timestamptz DEFAULT timestamptz '2040-01-07 09:00:00+07',
  p_end timestamptz DEFAULT timestamptz '2040-01-07 10:00:00+07',
  p_status text DEFAULT 'scheduled',
  p_org uuid DEFAULT 'a0000000-0000-4000-8000-000000000001',
  p_teacher_id uuid DEFAULT NULL,
  p_room_id uuid DEFAULT NULL
)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
  v_class uuid; v_teacher uuid; v_room uuid; v_schedule uuid; v_session uuid;
  v_wd text := _m4_wl_weekday(p_occ);
BEGIN
  v_class := _m4_wl_new_class(p_label, p_occ - 7, p_occ + 60, p_org);
  v_teacher := COALESCE(p_teacher_id, _m4_wl_new_teacher(p_label, p_org));
  v_room := COALESCE(p_room_id, _m4_wl_new_room(p_label || ' Room', p_org));
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
  DELETE FROM _m4_wl_last;
  INSERT INTO _m4_wl_last VALUES (v_class, v_teacher, v_room, v_schedule, v_session);
  RETURN v_session;
END;
$$;

-- 1: scheduled session counts for teacher
DO $$
DECLARE v_teacher uuid; v_row record;
BEGIN
  PERFORM _m4_wl_as_super();
  PERFORM _m4_wl_make_session('WL1 Count', '2040-01-07',
    timestamptz '2040-01-07 09:00:00+07', timestamptz '2040-01-07 10:00:00+07', 'scheduled');
  SELECT teacher_id INTO v_teacher FROM _m4_wl_last;
  PERFORM _m4_wl_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT * INTO v_row FROM public.list_teacher_workload('2040-01-07', '2040-01-07', NULL, v_teacher);
  PERFORM _m4_wl_record(1, 'scheduled session counts for teacher', v_row.materialized_session_count = 1);
END $$;

-- 2: scheduled minutes calculate correctly
DO $$
DECLARE v_teacher uuid; v_row record;
BEGIN
  PERFORM _m4_wl_as_super();
  PERFORM _m4_wl_make_session('WL2 Minutes', '2040-01-08',
    timestamptz '2040-01-08 09:00:00+07', timestamptz '2040-01-08 10:30:00+07', 'scheduled');
  SELECT teacher_id INTO v_teacher FROM _m4_wl_last;
  PERFORM _m4_wl_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT * INTO v_row FROM public.list_teacher_workload('2040-01-08', '2040-01-08', NULL, v_teacher);
  PERFORM _m4_wl_record(2, 'scheduled minutes calculate correctly', v_row.materialized_scheduled_minutes = 90);
END $$;

-- 3: completed session counts correctly
DO $$
DECLARE v_teacher uuid; v_row record;
BEGIN
  PERFORM _m4_wl_as_super();
  PERFORM _m4_wl_make_session('WL3 Completed', '2040-01-09',
    timestamptz '2040-01-09 09:00:00+07', timestamptz '2040-01-09 10:00:00+07', 'completed');
  SELECT teacher_id INTO v_teacher FROM _m4_wl_last;
  PERFORM _m4_wl_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT * INTO v_row FROM public.list_teacher_workload('2040-01-09', '2040-01-09', NULL, v_teacher);
  PERFORM _m4_wl_record(3, 'completed session counts correctly', v_row.completed_session_count = 1);
END $$;

-- 4: delivered-time semantics match M1 (scheduled fallback, no actual_*)
DO $$
DECLARE v_teacher uuid; v_row record;
BEGIN
  PERFORM _m4_wl_as_super();
  PERFORM _m4_wl_make_session('WL4 Delivered', '2040-01-10',
    timestamptz '2040-01-10 09:00:00+07', timestamptz '2040-01-10 10:00:00+07', 'completed');
  SELECT teacher_id INTO v_teacher FROM _m4_wl_last;
  PERFORM _m4_wl_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT * INTO v_row FROM public.list_teacher_workload('2040-01-10', '2040-01-10', NULL, v_teacher);
  PERFORM _m4_wl_record(
    4, 'delivered-time semantics match audited M1 behavior',
    v_row.delivered_scheduled_minutes = 60 AND v_row.actual_delivered_minutes = 0
  );
END $$;

-- 5: cancelled session excluded from workload minutes
DO $$
DECLARE v_teacher uuid; v_row record;
BEGIN
  PERFORM _m4_wl_as_super();
  PERFORM _m4_wl_make_session('WL5 Cancelled', '2040-01-11',
    timestamptz '2040-01-11 09:00:00+07', timestamptz '2040-01-11 10:00:00+07', 'cancelled');
  SELECT teacher_id INTO v_teacher FROM _m4_wl_last;
  PERFORM _m4_wl_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT * INTO v_row FROM public.list_teacher_workload('2040-01-11', '2040-01-11', NULL, v_teacher);
  PERFORM _m4_wl_record(
    5, 'cancelled session excluded from workload minutes',
    v_row.materialized_scheduled_minutes = 0 AND v_row.cancelled_session_count = 1
  );
END $$;

-- 6: in-progress treatment correct
DO $$
DECLARE v_teacher uuid; v_row record;
BEGIN
  PERFORM _m4_wl_as_super();
  PERFORM _m4_wl_make_session('WL6 InProgress', '2040-01-12',
    timestamptz '2040-01-12 09:00:00+07', timestamptz '2040-01-12 10:00:00+07', 'in_progress');
  SELECT teacher_id INTO v_teacher FROM _m4_wl_last;
  PERFORM _m4_wl_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT * INTO v_row FROM public.list_teacher_workload('2040-01-12', '2040-01-12', NULL, v_teacher);
  PERFORM _m4_wl_record(
    6, 'in-progress treatment correct',
    v_row.in_progress_session_count = 1
      AND v_row.materialized_scheduled_minutes = 60
      AND v_row.completed_session_count = 0
  );
END $$;

-- 7: projected occurrence contributes projected teacher workload
DO $$
DECLARE v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_class uuid; v_teacher uuid; v_row record;
BEGIN
  PERFORM _m4_wl_as_super();
  v_class := _m4_wl_new_class('WL7 Projected', '2040-02-01', '2040-02-28');
  v_teacher := _m4_wl_new_teacher('WL7');
  INSERT INTO class_schedule (
    organization_id, class_id, weekday_code, start_time, end_time,
    effective_from, teacher_id, status
  ) VALUES (v_org, v_class, 'mon', '09:00', '10:00', '2040-02-01', v_teacher, 'active');
  PERFORM _m4_wl_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT * INTO v_row FROM public.list_teacher_workload('2040-02-06', '2040-02-06', v_class, v_teacher);
  PERFORM _m4_wl_record(
    7, 'projected occurrence contributes projected teacher workload',
    v_row.projected_session_count = 1 AND v_row.projected_minutes = 60
  );
END $$;

-- 8: materialized occurrence suppresses projected duplicate
DO $$
DECLARE v_teacher uuid; v_class uuid; v_row record;
BEGIN
  PERFORM _m4_wl_as_super();
  PERFORM _m4_wl_make_session('WL8 Dedup', '2040-01-13',
    timestamptz '2040-01-13 09:00:00+07', timestamptz '2040-01-13 10:00:00+07', 'scheduled');
  SELECT teacher_id, class_id INTO v_teacher, v_class FROM _m4_wl_last;
  PERFORM _m4_wl_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT * INTO v_row FROM public.list_teacher_workload('2040-01-13', '2040-01-13', v_class, v_teacher);
  PERFORM _m4_wl_record(
    8, 'materialized occurrence suppresses projected duplicate',
    v_row.materialized_session_count = 1 AND v_row.projected_session_count = 0
  );
END $$;

-- 9: unresolved projected teacher not attributed
DO $$
DECLARE v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_class uuid; v_gaps record; v_sum integer;
BEGIN
  PERFORM _m4_wl_as_super();
  v_class := _m4_wl_new_class('WL9 Unresolved', '2040-03-01', '2040-03-31');
  INSERT INTO class_schedule (
    organization_id, class_id, weekday_code, start_time, end_time,
    effective_from, teacher_id, status
  ) VALUES (v_org, v_class, 'tue', '09:00', '10:00', '2040-03-01', NULL, 'active');
  PERFORM _m4_wl_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT * INTO v_gaps FROM public.get_operational_planning_gaps('2040-03-06', '2040-03-06', v_class);
  SELECT COALESCE(SUM(projected_session_count), 0) INTO v_sum
  FROM public.list_teacher_workload('2040-03-06', '2040-03-06', v_class, NULL);
  PERFORM _m4_wl_record(
    9, 'unresolved projected teacher not attributed',
    v_gaps.unresolved_projected_session_count = 1 AND v_sum = 0
  );
END $$;

-- 10: multiple-primary projected occurrence not attributed
DO $$
DECLARE v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_class uuid; v_t1 uuid; v_t2 uuid; v_gaps record;
BEGIN
  PERFORM _m4_wl_as_super();
  v_class := _m4_wl_new_class('WL10 Multi', '2040-04-01', '2040-04-30');
  v_t1 := _m4_wl_new_teacher('WL10A'); v_t2 := _m4_wl_new_teacher('WL10B');
  INSERT INTO class_teacher_assignment (organization_id, class_id, teacher_id, role_code, effective_from, status)
  VALUES (v_org, v_class, v_t1, 'primary', '2040-04-01', 'active'),
         (v_org, v_class, v_t2, 'primary', '2040-04-01', 'active');
  INSERT INTO class_schedule (
    organization_id, class_id, weekday_code, start_time, end_time,
    effective_from, teacher_id, status
  ) VALUES (v_org, v_class, 'wed', '09:00', '10:00', '2040-04-01', NULL, 'active');
  PERFORM _m4_wl_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT * INTO v_gaps FROM public.get_operational_planning_gaps('2040-04-04', '2040-04-04', v_class);
  PERFORM _m4_wl_record(
    10, 'multiple-primary projected occurrence not attributed',
    v_gaps.unresolved_projected_session_count = 1
  );
END $$;

-- 11: assistant not used as projected fallback
DO $$
DECLARE v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_class uuid; v_assistant uuid; v_gaps record;
BEGIN
  PERFORM _m4_wl_as_super();
  v_class := _m4_wl_new_class('WL11 Assistant', '2040-05-01', '2040-05-31');
  v_assistant := _m4_wl_new_teacher('WL11A');
  INSERT INTO class_teacher_assignment (organization_id, class_id, teacher_id, role_code, effective_from, status)
  VALUES (v_org, v_class, v_assistant, 'assistant', '2040-05-01', 'active');
  INSERT INTO class_schedule (
    organization_id, class_id, weekday_code, start_time, end_time,
    effective_from, teacher_id, status
  ) VALUES (v_org, v_class, 'mon', '09:00', '10:00', '2040-05-01', NULL, 'active');
  PERFORM _m4_wl_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT * INTO v_gaps FROM public.get_operational_planning_gaps('2040-05-07', '2040-05-07', v_class);
  PERFORM _m4_wl_record(11, 'assistant not used as projected fallback', v_gaps.unresolved_projected_session_count = 1);
END $$;

-- 12: rescheduled session counted on new operational date
DO $$
DECLARE v_session uuid; v_teacher uuid; v_row record;
BEGIN
  PERFORM _m4_wl_as_super();
  v_session := _m4_wl_make_session('WL12 Resched', '2040-01-14',
    timestamptz '2040-01-14 09:00:00+07', timestamptz '2040-01-14 10:00:00+07', 'scheduled');
  SELECT teacher_id INTO v_teacher FROM _m4_wl_last;
  PERFORM _m4_wl_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.reschedule_teaching_session(
    v_session, timestamptz '2040-01-15 09:00:00+07', timestamptz '2040-01-15 10:00:00+07', 'Move');
  SELECT * INTO v_row FROM public.list_teacher_workload('2040-01-15', '2040-01-15', NULL, v_teacher);
  PERFORM _m4_wl_record(12, 'rescheduled session counted on new operational date', v_row.materialized_session_count = 1);
END $$;

-- 13: original occurrence date does not retain workload
DO $$
DECLARE v_session uuid; v_teacher uuid; v_row record;
BEGIN
  PERFORM _m4_wl_as_super();
  v_session := _m4_wl_make_session('WL13 OldDate', '2040-01-16',
    timestamptz '2040-01-16 09:00:00+07', timestamptz '2040-01-16 10:00:00+07', 'scheduled');
  SELECT teacher_id INTO v_teacher FROM _m4_wl_last;
  PERFORM _m4_wl_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.reschedule_teaching_session(
    v_session, timestamptz '2040-01-17 09:00:00+07', timestamptz '2040-01-17 10:00:00+07', 'Move');
  SELECT * INTO v_row FROM public.list_teacher_workload('2040-01-16', '2040-01-16', NULL, v_teacher);
  PERFORM _m4_wl_record(13, 'original occurrence date does not retain workload', v_row.materialized_session_count = 0);
END $$;

-- 14: substituted teacher receives current workload
DO $$
DECLARE v_session uuid; v_old uuid; v_new uuid; v_row record;
BEGIN
  PERFORM _m4_wl_as_super();
  v_session := _m4_wl_make_session('WL14 Sub', '2040-01-18',
    timestamptz '2040-01-18 09:00:00+07', timestamptz '2040-01-18 10:00:00+07', 'scheduled');
  SELECT teacher_id INTO v_old FROM _m4_wl_last;
  v_new := _m4_wl_new_teacher('WL14New');
  PERFORM _m4_wl_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.substitute_session_teacher(v_session, v_new, 'Cover');
  SELECT * INTO v_row FROM public.list_teacher_workload('2040-01-18', '2040-01-18', NULL, v_new);
  PERFORM _m4_wl_record(14, 'substituted teacher receives current workload', v_row.materialized_session_count = 1);
END $$;

-- 15: previous teacher no longer receives that session
DO $$
DECLARE v_session uuid; v_old uuid; v_new uuid; v_row record;
BEGIN
  PERFORM _m4_wl_as_super();
  v_session := _m4_wl_make_session('WL15 SubOld', '2040-01-19',
    timestamptz '2040-01-19 09:00:00+07', timestamptz '2040-01-19 10:00:00+07', 'scheduled');
  SELECT teacher_id INTO v_old FROM _m4_wl_last;
  v_new := _m4_wl_new_teacher('WL15New');
  PERFORM _m4_wl_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.substitute_session_teacher(v_session, v_new, 'Cover');
  SELECT * INTO v_row FROM public.list_teacher_workload('2040-01-19', '2040-01-19', NULL, v_old);
  PERFORM _m4_wl_record(15, 'previous teacher no longer receives that session', v_row.materialized_session_count = 0);
END $$;

-- 16: room booked minutes correct
DO $$
DECLARE v_room uuid; v_row record;
BEGIN
  PERFORM _m4_wl_as_super();
  PERFORM _m4_wl_make_session('WL16 Room', '2040-01-20',
    timestamptz '2040-01-20 09:00:00+07', timestamptz '2040-01-20 11:00:00+07', 'scheduled');
  SELECT room_id INTO v_room FROM _m4_wl_last;
  PERFORM _m4_wl_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT * INTO v_row FROM public.list_room_usage('2040-01-20', '2040-01-20', NULL, v_room);
  PERFORM _m4_wl_record(16, 'room booked minutes correct', v_row.materialized_booked_minutes = 120);
END $$;

-- 17: projected room usage correct
DO $$
DECLARE v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_class uuid; v_room uuid; v_row record;
BEGIN
  PERFORM _m4_wl_as_super();
  v_class := _m4_wl_new_class('WL17 RoomProj', '2040-06-01', '2040-06-30');
  v_room := _m4_wl_new_room('WL17 Room');
  INSERT INTO class_schedule (
    organization_id, class_id, weekday_code, start_time, end_time,
    effective_from, room_id, status
  ) VALUES (v_org, v_class, 'thu', '09:00', '10:30', '2040-06-01', v_room, 'active');
  PERFORM _m4_wl_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT * INTO v_row FROM public.list_room_usage('2040-06-07', '2040-06-07', v_class, v_room);
  PERFORM _m4_wl_record(
    17, 'projected room usage correct',
    v_row.projected_session_count = 1 AND v_row.projected_booked_minutes = 90
  );
END $$;

-- 18: materialized room suppresses projected duplicate
DO $$
DECLARE v_room uuid; v_class uuid; v_row record;
BEGIN
  PERFORM _m4_wl_as_super();
  PERFORM _m4_wl_make_session('WL18 RoomDedup', '2040-01-21',
    timestamptz '2040-01-21 09:00:00+07', timestamptz '2040-01-21 10:00:00+07', 'scheduled');
  SELECT room_id, class_id INTO v_room, v_class FROM _m4_wl_last;
  PERFORM _m4_wl_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT * INTO v_row FROM public.list_room_usage('2040-01-21', '2040-01-21', v_class, v_room);
  PERFORM _m4_wl_record(
    18, 'materialized room suppresses projected duplicate',
    v_row.materialized_session_count = 1 AND v_row.projected_session_count = 0
  );
END $$;

-- 19: room change moves usage to new room
DO $$
DECLARE v_session uuid; v_old uuid; v_new uuid; v_row_old record; v_row_new record;
BEGIN
  PERFORM _m4_wl_as_super();
  v_session := _m4_wl_make_session('WL19 RoomChg', '2040-01-22',
    timestamptz '2040-01-22 09:00:00+07', timestamptz '2040-01-22 10:00:00+07', 'scheduled');
  SELECT room_id INTO v_old FROM _m4_wl_last;
  v_new := _m4_wl_new_room('WL19 NewRoom');
  PERFORM _m4_wl_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.change_session_room(v_session, v_new, 'Move room');
  SELECT * INTO v_row_old FROM public.list_room_usage('2040-01-22', '2040-01-22', NULL, v_old);
  SELECT * INTO v_row_new FROM public.list_room_usage('2040-01-22', '2040-01-22', NULL, v_new);
  PERFORM _m4_wl_record(
    19, 'room change moves usage to new room',
    v_row_old.materialized_session_count = 0 AND v_row_new.materialized_session_count = 1
  );
END $$;

-- 20: cancelled session excluded from room booked minutes
DO $$
DECLARE v_room uuid; v_row record;
BEGIN
  PERFORM _m4_wl_as_super();
  PERFORM _m4_wl_make_session('WL20 RoomCancel', '2040-01-23',
    timestamptz '2040-01-23 09:00:00+07', timestamptz '2040-01-23 10:00:00+07', 'cancelled');
  SELECT room_id INTO v_room FROM _m4_wl_last;
  PERFORM _m4_wl_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT * INTO v_row FROM public.list_room_usage('2040-01-23', '2040-01-23', NULL, v_room);
  PERFORM _m4_wl_record(
    20, 'cancelled session excluded from room booked minutes',
    v_row.materialized_booked_minutes = 0 AND v_row.cancelled_session_count = 1
  );
END $$;

-- 21: roomless schedule not attributed
DO $$
DECLARE v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_class uuid; v_gaps record;
BEGIN
  PERFORM _m4_wl_as_super();
  v_class := _m4_wl_new_class('WL21 NoRoom', '2040-07-01', '2040-07-31');
  INSERT INTO class_schedule (
    organization_id, class_id, weekday_code, start_time, end_time,
    effective_from, teacher_id, status
  ) VALUES (v_org, v_class, 'fri', '09:00', '10:00', '2040-07-01', _m4_wl_new_teacher('WL21T'), 'active');
  PERFORM _m4_wl_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT * INTO v_gaps FROM public.get_operational_planning_gaps('2040-07-06', '2040-07-06', v_class);
  PERFORM _m4_wl_record(21, 'roomless schedule not attributed', v_gaps.roomless_projected_session_count = 1);
END $$;

-- 22: cross-org teacher data excluded (invalid filter)
SELECT _m4_wl_expect_fail(22, 'cross-org teacher data excluded', $$
  DO $inner$
  DECLARE v_other uuid;
  BEGIN
    PERFORM _m4_wl_as_super();
    v_other := _m4_wl_new_teacher('WL22B', 'b0000000-0000-4000-8000-000000000001');
    PERFORM _m4_wl_as_auth('a1111111-1111-4111-8111-111111111111');
    PERFORM public.list_teacher_workload('2040-01-01', '2040-01-31', NULL, v_other);
  END $inner$;
$$);

-- 23: cross-org room data excluded
SELECT _m4_wl_expect_fail(23, 'cross-org room data excluded', $$
  DO $inner$
  DECLARE v_other uuid;
  BEGIN
    PERFORM _m4_wl_as_super();
    v_other := _m4_wl_new_room('WL23B', 'b0000000-0000-4000-8000-000000000001');
    PERFORM _m4_wl_as_auth('a1111111-1111-4111-8111-111111111111');
    PERFORM public.list_room_usage('2040-01-01', '2040-01-31', NULL, v_other);
  END $inner$;
$$);

-- 24: teacher filter works
DO $$
DECLARE v_teacher uuid; v_other uuid; v_cnt integer;
BEGIN
  PERFORM _m4_wl_as_super();
  PERFORM _m4_wl_make_session('WL24 Filter', '2040-01-24',
    timestamptz '2040-01-24 09:00:00+07', timestamptz '2040-01-24 10:00:00+07', 'scheduled');
  SELECT teacher_id INTO v_teacher FROM _m4_wl_last;
  v_other := _m4_wl_new_teacher('WL24Other');
  PERFORM _m4_wl_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_cnt FROM public.list_teacher_workload('2040-01-24', '2040-01-24', NULL, v_other);
  PERFORM _m4_wl_record(24, 'teacher filter works', v_cnt = 1);
END $$;

-- 25: room filter works
DO $$
DECLARE v_room uuid; v_other uuid; v_cnt integer;
BEGIN
  PERFORM _m4_wl_as_super();
  PERFORM _m4_wl_make_session('WL25 RoomFilt', '2040-01-25',
    timestamptz '2040-01-25 09:00:00+07', timestamptz '2040-01-25 10:00:00+07', 'scheduled');
  SELECT room_id INTO v_room FROM _m4_wl_last;
  v_other := _m4_wl_new_room('WL25Other');
  PERFORM _m4_wl_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_cnt FROM public.list_room_usage('2040-01-25', '2040-01-25', NULL, v_other);
  PERFORM _m4_wl_record(25, 'room filter works', v_cnt = 1);
END $$;

-- 26: class filter works
DO $$
DECLARE v_class uuid; v_other uuid; v_row record;
BEGIN
  PERFORM _m4_wl_as_super();
  PERFORM _m4_wl_make_session('WL26 ClassFilt', '2040-01-26',
    timestamptz '2040-01-26 09:00:00+07', timestamptz '2040-01-26 10:00:00+07', 'scheduled');
  SELECT class_id INTO v_class FROM _m4_wl_last;
  v_other := _m4_wl_new_class('WL26 Other', '2040-01-01', '2040-12-31');
  PERFORM _m4_wl_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT * INTO v_row FROM public.list_teacher_workload('2040-01-26', '2040-01-26', v_other, NULL);
  PERFORM _m4_wl_record(
    26, 'class filter works where supported',
    (SELECT materialized_session_count FROM public.list_teacher_workload('2040-01-26', '2040-01-26', v_class, NULL) LIMIT 1) >= 1
      AND NOT EXISTS (
        SELECT 1 FROM public.list_teacher_workload('2040-01-26', '2040-01-26', v_other, NULL)
        WHERE materialized_session_count > 0
      )
  );
END $$;

-- 27: organization timezone date boundary correct
DO $$
DECLARE v_teacher uuid; v_cnt integer;
BEGIN
  PERFORM _m4_wl_as_super();
  -- 2040-01-27 17:00 UTC = 2040-01-28 00:00 in Asia/Ho_Chi_Minh (+7)
  PERFORM _m4_wl_make_session('WL27 TZ', '2040-01-27',
    timestamptz '2040-01-27 17:00:00+00', timestamptz '2040-01-27 18:00:00+00', 'scheduled');
  SELECT teacher_id INTO v_teacher FROM _m4_wl_last;
  PERFORM _m4_wl_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT materialized_session_count INTO v_cnt
  FROM public.list_teacher_workload('2040-01-28', '2040-01-28', NULL, v_teacher);
  PERFORM _m4_wl_record(27, 'organization timezone date boundary correct', v_cnt = 1);
END $$;

-- 28: date range maximum enforced
SELECT _m4_wl_expect_fail(28, 'date range maximum enforced', $$
  DO $inner$
  BEGIN
    PERFORM _m4_wl_as_auth('a1111111-1111-4111-8111-111111111111');
    PERFORM public.list_teacher_workload('2040-01-01', '2041-01-02', NULL, NULL);
  END $inner$;
$$);

-- 29: active zero-workload teacher behavior correct
DO $$
DECLARE v_idle uuid; v_row record;
BEGIN
  PERFORM _m4_wl_as_super();
  v_idle := _m4_wl_new_teacher('WL29 Idle');
  PERFORM _m4_wl_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT * INTO v_row FROM public.list_teacher_workload('2040-01-01', '2040-01-07', NULL, v_idle);
  PERFORM _m4_wl_record(
    29, 'active zero-workload teacher behavior correct',
    v_row.materialized_session_count = 0 AND v_row.projected_session_count = 0
  );
END $$;

-- 30: active zero-usage room behavior correct
DO $$
DECLARE v_idle uuid; v_row record;
BEGIN
  PERFORM _m4_wl_as_super();
  v_idle := _m4_wl_new_room('WL30 Idle');
  PERFORM _m4_wl_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT * INTO v_row FROM public.list_room_usage('2040-01-01', '2040-01-07', NULL, v_idle);
  PERFORM _m4_wl_record(
    30, 'active zero-usage room behavior correct',
    v_row.materialized_session_count = 0 AND v_row.projected_session_count = 0
  );
END $$;

-- 31: T06 history rows do not duplicate aggregates
DO $$
DECLARE v_session uuid; v_teacher uuid; v_row record;
BEGIN
  PERFORM _m4_wl_as_super();
  v_session := _m4_wl_make_session('WL31 History', '2040-01-28',
    timestamptz '2040-01-28 09:00:00+07', timestamptz '2040-01-28 10:00:00+07', 'scheduled');
  SELECT teacher_id INTO v_teacher FROM _m4_wl_last;
  PERFORM _m4_wl_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.reschedule_teaching_session(
    v_session, timestamptz '2040-01-28 11:00:00+07', timestamptz '2040-01-28 12:00:00+07', 'H1');
  PERFORM public.reschedule_teaching_session(
    v_session, timestamptz '2040-01-28 13:00:00+07', timestamptz '2040-01-28 14:00:00+07', 'H2');
  SELECT * INTO v_row FROM public.list_teacher_workload('2040-01-28', '2040-01-28', NULL, v_teacher);
  PERFORM _m4_wl_record(31, 'T06 history rows do not duplicate aggregates', v_row.materialized_session_count = 1);
END $$;

-- 32: current session state is authoritative
DO $$
DECLARE v_session uuid; v_teacher uuid; v_row record;
BEGIN
  PERFORM _m4_wl_as_super();
  v_session := _m4_wl_make_session('WL32 State', '2040-01-29',
    timestamptz '2040-01-29 09:00:00+07', timestamptz '2040-01-29 10:00:00+07', 'scheduled');
  SELECT teacher_id INTO v_teacher FROM _m4_wl_last;
  PERFORM _m4_wl_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.cancel_teaching_session(v_session, 'Cancel');
  SELECT * INTO v_row FROM public.list_teacher_workload('2040-01-29', '2040-01-29', NULL, v_teacher);
  PERFORM _m4_wl_record(
    32, 'current session state is authoritative',
    v_row.materialized_scheduled_minutes = 0 AND v_row.cancelled_session_count = 1
  );
END $$;

-- 33: completed historical session remains counted in historical requested period
DO $$
DECLARE v_teacher uuid; v_row record;
BEGIN
  PERFORM _m4_wl_as_super();
  PERFORM _m4_wl_make_session('WL33 Hist', '2040-01-30',
    timestamptz '2040-01-30 09:00:00+07', timestamptz '2040-01-30 10:00:00+07', 'completed');
  SELECT teacher_id INTO v_teacher FROM _m4_wl_last;
  PERFORM _m4_wl_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT * INTO v_row FROM public.list_teacher_workload('2040-01-01', '2040-01-31', NULL, v_teacher);
  PERFORM _m4_wl_record(33, 'completed historical session remains counted in historical requested period', v_row.completed_session_count >= 1);
END $$;

-- 34: future projected occurrence respects schedule effective bounds
DO $$
DECLARE v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_class uuid; v_teacher uuid; v_cnt integer;
BEGIN
  PERFORM _m4_wl_as_super();
  v_class := _m4_wl_new_class('WL34 Bounds', '2040-08-01', '2040-08-31');
  v_teacher := _m4_wl_new_teacher('WL34');
  INSERT INTO class_schedule (
    organization_id, class_id, weekday_code, start_time, end_time,
    effective_from, effective_to, teacher_id, status
  ) VALUES (v_org, v_class, 'mon', '09:00', '10:00', '2040-08-01', '2040-08-12', v_teacher, 'active');
  PERFORM _m4_wl_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT projected_session_count INTO v_cnt
  FROM public.list_teacher_workload('2040-08-01', '2040-08-31', v_class, v_teacher);
  PERFORM _m4_wl_record(34, 'future projected occurrence respects schedule effective bounds', v_cnt = 1);
END $$;

-- 35: closed class timetable projection behavior remains correct
DO $$
DECLARE v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_class uuid; v_teacher uuid; v_cnt integer;
BEGIN
  PERFORM _m4_wl_as_super();
  v_class := _m4_wl_new_class('WL35 Closed', '2040-09-01', '2040-09-30');
  UPDATE class SET status = 'closed' WHERE id = v_class;
  v_teacher := _m4_wl_new_teacher('WL35');
  INSERT INTO class_schedule (
    organization_id, class_id, weekday_code, start_time, end_time,
    effective_from, teacher_id, status
  ) VALUES (v_org, v_class, 'tue', '09:00', '10:00', '2040-09-01', v_teacher, 'active');
  PERFORM _m4_wl_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT projected_session_count INTO v_cnt
  FROM public.list_teacher_workload('2040-09-01', '2040-09-30', v_class, v_teacher);
  PERFORM _m4_wl_record(35, 'closed/ended timetable projection behavior remains correct', COALESCE(v_cnt, 0) = 0);
END $$;

DO $$
DECLARE v_fail integer;
BEGIN
  SELECT count(*) INTO v_fail FROM _m4_wl_results WHERE result = 'FAIL';
  IF v_fail > 0 THEN
    RAISE EXCEPTION 'M4-T07 workload analytics tests failed: % failure(s)', v_fail;
  END IF;
  RAISE NOTICE 'M4-T07 workload analytics: all % tests passed', (SELECT count(*) FROM _m4_wl_results);
END $$;

ROLLBACK;
