-- M0-T06 locale persistence verification: 6 scenarios
-- Requires local Supabase stack + dev seed fixtures.

CREATE TEMP TABLE IF NOT EXISTS _loc_results (
  test_no integer PRIMARY KEY,
  test_name text NOT NULL,
  result text NOT NULL CHECK (result IN ('PASS', 'FAIL'))
);

GRANT ALL ON TABLE _loc_results TO authenticated, anon;

CREATE OR REPLACE FUNCTION _loc_record(test_no integer, test_name text, passed boolean)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO _loc_results (test_no, test_name, result)
  VALUES (test_no, test_name, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END);
END;
$$;

CREATE OR REPLACE FUNCTION _loc_as_auth(p_auth_id uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', p_auth_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_auth_id::text, 'role', 'authenticated')::text, true);
END;
$$;

CREATE OR REPLACE FUNCTION _loc_as_anon()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE anon;
  PERFORM set_config('request.jwt.claim.sub', '', true);
END;
$$;

CREATE OR REPLACE FUNCTION _loc_as_super()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
END;
$$;

-- Fixture UUIDs (supabase/seed.sql)
-- Org A admin auth: a1111111-1111-4111-8111-111111111111
-- Org A admin app:  a1000000-0000-4000-8000-000000000001
-- Org A staff auth: a2222222-2222-4222-8222-222222222222
-- Org A staff app:  a2000000-0000-4000-8000-000000000001

-- Locale-1: authenticated user can change own preferred locale vi → en
DO $$
DECLARE v_locale text;
BEGIN
  PERFORM _loc_as_super();
  UPDATE app_user SET preferred_locale = 'vi' WHERE id = 'a1000000-0000-4000-8000-000000000001';

  PERFORM _loc_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.set_own_preferred_locale('en');

  SELECT preferred_locale INTO v_locale
  FROM app_user WHERE id = 'a1000000-0000-4000-8000-000000000001';

  PERFORM _loc_record(1, 'authenticated user changes own locale vi to en', v_locale = 'en');
END $$;

-- Locale-2: user cannot change another app_user locale
DO $$
DECLARE
  v_rows integer;
  v_locale text;
BEGIN
  PERFORM _loc_as_super();
  UPDATE app_user SET preferred_locale = 'vi' WHERE id = 'a1000000-0000-4000-8000-000000000001';

  PERFORM _loc_as_auth('a2222222-2222-4222-8222-222222222222');
  UPDATE app_user
  SET preferred_locale = 'en'
  WHERE id = 'a1000000-0000-4000-8000-000000000001';
  GET DIAGNOSTICS v_rows = ROW_COUNT;

  PERFORM _loc_as_super();
  SELECT preferred_locale INTO v_locale
  FROM app_user WHERE id = 'a1000000-0000-4000-8000-000000000001';

  PERFORM _loc_record(
    2,
    'user cannot change another app_user locale',
    v_rows = 0 AND v_locale = 'vi'
  );
END $$;

-- Locale-3: invalid locale rejected
DO $$
DECLARE v_rejected boolean := false;
BEGIN
  PERFORM _loc_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.set_own_preferred_locale('fr');
    v_rejected := false;
  EXCEPTION WHEN OTHERS THEN
    v_rejected := true;
  END;
  PERFORM _loc_record(3, 'invalid locale fr rejected', v_rejected);
END $$;

-- Locale-4: anonymous user cannot persist locale into app_user
DO $$
DECLARE v_rejected boolean := false;
BEGIN
  PERFORM _loc_as_anon();
  BEGIN
    PERFORM public.set_own_preferred_locale('en');
    v_rejected := false;
  EXCEPTION WHEN insufficient_privilege THEN
    v_rejected := true;
  WHEN OTHERS THEN
    v_rejected := true;
  END;
  PERFORM _loc_record(4, 'anonymous cannot persist locale into app_user', v_rejected);
END $$;

-- Locale-5: changing locale does not alter org_id, auth_user_id, status, or roles
DO $$
DECLARE
  v_before app_user%ROWTYPE;
  v_after app_user%ROWTYPE;
  v_role_count_before integer;
  v_role_count_after integer;
BEGIN
  PERFORM _loc_as_super();
  SELECT * INTO v_before FROM app_user WHERE id = 'a1000000-0000-4000-8000-000000000001';
  SELECT count(*) INTO v_role_count_before
  FROM user_role WHERE user_id = 'a1000000-0000-4000-8000-000000000001';

  PERFORM _loc_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.set_own_preferred_locale('vi');

  PERFORM _loc_as_super();
  SELECT * INTO v_after FROM app_user WHERE id = 'a1000000-0000-4000-8000-000000000001';
  SELECT count(*) INTO v_role_count_after
  FROM user_role WHERE user_id = 'a1000000-0000-4000-8000-000000000001';

  PERFORM _loc_record(
    5,
    'locale change preserves org auth status and roles',
    v_before.organization_id = v_after.organization_id
      AND v_before.auth_user_id = v_after.auth_user_id
      AND v_before.status = v_after.status
      AND v_role_count_before = v_role_count_after
  );
END $$;

-- Locale-6: persisted locale resolves correctly on subsequent authenticated context
DO $$
DECLARE v_resolved text;
BEGIN
  PERFORM _loc_as_super();
  UPDATE app_user SET preferred_locale = 'en' WHERE id = 'a1000000-0000-4000-8000-000000000001';

  PERFORM _loc_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT preferred_locale INTO v_resolved
  FROM app_user
  WHERE auth_user_id = auth.uid() AND status = 'active';

  PERFORM _loc_record(6, 'persisted locale resolves on authenticated read', v_resolved = 'en');
END $$;

DO $$
DECLARE
  passed integer;
  failed integer;
  total integer := 6;
BEGIN
  SELECT count(*) FILTER (WHERE result = 'PASS'),
         count(*) FILTER (WHERE result = 'FAIL')
  INTO passed, failed
  FROM _loc_results;

  RAISE NOTICE 'M0 locale Tests: % / % passed (% failed)', passed, total, failed;
  IF failed > 0 THEN
    RAISE EXCEPTION 'Locale tests failed: % of % (expected 6)', failed, total;
  END IF;
END $$;
