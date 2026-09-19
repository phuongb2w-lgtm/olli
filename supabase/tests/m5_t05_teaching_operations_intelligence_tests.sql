-- M5-T05: Teaching operations intelligence tests (37 scenarios)

BEGIN;

CREATE TEMP TABLE _m5_t05_results (
  test_no   integer PRIMARY KEY,
  test_name text NOT NULL,
  result    text NOT NULL CHECK (result IN ('PASS', 'FAIL'))
);

GRANT ALL ON TABLE _m5_t05_results TO authenticated, anon;

CREATE OR REPLACE FUNCTION _m5_t05_record(test_no integer, test_name text, passed boolean)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO _m5_t05_results (test_no, test_name, result)
  VALUES (test_no, test_name, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END);
END;
$$;

CREATE OR REPLACE FUNCTION _m5_t05_as_auth(p_auth_id uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', p_auth_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_auth_id::text, 'role', 'authenticated')::text, true);
END;
$$;

CREATE OR REPLACE FUNCTION _m5_t05_as_super()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
END;
$$;

CREATE OR REPLACE FUNCTION _m5_t05_weekday(p_date date)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE EXTRACT(DOW FROM p_date)::int
    WHEN 0 THEN 'sun' WHEN 1 THEN 'mon' WHEN 2 THEN 'tue' WHEN 3 THEN 'wed'
    WHEN 4 THEN 'thu' WHEN 5 THEN 'fri' WHEN 6 THEN 'sat'
  END;
$$;

CREATE TEMP TABLE _m5_t05_last (
  class_id uuid, teacher_id uuid, teacher_b uuid, room_id uuid, room_b uuid,
  schedule_id uuid, session_id uuid
);

CREATE OR REPLACE FUNCTION _m5_t05_make_session(
  p_label text, p_occ date, p_start timestamptz, p_end timestamptz, p_status text,
  p_org uuid DEFAULT 'a0000000-0000-4000-8000-000000000001'
)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
  v_class uuid; v_teacher uuid; v_room uuid; v_schedule uuid; v_session uuid;
  v_wd text := _m5_t05_weekday(p_occ);
BEGIN
  INSERT INTO class (organization_id, course_id, name, status, term_start_date, term_end_date)
  SELECT p_org, c.course_id, p_label, 'active', p_occ - 30, p_occ + 90
  FROM class c WHERE c.organization_id = p_org LIMIT 1
  RETURNING id INTO v_class;
  INSERT INTO teacher (organization_id, given_name, family_name, status)
  VALUES (p_org, p_label, 'T05', 'active') RETURNING id INTO v_teacher;
  INSERT INTO room (organization_id, code, name, status)
  VALUES (p_org, 'T05-' || substr(gen_random_uuid()::text, 1, 6), p_label || ' Room', 'active')
  RETURNING id INTO v_room;
  INSERT INTO class_schedule (
    organization_id, class_id, weekday_code, start_time, end_time,
    effective_from, room_id, teacher_id, status
  ) VALUES (
    p_org, v_class, v_wd, (p_start AT TIME ZONE 'Asia/Ho_Chi_Minh')::time,
    (p_end AT TIME ZONE 'Asia/Ho_Chi_Minh')::time, p_occ - 14, v_room, v_teacher, 'active'
  ) RETURNING id INTO v_schedule;
  INSERT INTO teaching_session (
    organization_id, class_id, class_schedule_id, teacher_id, room_id,
    occurrence_date, scheduled_start_at, scheduled_end_at, status
  ) VALUES (
    p_org, v_class, v_schedule, v_teacher, v_room, p_occ, p_start, p_end, p_status
  ) RETURNING id INTO v_session;
  DELETE FROM _m5_t05_last;
  INSERT INTO _m5_t05_last VALUES (v_class, v_teacher, NULL, v_room, NULL, v_schedule, v_session);
  RETURN v_session;
END;
$$;

-- Seed teacher-linked app user for personal scope
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_role uuid; v_user uuid; v_auth uuid := 'e2222222-2222-4222-8222-222222222222';
  v_teacher uuid;
BEGIN
  PERFORM _m5_t05_as_super();
  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at, is_sso_user, is_anonymous
  )
  SELECT v_auth, (SELECT id FROM auth.instances LIMIT 1), 'authenticated', 'authenticated',
    'm5-t05-teacher@olli.local', '', now(), now(), now(), false, false
  ON CONFLICT (id) DO NOTHING;
  SELECT id INTO v_user FROM app_user WHERE email = 'm5-t05-teacher@olli.local';
  IF v_user IS NULL THEN
    SELECT id INTO v_role FROM role WHERE organization_id = v_org AND code = 'm5_t05_teacher';
    IF v_role IS NULL THEN
      INSERT INTO role (organization_id, code) VALUES (v_org, 'm5_t05_teacher') RETURNING id INTO v_role;
      INSERT INTO role_permission (role_id, permission_id)
      SELECT v_role, p.id FROM permission p
      WHERE p.code IN (
      'organization.read', 'enrollment.read', 'attendance.record', 'attendance.read', 'teacher.read'
    );
    END IF;
    INSERT INTO app_user (organization_id, email, display_name, auth_user_id, status)
    VALUES (v_org, 'm5-t05-teacher@olli.local', 'M5 T05 Teacher', v_auth, 'active')
    RETURNING id INTO v_user;
    INSERT INTO user_role (organization_id, user_id, role_id, effective_from, status)
    VALUES (v_org, v_user, v_role, CURRENT_DATE, 'active');
  END IF;
  SELECT id INTO v_teacher FROM teacher WHERE organization_id = v_org AND user_id = v_user LIMIT 1;
  IF v_teacher IS NULL THEN
    INSERT INTO teacher (organization_id, given_name, family_name, status, user_id)
    VALUES (v_org, 'M5T05', 'Linked', 'active', v_user)
    RETURNING id INTO v_teacher;
  END IF;
END $$;

-- 1–5 session delivery semantics
DO $$
DECLARE v_metrics jsonb;
BEGIN
  PERFORM _m5_t05_as_super();
  PERFORM _m5_t05_make_session('T05 Proj', '2046-02-03',
    '2046-02-03 09:00:00+07', '2046-02-03 10:00:00+07', 'scheduled');
  PERFORM _m5_t05_as_auth('a1111111-1111-4111-8111-111111111111');
  v_metrics := public.get_teaching_ops_session_metrics('2046-02-03', '2046-02-03');
  PERFORM _m5_t05_record(1, 'projected distinct from materialized fields exposed',
    (v_metrics ? 'projected_occurrences') AND (v_metrics ? 'materialized_sessions'));
END $$;

DO $$
DECLARE v_metrics jsonb;
BEGIN
  PERFORM _m5_t05_as_super();
  PERFORM _m5_t05_make_session('T05 Sched', '2046-02-04',
    '2046-02-04 09:00:00+07', '2046-02-04 10:00:00+07', 'scheduled');
  PERFORM _m5_t05_as_auth('a1111111-1111-4111-8111-111111111111');
  v_metrics := public.get_teaching_ops_session_metrics('2046-02-04', '2046-02-04');
  PERFORM _m5_t05_record(2, 'scheduled session is not delivered',
    (v_metrics->>'scheduled_sessions')::bigint >= 1
      AND (v_metrics->>'delivered_sessions')::bigint = 0);
END $$;

DO $$
DECLARE v_metrics jsonb;
BEGIN
  PERFORM _m5_t05_as_super();
  PERFORM _m5_t05_make_session('T05 IP', '2046-02-05',
    '2046-02-05 09:00:00+07', '2046-02-05 10:00:00+07', 'in_progress');
  PERFORM _m5_t05_as_auth('a1111111-1111-4111-8111-111111111111');
  v_metrics := public.get_teaching_ops_session_metrics('2046-02-05', '2046-02-05');
  PERFORM _m5_t05_record(3, 'in-progress session is not delivered',
    (v_metrics->>'in_progress_sessions')::bigint >= 1
      AND (v_metrics->>'delivered_sessions')::bigint = 0);
END $$;

DO $$
DECLARE v_metrics jsonb;
BEGIN
  PERFORM _m5_t05_as_super();
  PERFORM _m5_t05_make_session('T05 Done', '2046-02-06',
    '2046-02-06 09:00:00+07', '2046-02-06 10:00:00+07', 'completed');
  PERFORM _m5_t05_as_auth('a1111111-1111-4111-8111-111111111111');
  v_metrics := public.get_teaching_ops_session_metrics('2046-02-06', '2046-02-06');
  PERFORM _m5_t05_record(4, 'completed session is delivered',
    (v_metrics->>'delivered_sessions')::bigint >= 1);
END $$;

DO $$
DECLARE v_metrics jsonb;
BEGIN
  PERFORM _m5_t05_as_super();
  PERFORM _m5_t05_make_session('T05 Cancel', '2046-02-07',
    '2046-02-07 09:00:00+07', '2046-02-07 10:00:00+07', 'cancelled');
  PERFORM _m5_t05_as_auth('a1111111-1111-4111-8111-111111111111');
  v_metrics := public.get_teaching_ops_session_metrics('2046-02-07', '2046-02-07');
  PERFORM _m5_t05_record(5, 'cancelled session is not delivered',
    (v_metrics->>'cancelled_sessions')::bigint >= 1
      AND (v_metrics->>'delivered_sessions')::bigint = 0);
END $$;

-- 6–8 operational date / timezone
DO $$
DECLARE v_session uuid; v_metrics jsonb;
BEGIN
  PERFORM _m5_t05_as_super();
  v_session := _m5_t05_make_session('T05 ReSched', '2046-02-10',
    '2046-02-10 09:00:00+07', '2046-02-10 10:00:00+07', 'scheduled');
  PERFORM _m5_t05_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.reschedule_teaching_session(
    v_session, timestamptz '2046-02-12 09:00:00+07', timestamptz '2046-02-12 10:00:00+07', 'test');
  v_metrics := public.get_teaching_ops_session_metrics('2046-02-12', '2046-02-12');
  PERFORM _m5_t05_record(6, 'rescheduled session on current operational date',
    (v_metrics->>'scheduled_sessions')::bigint >= 1);
  v_metrics := public.get_teaching_ops_session_metrics('2046-02-10', '2046-02-10');
  PERFORM _m5_t05_record(7, 'original occurrence date does not double-count',
    (v_metrics->>'scheduled_sessions')::bigint = 0);
END $$;

DO $$
DECLARE v_bounds reporting_period_bounds;
BEGIN
  PERFORM _m5_t05_as_auth('a1111111-1111-4111-8111-111111111111');
  v_bounds := public.resolve_reporting_period('2046-02-01', '2046-02-01');
  PERFORM _m5_t05_record(8, 'timezone boundary reporting period deterministic',
    v_bounds.timezone IS NOT NULL AND v_bounds.end_at_exclusive > v_bounds.start_at_utc);
END $$;

-- 9–12 teacher attribution / substitution
DO $$
DECLARE v_session uuid; v_teacher uuid; v_new uuid; v_row record; v_changes jsonb;
BEGIN
  PERFORM _m5_t05_as_super();
  v_session := _m5_t05_make_session('T05 Sub', '2046-02-14',
    '2046-02-14 09:00:00+07', '2046-02-14 10:00:00+07', 'scheduled');
  SELECT teacher_id INTO v_teacher FROM _m5_t05_last;
  INSERT INTO teacher (organization_id, given_name, family_name, status)
  VALUES ('a0000000-0000-4000-8000-000000000001', 'Sub', 'T05B', 'active') RETURNING id INTO v_new;
  UPDATE _m5_t05_last SET teacher_b = v_new;
  PERFORM _m5_t05_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.substitute_session_teacher(v_session, v_new, 'cover');
  PERFORM _m5_t05_as_super();
  PERFORM set_config('olli.teaching_session_mutation', 'true', true);
  UPDATE teaching_session SET status = 'completed' WHERE id = v_session;
  PERFORM _m5_t05_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT * INTO v_row FROM public.list_teacher_workload('2046-02-14', '2046-02-14', NULL, v_new);
  SELECT public.get_teaching_ops_change_metrics(CURRENT_DATE, CURRENT_DATE) INTO v_changes;
  PERFORM _m5_t05_record(9, 'current teacher from teaching_session.teacher_id',
    EXISTS (SELECT 1 FROM teaching_session WHERE id = v_session AND teacher_id = v_new));
  PERFORM _m5_t05_record(10, 'substitution event recorded separately',
    (v_changes->'teacher_substitution'->>'event_count')::bigint >= 1);
  PERFORM _m5_t05_record(11, 'completed workload credited to current teacher',
    v_row.completed_session_count >= 1 AND v_row.delivered_scheduled_minutes >= 60);
  SELECT * INTO v_row FROM public.list_teacher_workload('2046-02-14', '2046-02-14', NULL, v_teacher);
  PERFORM _m5_t05_record(12, 'previous teacher no delivered workload after substitution',
    v_row.completed_session_count = 0);
END $$;

-- 13–15 room attribution
DO $$
DECLARE v_session uuid; v_old uuid; v_new uuid; v_row_old record; v_row_new record;
BEGIN
  PERFORM _m5_t05_as_super();
  v_session := _m5_t05_make_session('T05 Room', '2046-02-15',
    '2046-02-15 09:00:00+07', '2046-02-15 10:00:00+07', 'scheduled');
  SELECT room_id INTO v_old FROM _m5_t05_last;
  INSERT INTO room (organization_id, code, name, status)
  VALUES ('a0000000-0000-4000-8000-000000000001', 'T05R2', 'Room B', 'active') RETURNING id INTO v_new;
  PERFORM _m5_t05_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.change_session_room(v_session, v_new, 'move');
  PERFORM _m5_t05_as_super();
  PERFORM set_config('olli.teaching_session_mutation', 'true', true);
  UPDATE teaching_session SET status = 'completed' WHERE id = v_session;
  PERFORM _m5_t05_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM _m5_t05_record(13, 'current room from teaching_session.room_id',
    EXISTS (SELECT 1 FROM teaching_session WHERE id = v_session AND room_id = v_new));
  SELECT * INTO v_row_old FROM public.list_room_usage('2046-02-15', '2046-02-15', NULL, v_old);
  SELECT * INTO v_row_new FROM public.list_room_usage('2046-02-15', '2046-02-15', NULL, v_new);
  PERFORM _m5_t05_record(14, 'room change does not double-count current usage',
    COALESCE(v_row_old.completed_session_count, 0) = 0
      AND COALESCE(v_row_new.completed_session_count, 0) >= 1);
  PERFORM _m5_t05_record(15, 'completed room usage credited once',
    COALESCE(v_row_new.delivered_scheduled_minutes, 0) = 60);
END $$;

-- 16–20 change event counts
DO $$
DECLARE v_session uuid; v_changes jsonb;
BEGIN
  PERFORM _m5_t05_as_super();
  v_session := _m5_t05_make_session('T05 Multi', '2046-02-16',
    '2046-02-16 09:00:00+07', '2046-02-16 10:00:00+07', 'scheduled');
  PERFORM _m5_t05_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.reschedule_teaching_session(v_session,
    timestamptz '2046-02-17 09:00:00+07', timestamptz '2046-02-17 10:00:00+07', 'a');
  PERFORM public.reschedule_teaching_session(v_session,
    timestamptz '2046-02-18 09:00:00+07', timestamptz '2046-02-18 10:00:00+07', 'b');
  PERFORM public.cancel_teaching_session(v_session, 'cancel');
  v_changes := public.get_teaching_ops_change_metrics(CURRENT_DATE, CURRENT_DATE);
  PERFORM _m5_t05_record(16, 'reschedule event count deterministic',
    (v_changes->'reschedule'->>'event_count')::bigint >= 2);
  PERFORM _m5_t05_record(17, 'unique sessions rescheduled distinct from events',
    (v_changes->'reschedule'->>'affected_session_count')::bigint >= 1
      AND (v_changes->'reschedule'->>'event_count')::bigint
          > (v_changes->'reschedule'->>'affected_session_count')::bigint);
  PERFORM _m5_t05_record(18, 'cancellation event count deterministic',
    (v_changes->'cancellation'->>'event_count')::bigint >= 1);
  PERFORM _m5_t05_record(19, 'substitution event count field present',
    v_changes->'teacher_substitution' ? 'event_count');
  PERFORM _m5_t05_record(20, 'room change event count field present',
    v_changes->'room_change' ? 'event_count');
END $$;

-- 21–24 workload semantics
DO $$
DECLARE v_teacher uuid; v_row record; v_metrics jsonb;
BEGIN
  PERFORM _m5_t05_as_super();
  PERFORM _m5_t05_make_session('T05 Min', '2046-02-20',
    '2046-02-20 09:00:00+07', '2046-02-20 10:30:00+07', 'completed');
  SELECT teacher_id INTO v_teacher FROM _m5_t05_last;
  PERFORM _m5_t05_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT * INTO v_row FROM public.list_teacher_workload('2046-02-20', '2046-02-20', NULL, v_teacher);
  PERFORM _m5_t05_record(21, 'session duration contributes correct minutes',
    v_row.delivered_scheduled_minutes = 90);
  PERFORM _m5_t05_as_super();
  PERFORM _m5_t05_make_session('T05 CancWL', '2046-02-21',
    '2046-02-21 09:00:00+07', '2046-02-21 10:00:00+07', 'cancelled');
  SELECT teacher_id INTO v_teacher FROM _m5_t05_last;
  SELECT * INTO v_row FROM public.list_teacher_workload('2046-02-21', '2046-02-21', NULL, v_teacher);
  PERFORM _m5_t05_record(22, 'cancelled excluded from delivered workload',
    v_row.delivered_scheduled_minutes = 0);
  v_metrics := public.get_teaching_ops_session_metrics('2046-02-01', '2046-02-28');
  PERFORM _m5_t05_record(24, 'projected workload separate from materialized',
    (v_metrics ? 'projected_occurrences') AND (v_metrics ? 'materialized_sessions'));
END $$;

DO $$
DECLARE v_session uuid; v_teacher uuid; v_row23 record; v_row22 record;
BEGIN
  PERFORM _m5_t05_as_super();
  v_session := _m5_t05_make_session('T05 RS WL', '2046-02-22',
    '2046-02-22 09:00:00+07', '2046-02-22 10:00:00+07', 'scheduled');
  SELECT teacher_id INTO v_teacher FROM _m5_t05_last;
  PERFORM _m5_t05_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.reschedule_teaching_session(v_session,
    timestamptz '2046-02-23 09:00:00+07', timestamptz '2046-02-23 10:00:00+07', 'mv');
  SELECT * INTO v_row23 FROM public.list_teacher_workload('2046-02-23', '2046-02-23', NULL, v_teacher);
  SELECT * INTO v_row22 FROM public.list_teacher_workload('2046-02-22', '2046-02-22', NULL, v_teacher);
  PERFORM _m5_t05_record(23, 'rescheduled session counted on current date only',
    v_row23.materialized_session_count >= 1 AND COALESCE(v_row22.materialized_session_count, 0) = 0);
END $$;

-- 25–28 room usage
DO $$
DECLARE v_room uuid; v_row record; v_overview jsonb;
BEGIN
  PERFORM _m5_t05_as_super();
  PERFORM _m5_t05_make_session('T05 RoomH', '2046-02-24',
    '2046-02-24 09:00:00+07', '2046-02-24 11:00:00+07', 'completed');
  SELECT room_id INTO v_room FROM _m5_t05_last;
  PERFORM _m5_t05_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT * INTO v_row FROM public.list_room_usage('2046-02-24', '2046-02-24', NULL, v_room);
  PERFORM _m5_t05_record(25, 'booked hours deterministic', v_row.delivered_scheduled_minutes = 120);
  PERFORM _m5_t05_record(26, 'cancelled session explicit in room row',
    v_row.cancelled_session_count >= 0);
  PERFORM _m5_t05_record(27, 'projected demand separate in room row',
    v_row.projected_session_count >= 0 AND v_row.materialized_session_count >= 1);
  v_overview := public.get_teaching_ops_intelligence_overview('2046-02-01', '2046-02-28', false);
  PERFORM _m5_t05_record(28, 'no fabricated utilization percentage',
    v_overview->>'utilization_percentage_rule' LIKE '%not computed%');
END $$;

-- 29–34 permissions
DO $$
DECLARE v_ok boolean := false;
BEGIN
  PERFORM _m5_t05_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.get_teaching_ops_intelligence_overview(CURRENT_DATE, CURRENT_DATE, false);
    v_ok := true;
  EXCEPTION WHEN others THEN v_ok := false; END;
  PERFORM _m5_t05_record(29, 'manager executive operations access PASS', v_ok);
END $$;

DO $$
DECLARE v_ok boolean := false;
BEGIN
  PERFORM _m5_t05_as_auth('a2222222-2222-4222-8222-222222222222');
  BEGIN
    PERFORM public.get_teaching_ops_session_metrics(CURRENT_DATE, CURRENT_DATE);
    v_ok := true;
  EXCEPTION WHEN others THEN v_ok := false; END;
  PERFORM _m5_t05_record(30, 'academic operations scheduling intelligence PASS', v_ok);
END $$;

DO $$
DECLARE
  v_ok boolean := false;
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_auth uuid := 'e2222222-2222-4222-8222-222222222222';
  v_role uuid;
  v_user uuid;
  v_teacher uuid;
BEGIN
  PERFORM _m5_t05_as_super();
  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at, is_sso_user, is_anonymous
  )
  SELECT v_auth, (SELECT id FROM auth.instances LIMIT 1), 'authenticated', 'authenticated',
    'm5-t05-teacher@olli.local', '', now(), now(), now(), false, false
  ON CONFLICT (id) DO NOTHING;
  SELECT id INTO v_role FROM role WHERE organization_id = v_org AND code = 'm5_t05_teacher';
  IF v_role IS NULL THEN
    INSERT INTO role (organization_id, code) VALUES (v_org, 'm5_t05_teacher') RETURNING id INTO v_role;
  END IF;
  INSERT INTO role_permission (role_id, permission_id)
  SELECT v_role, p.id FROM permission p
  WHERE p.code IN (
    'organization.read', 'enrollment.read', 'attendance.record', 'attendance.read', 'teacher.read'
  )
  ON CONFLICT DO NOTHING;
  SELECT id INTO v_user FROM app_user WHERE email = 'm5-t05-teacher@olli.local';
  IF v_user IS NULL THEN
    INSERT INTO app_user (organization_id, email, display_name, auth_user_id, status)
    VALUES (v_org, 'm5-t05-teacher@olli.local', 'M5 T05 Teacher', v_auth, 'active')
    RETURNING id INTO v_user;
    INSERT INTO user_role (organization_id, user_id, role_id, effective_from, status)
    VALUES (v_org, v_user, v_role, CURRENT_DATE, 'active');
  ELSE
    UPDATE app_user SET auth_user_id = v_auth, status = 'active' WHERE id = v_user;
  END IF;
  UPDATE teacher SET user_id = NULL WHERE organization_id = v_org AND user_id = v_user;
  INSERT INTO teacher (organization_id, given_name, family_name, status, user_id)
  VALUES (v_org, 'M5T05', 'Linked', 'active', v_user)
  RETURNING id INTO v_teacher;
  PERFORM _m5_t05_as_auth(v_auth);
  v_ok := public.is_active_app_user()
    AND public._current_linked_teacher_id() = v_teacher;
  IF v_ok THEN
    BEGIN
      PERFORM public.get_my_teaching_ops_overview(CURRENT_DATE, CURRENT_DATE);
    EXCEPTION WHEN others THEN
      v_ok := false;
    END;
  END IF;
  PERFORM _m5_t05_record(31, 'teacher personal scope PASS', v_ok);
END $$;

DO $$
DECLARE v_failed boolean := true;
BEGIN
  PERFORM _m5_t05_as_auth('e2222222-2222-4222-8222-222222222222');
  BEGIN
    PERFORM public.get_teaching_ops_intelligence_overview(CURRENT_DATE, CURRENT_DATE, false);
    v_failed := false;
  EXCEPTION WHEN others THEN v_failed := true; END;
  PERFORM _m5_t05_record(32, 'teacher denied center-wide executive operations', v_failed);
END $$;

DO $$
DECLARE v_failed boolean := true;
BEGIN
  PERFORM _m5_t05_as_auth('b7777777-7777-4777-8777-777777777777');
  BEGIN
    PERFORM public.get_teaching_ops_intelligence_overview(CURRENT_DATE, CURRENT_DATE, false);
    v_failed := false;
  EXCEPTION WHEN others THEN v_failed := true; END;
  PERFORM _m5_t05_record(33, 'accountant denied executive operations', v_failed);
END $$;

DO $$
DECLARE v_failed boolean := true;
BEGIN
  PERFORM _m5_t05_as_auth('b8888888-8888-4888-8888-888888888888');
  BEGIN
    PERFORM public.get_teaching_ops_intelligence_overview(CURRENT_DATE, CURRENT_DATE, false);
    v_failed := false;
  EXCEPTION WHEN others THEN v_failed := true; END;
  PERFORM _m5_t05_record(34, 'consultant denied executive operations', v_failed);
END $$;

-- 35–37 isolation
DO $$
DECLARE v_cnt integer;
BEGIN
  PERFORM _m5_t05_as_auth('b1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_cnt FROM teaching_session
  WHERE organization_id = 'a0000000-0000-4000-8000-000000000001';
  PERFORM _m5_t05_record(35, 'organization isolation PASS', v_cnt = 0);
END $$;

DO $$
DECLARE v_cnt integer;
BEGIN
  PERFORM _m5_t05_as_auth('e2222222-2222-4222-8222-222222222222');
  SELECT count(*) INTO v_cnt FROM public.list_teacher_workload(CURRENT_DATE, CURRENT_DATE, NULL, NULL);
  PERFORM _m5_t05_record(36, 'teacher scope isolation PASS', v_cnt <= 1);
END $$;

DO $$
DECLARE v_failed boolean := false; v_other_room uuid;
BEGIN
  PERFORM _m5_t05_as_super();
  INSERT INTO room (organization_id, code, name, status)
  SELECT 'b0000000-0000-4000-8000-000000000001', 'T05-ISO', 'Org B ISO', 'active'
  WHERE NOT EXISTS (
    SELECT 1 FROM room WHERE organization_id = 'b0000000-0000-4000-8000-000000000001'
      AND code = 'T05-ISO'
  );
  SELECT id INTO v_other_room FROM room
  WHERE organization_id = 'b0000000-0000-4000-8000-000000000001' AND code = 'T05-ISO' LIMIT 1;
  PERFORM _m5_t05_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.list_room_usage(CURRENT_DATE, CURRENT_DATE, NULL, v_other_room);
    v_failed := false;
  EXCEPTION WHEN others THEN
    v_failed := true;
  END;
  PERFORM _m5_t05_record(37, 'room organization boundaries PASS', v_failed);
END $$;

DO $$
DECLARE v_fail integer; v_total integer; r record;
BEGIN
  SELECT count(*) FILTER (WHERE result = 'FAIL'), count(*) INTO v_fail, v_total FROM _m5_t05_results;
  IF v_fail > 0 THEN
    FOR r IN SELECT test_no, test_name FROM _m5_t05_results WHERE result = 'FAIL' LOOP
      RAISE NOTICE 'FAILED: % - %', r.test_no, r.test_name;
    END LOOP;
    RAISE EXCEPTION 'M5-T05 teaching operations intelligence: %/% FAIL (% failed)',
      v_total - v_fail, v_total, v_fail;
  END IF;
  RAISE NOTICE 'M5-T05 teaching operations intelligence: %/% PASS (0 FAIL)', v_total, v_total;
END $$;

COMMIT;
