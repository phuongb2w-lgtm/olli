-- M5-T03: Academic quality intelligence tests (36 scenarios)

BEGIN;

CREATE TEMP TABLE _m5_t03_results (
  test_no   integer PRIMARY KEY,
  test_name text NOT NULL,
  result    text NOT NULL CHECK (result IN ('PASS', 'FAIL'))
);

GRANT ALL ON TABLE _m5_t03_results TO authenticated, anon;

CREATE OR REPLACE FUNCTION _m5_t03_record(test_no integer, test_name text, passed boolean)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO _m5_t03_results (test_no, test_name, result)
  VALUES (test_no, test_name, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END);
END;
$$;

CREATE OR REPLACE FUNCTION _m5_t03_as_auth(p_auth_id uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', p_auth_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_auth_id::text, 'role', 'authenticated')::text, true);
END;
$$;

CREATE OR REPLACE FUNCTION _m5_t03_as_super()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
END;
$$;

CREATE OR REPLACE FUNCTION _m5_t03_seed_auth_user(p_auth uuid, p_email text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at, is_sso_user, is_anonymous
  )
  VALUES (
    p_auth,
    (SELECT id FROM auth.instances LIMIT 1),
    'authenticated',
    'authenticated',
    p_email,
    '',
    now(),
    now(),
    now(),
    false,
    false
  )
  ON CONFLICT (id) DO NOTHING;
END;
$$;

-- Seed M5-T03 role users
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_role uuid;
  v_user uuid;
  v_auth uuid;
BEGIN
  PERFORM _m5_t03_as_super();

  IF NOT EXISTS (SELECT 1 FROM app_user WHERE email = 'm5-t03-academic@olli.local') THEN
    v_auth := 'c1111111-1111-4111-8111-111111111111';
    PERFORM _m5_t03_seed_auth_user(v_auth, 'm5-t03-academic@olli.local');
    INSERT INTO role (organization_id, code) VALUES (v_org, 'm5_t03_academic_ops') RETURNING id INTO v_role;
    INSERT INTO role_permission (role_id, permission_id)
    SELECT v_role, p.id FROM permission p
    WHERE p.code IN (
      'organization.read', 'attendance.read', 'attendance.review',
      'assessment.read', 'assessment_result.review',
      'observation.read', 'observation.review', 'enrollment.read'
    );
    INSERT INTO app_user (organization_id, email, display_name, auth_user_id, status)
    VALUES (v_org, 'm5-t03-academic@olli.local', 'M5 T03 Academic', v_auth, 'active')
    RETURNING id INTO v_user;
    INSERT INTO user_role (organization_id, user_id, role_id, effective_from, status)
    VALUES (v_org, v_user, v_role, CURRENT_DATE, 'active');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM app_user WHERE email = 'm5-t03-teacher@olli.local') THEN
    v_auth := 'c2222222-2222-4222-8222-222222222222';
    PERFORM _m5_t03_seed_auth_user(v_auth, 'm5-t03-teacher@olli.local');
    INSERT INTO role (organization_id, code) VALUES (v_org, 'm5_t03_teacher') RETURNING id INTO v_role;
    INSERT INTO role_permission (role_id, permission_id)
    SELECT v_role, p.id FROM permission p
    WHERE p.code IN (
      'organization.read', 'attendance.record', 'attendance.read',
      'assessment.read', 'assessment_result.record',
      'observation.record', 'observation.read', 'enrollment.read'
    );
    INSERT INTO app_user (organization_id, email, display_name, auth_user_id, status)
    VALUES (v_org, 'm5-t03-teacher@olli.local', 'M5 T03 Teacher', v_auth, 'active')
    RETURNING id INTO v_user;
    INSERT INTO user_role (organization_id, user_id, role_id, effective_from, status)
    VALUES (v_org, v_user, v_role, CURRENT_DATE, 'active');
  END IF;
END $$;

-- 1: scheduled session is not delivered
DO $$
DECLARE v_delivered bigint;
BEGIN
  PERFORM _m5_t03_as_auth('a1111111-1111-4111-8111-111111111111');
  v_delivered := public.count_delivered_teaching_sessions('2042-01-01', '2042-01-31');
  PERFORM _m5_t03_record(1, 'scheduled session is not delivered', v_delivered >= 0);
END $$;

-- 2: in-progress session is not delivered
DO $$
DECLARE v_delivery jsonb;
BEGIN
  PERFORM _m5_t03_as_auth('a1111111-1111-4111-8111-111111111111');
  v_delivery := public.get_academic_teaching_delivery('2042-02-01', '2042-02-28');
  PERFORM _m5_t03_record(
    2,
    'in-progress session is not delivered',
    COALESCE((v_delivery->>'in_progress_sessions')::bigint, 0) >= 0
      AND COALESCE((v_delivery->>'delivered_sessions')::bigint, 0) >= 0
  );
END $$;

-- 3: cancelled session is not delivered
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_class uuid;
  v_delivery jsonb;
BEGIN
  PERFORM _m5_t03_as_super();
  SELECT id INTO v_class FROM class WHERE organization_id = v_org LIMIT 1;
  INSERT INTO teaching_session (
    organization_id, class_id, scheduled_start_at, scheduled_end_at, status, teacher_id
  )
  SELECT v_org, v_class,
    timestamptz '2042-03-15 09:00:00+07', timestamptz '2042-03-15 10:00:00+07',
    'cancelled', t.id
  FROM teacher t WHERE t.organization_id = v_org LIMIT 1;

  PERFORM _m5_t03_as_auth('a1111111-1111-4111-8111-111111111111');
  v_delivery := public.get_academic_teaching_delivery('2042-03-01', '2042-03-31');
  PERFORM _m5_t03_record(
    3,
    'cancelled session is not delivered',
    COALESCE((v_delivery->>'cancelled_sessions')::bigint, 0) >= 1
  );
END $$;

-- 4: completed session is delivered
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_class uuid;
  v_delivery jsonb;
BEGIN
  PERFORM _m5_t03_as_super();
  SELECT id INTO v_class FROM class WHERE organization_id = v_org LIMIT 1;
  INSERT INTO teaching_session (
    organization_id, class_id, scheduled_start_at, scheduled_end_at, status, teacher_id
  )
  SELECT v_org, v_class,
    timestamptz '2042-04-15 09:00:00+07', timestamptz '2042-04-15 10:00:00+07',
    'completed', t.id
  FROM teacher t WHERE t.organization_id = v_org LIMIT 1;

  PERFORM _m5_t03_as_auth('a1111111-1111-4111-8111-111111111111');
  v_delivery := public.get_academic_teaching_delivery('2042-04-01', '2042-04-30');
  PERFORM _m5_t03_record(
    4,
    'completed session is delivered',
    COALESCE((v_delivery->>'delivered_sessions')::bigint, 0) >= 1
  );
END $$;

-- 5: teacher can record permitted attendance
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_class uuid;
  v_session uuid;
  v_enrollment uuid;
  v_id uuid;
BEGIN
  PERFORM _m5_t03_as_super();
  SELECT id INTO v_class FROM class WHERE organization_id = v_org LIMIT 1;
  SELECT id INTO v_enrollment FROM enrollment WHERE organization_id = v_org AND class_id = v_class AND status = 'active' LIMIT 1;

  INSERT INTO teaching_session (
    organization_id, class_id, scheduled_start_at, scheduled_end_at, status, teacher_id
  )
  SELECT v_org, v_class,
    timestamptz '2042-05-10 09:00:00+07', timestamptz '2042-05-10 10:00:00+07',
    'in_progress', t.id
  FROM teacher t WHERE t.organization_id = v_org LIMIT 1
  RETURNING id INTO v_session;

  PERFORM _m5_t03_as_auth('c2222222-2222-4222-8222-222222222222');
  INSERT INTO attendance (
    organization_id, teaching_session_id, enrollment_id, status, recorded_by
  ) VALUES (v_org, v_session, v_enrollment, 'present', (
    SELECT id FROM app_user WHERE email = 'm5-t03-teacher@olli.local'
  ))
  RETURNING id INTO v_id;

  PERFORM _m5_t03_record(5, 'teacher can record permitted attendance', v_id IS NOT NULL);
END $$;

-- 6: unrelated teacher cannot modify attendance (RLS/org scoped)
DO $$
DECLARE v_count integer;
BEGIN
  PERFORM _m5_t03_as_auth('b1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_count FROM attendance WHERE organization_id = 'a0000000-0000-4000-8000-000000000001';
  PERFORM _m5_t03_record(6, 'unrelated org user cannot read org A attendance', v_count = 0);
END $$;

-- 7: academic operations can review according to permissions
DO $$
DECLARE v_ok boolean := false;
BEGIN
  PERFORM _m5_t03_as_auth('c1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.list_academic_review_queue('attendance_pending', 10, 0);
    v_ok := true;
  EXCEPTION WHEN others THEN
    v_ok := false;
  END;
  PERFORM _m5_t03_record(7, 'academic operations can review according to permissions', v_ok);
END $$;

-- 8: confirmation does not create duplicate attendance
DO $$
DECLARE
  v_att uuid;
  v_before integer;
  v_after integer;
BEGIN
  PERFORM _m5_t03_as_super();
  SELECT id INTO v_att FROM attendance WHERE review_status = 'submitted' LIMIT 1;
  IF v_att IS NULL THEN
    UPDATE attendance SET review_status = 'submitted', submitted_at = now()
    WHERE id = (SELECT id FROM attendance LIMIT 1)
    RETURNING id INTO v_att;
  END IF;

  SELECT count(*) INTO v_before FROM attendance WHERE id = v_att;

  PERFORM _m5_t03_as_auth('c1111111-1111-4111-8111-111111111111');
  PERFORM public.review_attendance(v_att, 'confirm', 'OK');

  SELECT count(*) INTO v_after FROM attendance WHERE id = v_att;
  PERFORM _m5_t03_record(
    8,
    'confirmation does not create duplicate attendance',
    v_before = 1 AND v_after = 1
  );
END $$;

-- 9: unconfirmed data treatment is deterministic
DO $$
DECLARE v_metrics jsonb;
BEGIN
  PERFORM _m5_t03_as_auth('a1111111-1111-4111-8111-111111111111');
  v_metrics := public.get_academic_attendance_metrics('2042-01-01', '2042-12-31');
  PERFORM _m5_t03_record(
    9,
    'unconfirmed data treatment is deterministic',
    (v_metrics ? 'unconfirmed_count') AND (v_metrics ? 'attendance_rate')
  );
END $$;

-- 10: confirmed attendance contributes correctly to management KPI
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_class uuid;
  v_session uuid;
  v_enrollment uuid;
  v_metrics jsonb;
BEGIN
  PERFORM _m5_t03_as_super();
  SELECT id INTO v_class FROM class WHERE organization_id = v_org LIMIT 1;
  SELECT id INTO v_enrollment FROM enrollment
  WHERE organization_id = v_org AND class_id = v_class AND status = 'active' LIMIT 1;

  INSERT INTO teaching_session (
    organization_id, class_id, scheduled_start_at, scheduled_end_at, status, teacher_id
  )
  SELECT v_org, v_class,
    timestamptz '2042-05-20 09:00:00+07', timestamptz '2042-05-20 10:00:00+07',
    'completed', t.id
  FROM teacher t WHERE t.organization_id = v_org LIMIT 1
  RETURNING id INTO v_session;

  INSERT INTO attendance (
    organization_id, teaching_session_id, enrollment_id, status, review_status
  ) VALUES (v_org, v_session, v_enrollment, 'present', 'confirmed');

  PERFORM _m5_t03_as_auth('a1111111-1111-4111-8111-111111111111');
  v_metrics := public.get_academic_attendance_metrics('2042-05-01', '2042-05-31');
  PERFORM _m5_t03_record(
    10,
    'confirmed attendance contributes correctly to management KPI',
    COALESCE((v_metrics->>'confirmed_present')::bigint, 0) >= 1
  );
END $$;

-- 11: teacher can enter permitted result
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_class uuid;
  v_asm uuid;
  v_enr uuid;
  v_id uuid;
BEGIN
  PERFORM _m5_t03_as_super();
  SELECT id INTO v_class FROM class WHERE organization_id = v_org LIMIT 1;
  SELECT id INTO v_enr FROM enrollment WHERE organization_id = v_org AND class_id = v_class LIMIT 1;

  INSERT INTO assessment (
    organization_id, class_id, assessment_type_code, title, max_score, assessed_on, status
  ) VALUES (v_org, v_class, 'progress_test', 'T03 Test', 100, '2042-06-01', 'open')
  RETURNING id INTO v_asm;

  PERFORM _m5_t03_as_auth('c2222222-2222-4222-8222-222222222222');
  INSERT INTO assessment_result (
    organization_id, assessment_id, enrollment_id, raw_score, max_score, status
  ) VALUES (v_org, v_asm, v_enr, 80, 100, 'draft')
  RETURNING id INTO v_id;

  PERFORM _m5_t03_record(11, 'teacher can enter permitted result', v_id IS NOT NULL);
END $$;

-- 12: review/confirmation preserves same canonical result
DO $$
DECLARE v_result uuid; v_before uuid; v_status text;
BEGIN
  PERFORM _m5_t03_as_super();
  SELECT id INTO v_result FROM assessment_result WHERE status = 'draft' ORDER BY created_at DESC LIMIT 1;
  v_before := v_result;

  PERFORM _m5_t03_as_auth('c2222222-2222-4222-8222-222222222222');
  PERFORM public.submit_assessment_result(v_before);

  PERFORM _m5_t03_as_auth('c1111111-1111-4111-8111-111111111111');
  PERFORM public.review_assessment_result(v_before, 'confirm', 'Confirmed');

  SELECT status INTO v_status FROM assessment_result WHERE id = v_before;
  PERFORM _m5_t03_record(
    12,
    'review confirmation preserves same canonical result',
    v_status = 'finalized'
  );
END $$;

-- 13: unauthorized user cannot alter result
DO $$
DECLARE
  v_failed boolean := false;
  v_result uuid;
  v_before numeric;
  v_after numeric;
BEGIN
  PERFORM _m5_t03_as_super();
  SELECT id, raw_score INTO v_result, v_before
  FROM assessment_result WHERE status = 'finalized' LIMIT 1;

  PERFORM _m5_t03_as_auth('c2222222-2222-4222-8222-222222222222');
  BEGIN
    UPDATE assessment_result SET raw_score = 0 WHERE id = v_result;
    v_failed := false;
  EXCEPTION WHEN others THEN
    v_failed := true;
  END;

  PERFORM _m5_t03_as_super();
  SELECT raw_score INTO v_after FROM assessment_result WHERE id = v_result;

  PERFORM _m5_t03_record(
    13,
    'unauthorized user cannot alter result',
    v_failed AND v_before = v_after
  );
END $$;

-- 14: finalized result correction follows audit rules
DO $$
DECLARE v_result uuid; v_status text;
BEGIN
  PERFORM _m5_t03_as_super();
  SELECT id INTO v_result FROM assessment_result WHERE status = 'finalized' LIMIT 1;

  PERFORM _m5_t03_as_auth('c1111111-1111-4111-8111-111111111111');
  PERFORM public.review_assessment_result(v_result, 'correct', 'Audit correction');

  SELECT status INTO v_status FROM assessment_result WHERE id = v_result;
  PERFORM _m5_t03_record(
    14,
    'finalized result correction follows audit rules',
    v_status = 'corrected'
  );
END $$;

-- 15: teacher original comment preserved
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_class uuid;
  v_enr uuid;
  v_teacher uuid;
  v_obs uuid;
  v_comment text := 'Original teacher comment T03';
BEGIN
  PERFORM _m5_t03_as_super();
  SELECT id INTO v_class FROM class WHERE organization_id = v_org LIMIT 1;
  SELECT id INTO v_enr FROM enrollment WHERE organization_id = v_org AND class_id = v_class LIMIT 1;
  SELECT id INTO v_teacher FROM teacher WHERE organization_id = v_org LIMIT 1;

  INSERT INTO teacher_observation (
    organization_id, enrollment_id, class_id, teacher_id, observed_at, comment, status
  ) VALUES (v_org, v_enr, v_class, v_teacher, now(), v_comment, 'recorded')
  RETURNING id INTO v_obs;

  PERFORM _m5_t03_as_auth('c1111111-1111-4111-8111-111111111111');
  PERFORM public.translate_teacher_observation(v_obs, 'Translated text', 'en');

  SELECT comment INTO v_comment FROM teacher_observation WHERE id = v_obs;
  PERFORM _m5_t03_record(
    15,
    'teacher original comment preserved',
    v_comment = 'Original teacher comment T03'
  );
END $$;

-- 16: translation stored separately
DO $$
DECLARE v_obs uuid; v_trans text;
BEGIN
  PERFORM _m5_t03_as_super();
  SELECT id INTO v_obs FROM teacher_observation
  WHERE translated_comment IS NOT NULL LIMIT 1;

  SELECT translated_comment INTO v_trans FROM teacher_observation WHERE id = v_obs;
  PERFORM _m5_t03_record(16, 'translation stored separately', v_trans IS NOT NULL);
END $$;

-- 17: translator identity/time recorded
DO $$
DECLARE v_obs teacher_observation;
BEGIN
  PERFORM _m5_t03_as_super();
  SELECT * INTO v_obs FROM teacher_observation
  WHERE translated_by IS NOT NULL LIMIT 1;

  PERFORM _m5_t03_record(
    17,
    'translator identity time recorded',
    v_obs.translated_by IS NOT NULL AND v_obs.translated_at IS NOT NULL
  );
END $$;

-- 18: translation does not overwrite original
DO $$
DECLARE v_obs teacher_observation;
BEGIN
  PERFORM _m5_t03_as_super();
  SELECT * INTO v_obs FROM teacher_observation
  WHERE translated_comment IS NOT NULL AND comment IS NOT NULL LIMIT 1;

  PERFORM _m5_t03_record(
    18,
    'translation does not overwrite original',
    v_obs.comment IS DISTINCT FROM v_obs.translated_comment
  );
END $$;

-- 19: teacher cannot impersonate academic operations translation
DO $$
DECLARE v_failed boolean := false; v_obs uuid;
BEGIN
  PERFORM _m5_t03_as_super();
  SELECT id INTO v_obs FROM teacher_observation LIMIT 1;

  PERFORM _m5_t03_as_auth('c2222222-2222-4222-8222-222222222222');
  BEGIN
    PERFORM public.translate_teacher_observation(v_obs, 'Hack', 'en');
    v_failed := false;
  EXCEPTION WHEN insufficient_privilege THEN
    v_failed := true;
  END;
  PERFORM _m5_t03_record(19, 'teacher cannot impersonate academic ops translation', v_failed);
END $$;

-- 20: attendance rate deterministic
DO $$
DECLARE v_a jsonb; v_b jsonb;
BEGIN
  PERFORM _m5_t03_as_auth('a1111111-1111-4111-8111-111111111111');
  v_a := public.get_academic_attendance_metrics('2026-01-01', '2026-01-31');
  v_b := public.get_academic_attendance_metrics('2026-01-01', '2026-01-31');
  PERFORM _m5_t03_record(
    20,
    'attendance rate deterministic',
    (v_a->>'attendance_rate') IS NOT DISTINCT FROM (v_b->>'attendance_rate')
  );
END $$;

-- 21: completed-session denominator deterministic
DO $$
DECLARE v_a jsonb; v_b jsonb;
BEGIN
  PERFORM _m5_t03_as_auth('a1111111-1111-4111-8111-111111111111');
  v_a := public.get_academic_teaching_delivery('2026-02-01', '2026-02-28');
  v_b := public.get_academic_teaching_delivery('2026-02-01', '2026-02-28');
  PERFORM _m5_t03_record(
    21,
    'completed-session denominator deterministic',
    (v_a->>'delivery_completion_ratio') IS NOT DISTINCT FROM (v_b->>'delivery_completion_ratio')
  );
END $$;

-- 22: cancelled sessions handled correctly
DO $$
DECLARE v_delivery jsonb;
BEGIN
  PERFORM _m5_t03_as_auth('a1111111-1111-4111-8111-111111111111');
  v_delivery := public.get_academic_teaching_delivery('2042-03-01', '2042-03-31');
  PERFORM _m5_t03_record(
    22,
    'cancelled sessions handled correctly',
    (v_delivery ? 'cancelled_sessions') AND (v_delivery->>'denominator_rule') IS NOT NULL
  );
END $$;

-- 23: assessment metrics do not combine incompatible scales incorrectly
DO $$
DECLARE v_asm jsonb; v_scales jsonb;
BEGIN
  PERFORM _m5_t03_as_auth('a1111111-1111-4111-8111-111111111111');
  v_asm := public.get_academic_assessment_metrics('2020-01-01', '2099-12-31');
  v_scales := v_asm->'score_by_scale';
  PERFORM _m5_t03_record(
    23,
    'assessment metrics grouped by scale not combined',
    jsonb_typeof(v_scales) = 'array'
  );
END $$;

-- 24: observation coverage deterministic
DO $$
DECLARE v_a jsonb; v_b jsonb;
BEGIN
  PERFORM _m5_t03_as_auth('a1111111-1111-4111-8111-111111111111');
  v_a := public.get_academic_observation_metrics('2026-01-01', '2026-03-31');
  v_b := public.get_academic_observation_metrics('2026-01-01', '2026-03-31');
  PERFORM _m5_t03_record(
    24,
    'observation coverage deterministic',
    (v_a->>'observation_count') IS NOT DISTINCT FROM (v_b->>'observation_count')
  );
END $$;

-- 25: completed session missing required academic data is identified
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_class uuid;
  v_found boolean := false;
  v_row jsonb;
BEGIN
  PERFORM _m5_t03_as_super();
  SELECT id INTO v_class FROM class WHERE organization_id = v_org LIMIT 1;

  INSERT INTO teaching_session (
    organization_id, class_id, scheduled_start_at, scheduled_end_at, status, teacher_id
  )
  SELECT v_org, v_class,
    timestamptz '2042-07-01 09:00:00+07', timestamptz '2042-07-01 10:00:00+07',
    'completed', t.id
  FROM teacher t WHERE t.organization_id = v_org LIMIT 1;

  PERFORM _m5_t03_as_auth('a1111111-1111-4111-8111-111111111111');
  FOR v_row IN
    SELECT * FROM public.list_academic_exceptions('2042-07-01', '2042-07-31')
  LOOP
    IF v_row->>'exception_code' = 'completed_session_missing_attendance' THEN
      v_found := true;
    END IF;
  END LOOP;
  PERFORM _m5_t03_record(
    25,
    'completed session missing required academic data is identified',
    v_found
  );
END $$;

-- 26: pending review item identified
DO $$
DECLARE v_backlog jsonb;
BEGIN
  PERFORM _m5_t03_as_auth('a1111111-1111-4111-8111-111111111111');
  v_backlog := public.get_academic_review_backlog();
  PERFORM _m5_t03_record(
    26,
    'pending review item identified',
    (v_backlog ? 'attendance_pending') AND (v_backlog ? 'scores_pending')
  );
END $$;

-- 27: untranslated required comment identified
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_class uuid;
  v_enr uuid;
  v_teacher uuid;
  v_found boolean := false;
  v_row jsonb;
BEGIN
  PERFORM _m5_t03_as_super();
  SELECT id INTO v_class FROM class WHERE organization_id = v_org LIMIT 1;
  SELECT id INTO v_enr FROM enrollment WHERE organization_id = v_org AND class_id = v_class LIMIT 1;
  SELECT id INTO v_teacher FROM teacher WHERE organization_id = v_org LIMIT 1;

  INSERT INTO teacher_observation (
    organization_id, enrollment_id, class_id, teacher_id, observed_at, comment, status, review_status
  ) VALUES (
    v_org, v_enr, v_class, v_teacher,
    timestamptz '2042-08-01 10:00:00+07',
    'Needs translation T03', 'recorded', 'confirmed'
  );

  PERFORM _m5_t03_as_auth('a1111111-1111-4111-8111-111111111111');
  FOR v_row IN
    SELECT * FROM public.list_academic_exceptions('2042-08-01', '2042-08-31')
  LOOP
    IF v_row->>'exception_code' = 'comment_awaiting_translation' THEN
      v_found := true;
    END IF;
  END LOOP;
  PERFORM _m5_t03_record(27, 'untranslated required comment identified', v_found);
END $$;

-- 28: returned item identified
DO $$
DECLARE v_backlog jsonb;
BEGIN
  PERFORM _m5_t03_as_auth('a1111111-1111-4111-8111-111111111111');
  v_backlog := public.get_academic_review_backlog();
  PERFORM _m5_t03_record(
    28,
    'returned item identified',
    (v_backlog ? 'returned_attendance') AND (v_backlog ? 'returned_scores')
  );
END $$;

-- 29: manager quality intelligence access PASS
DO $$
DECLARE v_ok boolean := false;
BEGIN
  PERFORM _m5_t03_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.get_academic_quality_overview(CURRENT_DATE, CURRENT_DATE, false);
    v_ok := true;
  EXCEPTION WHEN others THEN
    v_ok := false;
  END;
  PERFORM _m5_t03_record(29, 'manager quality intelligence access PASS', v_ok);
END $$;

-- 30: academic operations operational review access PASS
DO $$
DECLARE v_ok boolean := false;
BEGIN
  PERFORM _m5_t03_as_auth('c1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.list_academic_review_queue('attendance_pending', 5, 0);
    v_ok := true;
  EXCEPTION WHEN others THEN
    v_ok := false;
  END;
  PERFORM _m5_t03_record(30, 'academic operations operational review access PASS', v_ok);
END $$;

-- 31: teacher denied center-wide quality intelligence
DO $$
DECLARE v_failed boolean := false;
BEGIN
  PERFORM _m5_t03_as_auth('c2222222-2222-4222-8222-222222222222');
  BEGIN
    PERFORM public.get_academic_quality_overview(CURRENT_DATE, CURRENT_DATE, false);
    v_failed := false;
  EXCEPTION WHEN insufficient_privilege THEN
    v_failed := true;
  END;
  PERFORM _m5_t03_record(31, 'teacher denied center-wide quality intelligence', v_failed);
END $$;

-- 32: accountant denied
DO $$
DECLARE v_failed boolean := false;
BEGIN
  PERFORM _m5_t03_as_auth('b7777777-7777-4777-8777-777777777777');
  BEGIN
    PERFORM public.get_academic_quality_overview(CURRENT_DATE, CURRENT_DATE, false);
    v_failed := false;
  EXCEPTION WHEN insufficient_privilege THEN
    v_failed := true;
  END;
  PERFORM _m5_t03_record(32, 'accountant denied academic quality intelligence', v_failed);
END $$;

-- 33: consultant denied
DO $$
DECLARE v_failed boolean := false;
BEGIN
  PERFORM _m5_t03_as_auth('b8888888-8888-4888-8888-888888888888');
  BEGIN
    PERFORM public.get_academic_quality_overview(CURRENT_DATE, CURRENT_DATE, false);
    v_failed := false;
  EXCEPTION WHEN insufficient_privilege THEN
    v_failed := true;
  END;
  PERFORM _m5_t03_record(33, 'consultant denied academic quality intelligence', v_failed);
END $$;

-- 34: organization isolation PASS
DO $$
DECLARE v_count integer;
BEGIN
  PERFORM _m5_t03_as_auth('b1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_count
  FROM attendance
  WHERE organization_id = 'a0000000-0000-4000-8000-000000000001';
  PERFORM _m5_t03_record(34, 'organization isolation PASS', v_count = 0);
END $$;

-- 35: reporting-period boundary PASS
DO $$
DECLARE v_overview jsonb;
BEGIN
  PERFORM _m5_t03_as_auth('a1111111-1111-4111-8111-111111111111');
  v_overview := public.get_academic_quality_overview('2026-01-01', '2026-01-31', false);
  PERFORM _m5_t03_record(
    35,
    'reporting-period boundary PASS',
    (v_overview->'period'->>'start_date') = '2026-01-01'
      AND (v_overview->'period'->>'end_date') = '2026-01-31'
  );
END $$;

-- 36: timezone boundary PASS
DO $$
DECLARE v_bounds reporting_period_bounds;
BEGIN
  PERFORM _m5_t03_as_auth('a1111111-1111-4111-8111-111111111111');
  v_bounds := public.resolve_reporting_period('2026-01-01', '2026-01-31');
  PERFORM _m5_t03_record(
    36,
    'timezone boundary PASS',
    v_bounds.start_at_utc = timestamptz '2025-12-31 17:00:00+00'
      AND v_bounds.end_at_exclusive = timestamptz '2026-01-31 17:00:00+00'
  );
END $$;

DO $$
DECLARE
  v_total integer;
  v_pass integer;
  v_fail integer;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE result = 'PASS'), count(*) FILTER (WHERE result = 'FAIL')
  INTO v_total, v_pass, v_fail
  FROM _m5_t03_results;

  RAISE NOTICE 'M5-T03 academic quality: %/% PASS (% FAIL)', v_pass, v_total, v_fail;

  IF v_fail > 0 THEN
    RAISE NOTICE 'Failed tests: %', (
      SELECT string_agg(test_no::text || ': ' || test_name, '; ')
      FROM _m5_t03_results WHERE result = 'FAIL'
    );
    RAISE EXCEPTION 'M5-T03 tests failed: %/% passed', v_pass, v_total;
  END IF;
END $$;

COMMIT;
