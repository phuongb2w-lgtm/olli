-- M4-T02: Teacher unavailability and room foundation tests.

BEGIN;

CREATE TEMP TABLE _m4_unavail_results (
  test_no   integer PRIMARY KEY,
  test_name text NOT NULL,
  result    text NOT NULL CHECK (result IN ('PASS', 'FAIL'))
);

GRANT ALL ON TABLE _m4_unavail_results TO authenticated, anon;

CREATE OR REPLACE FUNCTION _m4_unavail_record(test_no integer, test_name text, passed boolean)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  INSERT INTO _m4_unavail_results (test_no, test_name, result)
  VALUES (test_no, test_name, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END);
END;
$$;

CREATE OR REPLACE FUNCTION _m4_unavail_expect_fail(test_no integer, test_name text, sql_text text)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  BEGIN
    EXECUTE sql_text;
    PERFORM _m4_unavail_record(test_no, test_name, false);
  EXCEPTION WHEN OTHERS THEN
    PERFORM _m4_unavail_record(test_no, test_name, true);
  END;
END;
$$;

CREATE OR REPLACE FUNCTION _m4_unavail_as_auth(p_auth_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', p_auth_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_auth_id::text, 'role', 'authenticated')::text, true);
END;
$$;

CREATE OR REPLACE FUNCTION _m4_unavail_as_super()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
END;
$$;

-- Fixture UUIDs (supabase/seed.sql)
-- Org A: a0000000-0000-4000-8000-000000000001
-- Org B: b0000000-0000-4000-8000-000000000001
-- Org A admin auth: a1111111-1111-4111-8111-111111111111
-- Org A staff auth: a2222222-2222-4222-8222-222222222222
-- Org A reader auth: a4444444-4444-4444-8444-444444444444
-- Org A admin app_user: a1000000-0000-4000-8000-000000000001

-- 1: recurring block creation
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_teacher uuid;
  v_id uuid;
BEGIN
  PERFORM _m4_unavail_as_super();
  SELECT id INTO v_teacher FROM teacher WHERE organization_id = v_org LIMIT 1;

  PERFORM _m4_unavail_as_auth('a1111111-1111-4111-8111-111111111111');
  INSERT INTO teacher_unavailability (
    organization_id, teacher_id, block_type,
    weekday_code, start_time, end_time, effective_from,
    reason, status, created_by, updated_by
  )
  VALUES (
    v_org, v_teacher, 'recurring',
    'mon', '08:00', '12:00', '2026-01-01',
    'Morning unavailable', 'active',
    'a1000000-0000-4000-8000-000000000001',
    'a1000000-0000-4000-8000-000000000001'
  )
  RETURNING id INTO v_id;

  PERFORM _m4_unavail_record(1, 'recurring block creation', v_id IS NOT NULL);
END $$;

-- 2: one-off block creation
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_teacher uuid;
  v_id uuid;
BEGIN
  PERFORM _m4_unavail_as_super();
  SELECT id INTO v_teacher FROM teacher WHERE organization_id = v_org LIMIT 1;

  PERFORM _m4_unavail_as_auth('a1111111-1111-4111-8111-111111111111');
  INSERT INTO teacher_unavailability (
    organization_id, teacher_id, block_type,
    starts_at, ends_at, reason, status, created_by, updated_by
  )
  VALUES (
    v_org, v_teacher, 'one_off',
    timestamptz '2026-09-25 13:00:00+07',
    timestamptz '2026-09-25 17:00:00+07',
    'Leave', 'active',
    'a1000000-0000-4000-8000-000000000001',
    'a1000000-0000-4000-8000-000000000001'
  )
  RETURNING id INTO v_id;

  PERFORM _m4_unavail_record(2, 'one-off block creation', v_id IS NOT NULL);
END $$;

-- 3: recurring invalid duration rejected
SELECT _m4_unavail_expect_fail(
  3,
  'recurring invalid duration rejected',
  $$
  DO $inner$
  DECLARE
    v_org uuid := 'a0000000-0000-4000-8000-000000000001';
    v_teacher uuid;
  BEGIN
    PERFORM _m4_unavail_as_super();
    SELECT id INTO v_teacher FROM teacher WHERE organization_id = v_org LIMIT 1;
    PERFORM _m4_unavail_as_auth('a1111111-1111-4111-8111-111111111111');
    INSERT INTO teacher_unavailability (
      organization_id, teacher_id, block_type,
      weekday_code, start_time, end_time, effective_from, status
    )
    VALUES (
      v_org, v_teacher, 'recurring',
      'tue', '12:00', '08:00', '2026-01-01', 'active'
    );
  END $inner$;
  $$
);

-- 4: one-off invalid duration rejected
SELECT _m4_unavail_expect_fail(
  4,
  'one-off invalid duration rejected',
  $$
  DO $inner$
  DECLARE
    v_org uuid := 'a0000000-0000-4000-8000-000000000001';
    v_teacher uuid;
  BEGIN
    PERFORM _m4_unavail_as_super();
    SELECT id INTO v_teacher FROM teacher WHERE organization_id = v_org LIMIT 1;
    PERFORM _m4_unavail_as_auth('a1111111-1111-4111-8111-111111111111');
    INSERT INTO teacher_unavailability (
      organization_id, teacher_id, block_type, starts_at, ends_at, status
    )
    VALUES (
      v_org, v_teacher, 'one_off',
      timestamptz '2026-09-25 17:00:00+07',
      timestamptz '2026-09-25 13:00:00+07',
      'active'
    );
  END $inner$;
  $$
);

-- 5: invalid block-type field combination rejected
SELECT _m4_unavail_expect_fail(
  5,
  'invalid block-type field combination rejected',
  $$
  DO $inner$
  DECLARE
    v_org uuid := 'a0000000-0000-4000-8000-000000000001';
    v_teacher uuid;
  BEGIN
    PERFORM _m4_unavail_as_super();
    SELECT id INTO v_teacher FROM teacher WHERE organization_id = v_org LIMIT 1;
    PERFORM _m4_unavail_as_auth('a1111111-1111-4111-8111-111111111111');
    INSERT INTO teacher_unavailability (
      organization_id, teacher_id, block_type,
      weekday_code, start_time, end_time, effective_from,
      starts_at, ends_at, status
    )
    VALUES (
      v_org, v_teacher, 'recurring',
      'wed', '08:00', '09:00', '2026-01-01',
      timestamptz '2026-09-25 13:00:00+07',
      timestamptz '2026-09-25 17:00:00+07',
      'active'
    );
  END $inner$;
  $$
);

-- 6: invalid effective date range rejected
SELECT _m4_unavail_expect_fail(
  6,
  'invalid effective date range rejected',
  $$
  DO $inner$
  DECLARE
    v_org uuid := 'a0000000-0000-4000-8000-000000000001';
    v_teacher uuid;
  BEGIN
    PERFORM _m4_unavail_as_super();
    SELECT id INTO v_teacher FROM teacher WHERE organization_id = v_org LIMIT 1;
    PERFORM _m4_unavail_as_auth('a1111111-1111-4111-8111-111111111111');
    INSERT INTO teacher_unavailability (
      organization_id, teacher_id, block_type,
      weekday_code, start_time, end_time, effective_from, effective_to, status
    )
    VALUES (
      v_org, v_teacher, 'recurring',
      'thu', '08:00', '09:00', '2026-06-01', '2026-05-01', 'active'
    );
  END $inner$;
  $$
);

-- 7: cross-org teacher rejected
SELECT _m4_unavail_expect_fail(
  7,
  'cross-org teacher rejected',
  $$
  DO $inner$
  DECLARE
    v_org_a uuid := 'a0000000-0000-4000-8000-000000000001';
    v_teacher_b uuid;
  BEGIN
    PERFORM _m4_unavail_as_super();
    SELECT id INTO v_teacher_b FROM teacher WHERE organization_id = 'b0000000-0000-4000-8000-000000000001' LIMIT 1;
    PERFORM _m4_unavail_as_auth('a1111111-1111-4111-8111-111111111111');
    INSERT INTO teacher_unavailability (
      organization_id, teacher_id, block_type,
      weekday_code, start_time, end_time, effective_from, status
    )
    VALUES (
      v_org_a, v_teacher_b, 'recurring',
      'fri', '08:00', '09:00', '2026-01-01', 'active'
    );
  END $inner$;
  $$
);

-- 8: cross-org reads blocked
DO $$
DECLARE
  v_cnt integer;
BEGIN
  PERFORM _m4_unavail_as_auth('b1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_cnt
  FROM teacher_unavailability
  WHERE organization_id = 'a0000000-0000-4000-8000-000000000001';
  PERFORM _m4_unavail_record(8, 'cross-org reads blocked', v_cnt = 0);
END $$;

-- 9: unauthorized writes blocked
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_teacher uuid;
  v_err boolean := false;
BEGIN
  PERFORM _m4_unavail_as_super();
  SELECT id INTO v_teacher FROM teacher WHERE organization_id = v_org LIMIT 1;

  PERFORM _m4_unavail_as_auth('a2222222-2222-4222-8222-222222222222');
  BEGIN
    INSERT INTO teacher_unavailability (
      organization_id, teacher_id, block_type,
      weekday_code, start_time, end_time, effective_from, status
    )
    VALUES (
      v_org, v_teacher, 'recurring',
      'sat', '08:00', '09:00', '2026-01-01', 'active'
    );
  EXCEPTION WHEN insufficient_privilege THEN
    v_err := true;
  WHEN OTHERS THEN
    v_err := SQLERRM LIKE '%permission%' OR SQLERRM LIKE '%policy%' OR SQLERRM LIKE '%42501%';
  END;

  IF NOT v_err THEN
    SELECT count(*) = 0 INTO v_err
    FROM teacher_unavailability
    WHERE teacher_id = v_teacher AND weekday_code = 'sat' AND start_time = '08:00';
  END IF;

  PERFORM _m4_unavail_record(9, 'unauthorized writes blocked', v_err);
END $$;

-- 10: authorized writes allowed
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_teacher uuid;
  v_id uuid;
BEGIN
  PERFORM _m4_unavail_as_super();
  SELECT id INTO v_teacher FROM teacher WHERE organization_id = v_org LIMIT 1;

  PERFORM _m4_unavail_as_auth('a1111111-1111-4111-8111-111111111111');
  INSERT INTO teacher_unavailability (
    organization_id, teacher_id, block_type,
    weekday_code, start_time, end_time, effective_from, status,
    created_by, updated_by
  )
  VALUES (
    v_org, v_teacher, 'recurring',
    'sun', '10:00', '11:00', '2026-02-01', 'active',
    'a1000000-0000-4000-8000-000000000001',
    'a1000000-0000-4000-8000-000000000001'
  )
  RETURNING id INTO v_id;

  PERFORM _m4_unavail_record(10, 'authorized writes allowed', v_id IS NOT NULL);
END $$;

-- 11: ended block ignored by lookup
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_teacher uuid;
  v_hit boolean;
BEGIN
  PERFORM _m4_unavail_as_super();
  SELECT id INTO v_teacher FROM teacher WHERE organization_id = v_org LIMIT 1;

  INSERT INTO teacher_unavailability (
    organization_id, teacher_id, block_type,
    starts_at, ends_at, status
  )
  VALUES (
    v_org, v_teacher, 'one_off',
    timestamptz '2026-10-01 09:00:00+07',
    timestamptz '2026-10-01 11:00:00+07',
    'ended'
  );

  PERFORM _m4_unavail_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT public.teacher_has_unavailability(
    v_teacher,
    timestamptz '2026-10-01 09:30:00+07',
    timestamptz '2026-10-01 10:00:00+07'
  ) INTO v_hit;

  PERFORM _m4_unavail_record(11, 'ended block ignored by active-unavailability lookup', v_hit = false);
END $$;

-- 12: recurring intersection detected (uses recurring block from test 1)
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_teacher uuid;
  v_hit boolean;
BEGIN
  PERFORM _m4_unavail_as_super();
  SELECT id INTO v_teacher FROM teacher WHERE organization_id = v_org LIMIT 1;

  PERFORM _m4_unavail_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT public.teacher_has_unavailability(
    v_teacher,
    timestamptz '2026-06-01 09:00:00+07',
    timestamptz '2026-06-01 10:00:00+07'
  ) INTO v_hit;

  PERFORM _m4_unavail_record(12, 'recurring intersection detected', v_hit = true);
END $$;

-- 13: recurring non-intersection returns false
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_teacher uuid;
  v_hit boolean;
BEGIN
  PERFORM _m4_unavail_as_super();
  SELECT id INTO v_teacher FROM teacher WHERE organization_id = v_org LIMIT 1;

  PERFORM _m4_unavail_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT public.teacher_has_unavailability(
    v_teacher,
    timestamptz '2026-06-01 13:00:00+07',
    timestamptz '2026-06-01 14:00:00+07'
  ) INTO v_hit;

  PERFORM _m4_unavail_record(13, 'recurring non-intersection returns false', v_hit = false);
END $$;

-- 14: one-off intersection detected
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_teacher uuid;
  v_hit boolean;
BEGIN
  PERFORM _m4_unavail_as_super();
  SELECT id INTO v_teacher FROM teacher WHERE organization_id = v_org LIMIT 1;

  INSERT INTO teacher_unavailability (
    organization_id, teacher_id, block_type, starts_at, ends_at, status
  )
  VALUES (
    v_org, v_teacher, 'one_off',
    timestamptz '2026-11-15 14:00:00+07',
    timestamptz '2026-11-15 16:00:00+07',
    'active'
  );

  PERFORM _m4_unavail_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT public.teacher_has_unavailability(
    v_teacher,
    timestamptz '2026-11-15 14:30:00+07',
    timestamptz '2026-11-15 15:00:00+07'
  ) INTO v_hit;

  PERFORM _m4_unavail_record(14, 'one-off intersection detected', v_hit = true);
END $$;

-- 15: one-off non-intersection returns false
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_teacher uuid;
  v_hit boolean;
BEGIN
  PERFORM _m4_unavail_as_super();
  SELECT id INTO v_teacher FROM teacher WHERE organization_id = v_org LIMIT 1;

  PERFORM _m4_unavail_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT public.teacher_has_unavailability(
    v_teacher,
    timestamptz '2026-11-15 17:00:00+07',
    timestamptz '2026-11-15 18:00:00+07'
  ) INTO v_hit;

  PERFORM _m4_unavail_record(15, 'one-off non-intersection returns false', v_hit = false);
END $$;

-- 16: organization timezone interpretation is correct
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_teacher uuid;
  v_hit boolean;
  v_tz text;
BEGIN
  PERFORM _m4_unavail_as_super();
  SELECT id INTO v_teacher FROM teacher WHERE organization_id = v_org LIMIT 1;
  SELECT timezone INTO v_tz FROM organization WHERE id = v_org;

  DELETE FROM teacher_unavailability
  WHERE organization_id = v_org
    AND teacher_id = v_teacher
    AND block_type = 'recurring'
    AND weekday_code = 'tue';

  INSERT INTO teacher_unavailability (
    organization_id, teacher_id, block_type,
    weekday_code, start_time, end_time, effective_from, status
  )
  VALUES (
    v_org, v_teacher, 'recurring',
    'tue', '18:00', '20:00', '2026-01-01', 'active'
  );

  PERFORM _m4_unavail_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT public.teacher_has_unavailability(
    v_teacher,
    timestamptz '2026-06-02 18:30:00+07',
    timestamptz '2026-06-02 19:00:00+07'
  ) INTO v_hit;

  PERFORM _m4_unavail_record(
    16,
    'organization timezone interpretation is correct',
    v_hit = true AND v_tz = 'Asia/Ho_Chi_Minh'
  );
END $$;

-- 17: overlapping unavailability rows allowed
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_teacher uuid;
  v_cnt integer;
BEGIN
  PERFORM _m4_unavail_as_super();
  SELECT id INTO v_teacher FROM teacher WHERE organization_id = v_org LIMIT 1;

  PERFORM _m4_unavail_as_auth('a1111111-1111-4111-8111-111111111111');
  INSERT INTO teacher_unavailability (
    organization_id, teacher_id, block_type,
    weekday_code, start_time, end_time, effective_from, status
  )
  VALUES (
    v_org, v_teacher, 'recurring',
    'mon', '08:00', '10:00', '2026-03-01', 'active'
  );

  INSERT INTO teacher_unavailability (
    organization_id, teacher_id, block_type, starts_at, ends_at, status
  )
  VALUES (
    v_org, v_teacher, 'one_off',
    timestamptz '2026-06-01 08:00:00+07',
    timestamptz '2026-06-01 12:00:00+07',
    'active'
  );

  SELECT count(*) INTO v_cnt
  FROM teacher_unavailability
  WHERE organization_id = v_org
    AND teacher_id = v_teacher
    AND status = 'active';

  PERFORM _m4_unavail_record(17, 'overlapping unavailability rows allowed', v_cnt >= 2);
END $$;

-- 18: exact duplicate active recurring rejected
SELECT _m4_unavail_expect_fail(
  18,
  'exact duplicate active recurring rejected',
  $$
  DO $inner$
  DECLARE
    v_org uuid := 'a0000000-0000-4000-8000-000000000001';
    v_teacher uuid;
  BEGIN
    PERFORM _m4_unavail_as_super();
    SELECT id INTO v_teacher FROM teacher WHERE organization_id = v_org LIMIT 1;
    PERFORM _m4_unavail_as_auth('a1111111-1111-4111-8111-111111111111');
    INSERT INTO teacher_unavailability (
      organization_id, teacher_id, block_type,
      weekday_code, start_time, end_time, effective_from, status
    )
    VALUES (
      v_org, v_teacher, 'recurring',
      'sun', '10:00', '11:00', '2026-02-01', 'active'
    );
  END $inner$;
  $$
);

-- 19: existing room behavior remains valid
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_room uuid;
  v_has_notes boolean;
BEGIN
  PERFORM _m4_unavail_as_auth('a1111111-1111-4111-8111-111111111111');
  UPDATE room
  SET notes = 'Near reception', updated_by = 'a1000000-0000-4000-8000-000000000001'
  WHERE organization_id = v_org AND code = 'A101'
  RETURNING id INTO v_room;

  SELECT notes IS NOT NULL INTO v_has_notes FROM room WHERE id = v_room;

  PERFORM _m4_unavail_record(
    19,
    'existing room behavior remains valid',
    v_room IS NOT NULL AND v_has_notes
  );
END $$;

-- 20: teaching session room exclusion remains valid
SELECT _m4_unavail_expect_fail(
  20,
  'teaching session room exclusion remains valid',
  $$
  DO $inner$
  DECLARE
    v_org uuid := 'a0000000-0000-4000-8000-000000000001';
    v_class uuid;
    v_teacher uuid;
    v_room uuid;
    v_s1 uuid;
  BEGIN
    PERFORM _m4_unavail_as_super();
    SELECT c.id INTO v_class FROM class c WHERE c.organization_id = v_org LIMIT 1;
    SELECT t.id INTO v_teacher FROM teacher t WHERE t.organization_id = v_org LIMIT 1;
    SELECT r.id INTO v_room FROM room r WHERE r.organization_id = v_org LIMIT 1;

    INSERT INTO teaching_session (
      organization_id, class_id, teacher_id, room_id,
      scheduled_start_at, scheduled_end_at, status
    )
    VALUES (
      v_org, v_class, v_teacher, v_room,
      timestamptz '2027-01-10 18:00:00+07',
      timestamptz '2027-01-10 20:00:00+07',
      'scheduled'
    )
    RETURNING id INTO v_s1;

    INSERT INTO teaching_session (
      organization_id, class_id, teacher_id, room_id,
      scheduled_start_at, scheduled_end_at, status
    )
    VALUES (
      v_org, v_class, v_teacher, v_room,
      timestamptz '2027-01-10 19:00:00+07',
      timestamptz '2027-01-10 21:00:00+07',
      'scheduled'
    );
  END $inner$;
  $$
);

-- 21: teaching session teacher exclusion remains valid
SELECT _m4_unavail_expect_fail(
  21,
  'teaching session teacher exclusion remains valid',
  $$
  DO $inner$
  DECLARE
    v_org uuid := 'a0000000-0000-4000-8000-000000000001';
    v_class uuid;
    v_teacher uuid;
    v_room uuid;
  BEGIN
    PERFORM _m4_unavail_as_super();
    SELECT c.id INTO v_class FROM class c WHERE c.organization_id = v_org LIMIT 1;
    SELECT t.id INTO v_teacher FROM teacher t WHERE t.organization_id = v_org LIMIT 1;
    SELECT r.id INTO v_room FROM room r WHERE r.organization_id = v_org LIMIT 1;

    INSERT INTO teaching_session (
      organization_id, class_id, teacher_id, room_id,
      scheduled_start_at, scheduled_end_at, status
    )
    VALUES (
      v_org, v_class, v_teacher, v_room,
      timestamptz '2027-02-10 18:00:00+07',
      timestamptz '2027-02-10 20:00:00+07',
      'scheduled'
    );

    INSERT INTO teaching_session (
      organization_id, class_id, teacher_id, room_id,
      scheduled_start_at, scheduled_end_at, status
    )
    VALUES (
      v_org, v_class, v_teacher, v_room,
      timestamptz '2027-02-10 19:00:00+07',
      timestamptz '2027-02-10 21:00:00+07',
      'scheduled'
    );
  END $inner$;
  $$
);

-- 22: generate_teaching_sessions rejects teacher unavailability (M4-T04)
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_class uuid;
  v_teacher uuid;
  v_schedule uuid;
  v_unavail boolean;
  v_rejected boolean := false;
BEGIN
  PERFORM _m4_unavail_as_super();
  SELECT c.id INTO v_class FROM class c WHERE c.organization_id = v_org LIMIT 1;
  SELECT t.id INTO v_teacher FROM teacher t WHERE t.organization_id = v_org LIMIT 1;

  INSERT INTO teacher_unavailability (
    organization_id, teacher_id, block_type,
    weekday_code, start_time, end_time, effective_from, status
  )
  VALUES (
    v_org, v_teacher, 'recurring',
    'wed', '00:00', '23:59', '2027-03-01', 'active'
  );

  INSERT INTO class_schedule (
    organization_id, class_id, weekday_code, start_time, end_time,
    effective_from, teacher_id, status
  )
  VALUES (
    v_org, v_class, 'wed', '18:00', '19:30', '2027-03-01', v_teacher, 'active'
  )
  RETURNING id INTO v_schedule;

  PERFORM _m4_unavail_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT public.teacher_has_unavailability(
    v_teacher,
    timestamptz '2027-03-03 18:00:00+07',
    timestamptz '2027-03-03 19:30:00+07'
  ) INTO v_unavail;

  BEGIN
    PERFORM public.generate_teaching_sessions(v_schedule, '2027-03-01', '2027-03-31');
  EXCEPTION WHEN OTHERS THEN
    v_rejected := SQLERRM LIKE '%teacher_unavailable%';
  END;

  PERFORM _m4_unavail_record(
    22,
    'generate_teaching_sessions rejects teacher unavailability',
    v_unavail = true AND v_rejected
  );
END $$;

-- Summary
DO $$
DECLARE
  v_total integer;
  v_failed integer;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE result = 'FAIL')
  INTO v_total, v_failed
  FROM _m4_unavail_results;

  IF v_failed > 0 THEN
    RAISE EXCEPTION 'M4 teacher unavailability Tests: % / % passed (% failed)',
      v_total - v_failed, v_total, v_failed;
  END IF;

  RAISE NOTICE 'M4 teacher unavailability Tests: % / % passed (0 failed)', v_total, v_total;
END $$;

ROLLBACK;
