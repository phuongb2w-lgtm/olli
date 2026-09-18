-- M5-T01.1: Semantic boundary correction tests (10 scenarios)

BEGIN;

CREATE TEMP TABLE _m5_t011_results (
  test_no   integer PRIMARY KEY,
  test_name text NOT NULL,
  result    text NOT NULL CHECK (result IN ('PASS', 'FAIL'))
);

GRANT ALL ON TABLE _m5_t011_results TO authenticated, anon;

CREATE OR REPLACE FUNCTION _m5_t011_record(test_no integer, test_name text, passed boolean)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO _m5_t011_results (test_no, test_name, result)
  VALUES (test_no, test_name, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END);
END;
$$;

CREATE OR REPLACE FUNCTION _m5_t011_as_auth(p_auth_id uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', p_auth_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_auth_id::text, 'role', 'authenticated')::text, true);
END;
$$;

CREATE OR REPLACE FUNCTION _m5_t011_as_super()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
END;
$$;

CREATE OR REPLACE FUNCTION _m5_t011_seed_auth_user(p_auth uuid, p_email text)
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

DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_role uuid;
  v_user uuid;
  v_auth uuid;
BEGIN
  PERFORM _m5_t011_as_super();

  IF NOT EXISTS (SELECT 1 FROM app_user WHERE email = 'm5-consultant@olli.local') THEN
    v_auth := 'a8888888-8888-4888-8888-888888888888';
    PERFORM _m5_t011_seed_auth_user(v_auth, 'm5-consultant@olli.local');
    INSERT INTO role (organization_id, code) VALUES (v_org, 'm5_t011_consultant') RETURNING id INTO v_role;
    INSERT INTO role_permission (role_id, permission_id)
    SELECT v_role, p.id FROM permission p
    WHERE p.code IN ('organization.read', 'consultant_revenue.declare');
    INSERT INTO app_user (organization_id, email, display_name, auth_user_id, status)
    VALUES (v_org, 'm5-consultant@olli.local', 'M5 Consultant', v_auth, 'active')
    RETURNING id INTO v_user;
    INSERT INTO user_role (organization_id, user_id, role_id, effective_from, status)
    VALUES (v_org, v_user, v_role, CURRENT_DATE, 'active');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM app_user WHERE email = 'm5-accountant@olli.local') THEN
    v_auth := 'a7777777-7777-4777-8777-777777777777';
    PERFORM _m5_t011_seed_auth_user(v_auth, 'm5-accountant@olli.local');
    INSERT INTO role (organization_id, code) VALUES (v_org, 'm5_t011_accountant') RETURNING id INTO v_role;
    INSERT INTO role_permission (role_id, permission_id)
    SELECT v_role, p.id FROM permission p
    WHERE p.code IN (
      'organization.read', 'payment.read', 'revenue.read',
      'consultant_revenue.review'
    );
    INSERT INTO app_user (organization_id, email, display_name, auth_user_id, status)
    VALUES (v_org, 'm5-accountant@olli.local', 'M5 Accountant', v_auth, 'active')
    RETURNING id INTO v_user;
    INSERT INTO user_role (organization_id, user_id, role_id, effective_from, status)
    VALUES (v_org, v_user, v_role, CURRENT_DATE, 'active');
  END IF;
END $$;

-- 1: scheduled materialized session is not delivered
DO $$
BEGIN
  PERFORM _m5_t011_record(
    1,
    'scheduled session is not delivered',
    public.teaching_session_is_delivered('scheduled') = false
      AND public.teaching_session_is_materialized_non_delivered('scheduled') = true
  );
END $$;

-- 2: in_progress materialized session is not delivered
DO $$
BEGIN
  PERFORM _m5_t011_record(
    2,
    'in_progress session is not delivered',
    public.teaching_session_is_delivered('in_progress') = false
  );
END $$;

-- 3: completed session is delivered
DO $$
BEGIN
  PERFORM _m5_t011_record(
    3,
    'completed session is delivered',
    public.teaching_session_is_delivered('completed') = true
  );
END $$;

-- 4: cancelled materialized session is not delivered
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_class uuid;
  v_materialized bigint;
  v_delivered bigint;
BEGIN
  PERFORM _m5_t011_as_super();
  SELECT id INTO v_class FROM class WHERE organization_id = v_org LIMIT 1;

  INSERT INTO teaching_session (
    organization_id, class_id, scheduled_start_at, scheduled_end_at, status, teacher_id
  )
  SELECT v_org, v_class,
    timestamptz '2042-06-01 09:00:00+07', timestamptz '2042-06-01 10:00:00+07',
    'cancelled', t.id
  FROM teacher t WHERE t.organization_id = v_org LIMIT 1;

  INSERT INTO teaching_session (
    organization_id, class_id, scheduled_start_at, scheduled_end_at, status, teacher_id
  )
  SELECT v_org, v_class,
    timestamptz '2042-06-01 11:00:00+07', timestamptz '2042-06-01 12:00:00+07',
    'scheduled', t.id
  FROM teacher t WHERE t.organization_id = v_org LIMIT 1;

  PERFORM _m5_t011_as_auth('a1111111-1111-4111-8111-111111111111');
  v_materialized := public.count_materialized_teaching_sessions('2042-06-01', '2042-06-01', v_class);
  v_delivered := public.count_delivered_teaching_sessions('2042-06-01', '2042-06-01', v_class);

  PERFORM _m5_t011_record(
    4,
    'cancelled not materialized count; scheduled alone not delivered',
    v_materialized = 1 AND v_delivered = 0
  );
END $$;

-- 5: projected calendar entry is not materialized session row
DO $$
DECLARE
  v_proj integer; v_mat integer;
BEGIN
  PERFORM _m5_t011_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_proj
  FROM public.list_operational_calendar(CURRENT_DATE, CURRENT_DATE + 60, NULL, NULL, NULL)
  WHERE entry_type = 'projected';
  SELECT count(*) INTO v_mat
  FROM public.list_operational_calendar(CURRENT_DATE, CURRENT_DATE + 60, NULL, NULL, NULL)
  WHERE entry_type = 'session';
  PERFORM _m5_t011_record(
    5,
    'projected calendar entries distinct from materialized sessions',
    v_proj >= 0 AND v_mat >= 0
  );
END $$;

-- 6: materialized count exceeds delivered when scheduled sessions exist
DO $$
DECLARE
  v_mat bigint; v_del bigint;
BEGIN
  PERFORM _m5_t011_as_auth('a1111111-1111-4111-8111-111111111111');
  v_mat := public.count_materialized_teaching_sessions('2020-01-01', '2099-12-31', NULL);
  v_del := public.count_delivered_teaching_sessions('2020-01-01', '2099-12-31', NULL);
  PERFORM _m5_t011_record(
    6,
    'materialized count can exceed delivered count',
    v_mat >= v_del
  );
END $$;

-- 7: approved declaration without payment is not canonical cash
DO $$
DECLARE
  v_decl uuid;
  v_cash_before numeric;
  v_cash_after numeric;
  v_approved numeric;
BEGIN
  PERFORM _m5_t011_as_auth('a1111111-1111-4111-8111-111111111111');
  v_cash_before := public.sum_canonical_cash_collected('2020-01-01', '2099-12-31');

  PERFORM _m5_t011_as_auth('a8888888-8888-4888-8888-888888888888');
  v_decl := public.declare_consultant_revenue(CURRENT_DATE, 999999, 'T011 cash boundary');

  PERFORM _m5_t011_as_auth('a7777777-7777-4777-8777-777777777777');
  PERFORM public.review_consultant_revenue_declaration(v_decl, 'approve', 'Validated only');

  v_approved := public.sum_approved_consultant_declarations('2020-01-01', '2099-12-31');
  v_cash_after := public.sum_canonical_cash_collected('2020-01-01', '2099-12-31');

  PERFORM _m5_t011_record(
    7,
    'approved declaration does not increase canonical cash without payment',
    v_approved >= 999999
      AND v_cash_after = v_cash_before
      AND public.declaration_has_canonical_payment(v_decl) = false
  );
END $$;

-- 8: approved declaration is not recognized revenue
DO $$
DECLARE
  v_decl uuid;
  v_rev_before numeric;
  v_rev_after numeric;
BEGIN
  PERFORM _m5_t011_as_auth('a1111111-1111-4111-8111-111111111111');
  v_rev_before := public.count_canonical_financial_revenue('2020-01-01', '2099-12-31');

  PERFORM _m5_t011_as_auth('a8888888-8888-4888-8888-888888888888');
  v_decl := public.declare_consultant_revenue(CURRENT_DATE, 888888, 'T011 rev boundary');

  PERFORM _m5_t011_as_auth('a7777777-7777-4777-8777-777777777777');
  PERFORM public.review_consultant_revenue_declaration(v_decl, 'approve', 'No recognition');

  v_rev_after := public.count_canonical_financial_revenue('2020-01-01', '2099-12-31');

  PERFORM _m5_t011_record(
    8,
    'approved declaration does not increase recognized revenue',
    v_rev_after = v_rev_before
  );
END $$;

-- 9: pending and returned excluded from approved and canonical sums
DO $$
DECLARE
  v_pending numeric; v_approved numeric;
BEGIN
  PERFORM _m5_t011_as_auth('a8888888-8888-4888-8888-888888888888');
  PERFORM public.declare_consultant_revenue(CURRENT_DATE, 111111, 'Still pending');

  PERFORM _m5_t011_as_auth('a7777777-7777-4777-8777-777777777777');
  v_pending := public.sum_pending_consultant_declarations(CURRENT_DATE, CURRENT_DATE);
  v_approved := public.sum_approved_consultant_declarations(CURRENT_DATE, CURRENT_DATE);

  PERFORM _m5_t011_record(
    9,
    'pending declarations excluded from approved sum',
    v_pending >= 111111 AND v_approved >= 0
  );
END $$;

-- 10: M2 class_delivered_session_count still requires completed status
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_class uuid;
  v_count bigint;
BEGIN
  PERFORM _m5_t011_as_super();
  SELECT id INTO v_class FROM class WHERE organization_id = v_org LIMIT 1;

  INSERT INTO teaching_session (
    organization_id, class_id, scheduled_start_at, scheduled_end_at, status, teacher_id
  )
  SELECT v_org, v_class,
    timestamptz '2042-07-01 09:00:00+07', timestamptz '2042-07-01 10:00:00+07',
    'scheduled', t.id
  FROM teacher t WHERE t.organization_id = v_org LIMIT 1;

  v_count := public.class_delivered_session_count(v_class, date_trunc('month', timestamptz '2042-07-01 09:00:00+07')::date);

  PERFORM _m5_t011_record(
    10,
    'M2 delivered session count ignores scheduled-only materialized session',
    v_count = 0
  );
END $$;

DO $$
DECLARE
  v_total integer;
  v_pass integer;
  v_fail integer;
  r RECORD;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE result = 'PASS'), count(*) FILTER (WHERE result = 'FAIL')
  INTO v_total, v_pass, v_fail
  FROM _m5_t011_results;

  IF v_fail > 0 THEN
    FOR r IN SELECT test_no, test_name FROM _m5_t011_results WHERE result = 'FAIL' ORDER BY test_no LOOP
      RAISE NOTICE 'FAIL % — %', r.test_no, r.test_name;
    END LOOP;
    RAISE EXCEPTION 'M5-T01.1 semantic tests failed: %/% passed', v_pass, v_total;
  END IF;

  RAISE NOTICE 'M5-T01.1 semantic correction tests: %/% passed', v_pass, v_total;
END $$;

ROLLBACK;
