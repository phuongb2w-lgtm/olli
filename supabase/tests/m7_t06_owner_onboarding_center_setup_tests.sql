-- M7-T06 Owner onboarding & center setup (authoritative setup_completed_at)

CREATE TEMP TABLE IF NOT EXISTS _m7_t06_results (
  test_no integer PRIMARY KEY,
  test_name text NOT NULL,
  result text NOT NULL CHECK (result IN ('PASS', 'FAIL'))
);

GRANT ALL ON TABLE _m7_t06_results TO authenticated, anon;

CREATE OR REPLACE FUNCTION _m7_t06_record(test_no integer, test_name text, passed boolean)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO _m7_t06_results (test_no, test_name, result)
  VALUES (test_no, test_name, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END);
END;
$$;

CREATE OR REPLACE FUNCTION _m7_t06_as_auth(p_auth_id uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', p_auth_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_auth_id::text, 'role', 'authenticated')::text, true);
END;
$$;

-- 1: fixture Org A owner has setup completed
DO $$
DECLARE
  v_ok boolean;
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
  SELECT o.setup_completed_at IS NOT NULL INTO v_ok
  FROM public.organization o
  WHERE o.id = 'a0000000-0000-4000-8000-000000000001';
  PERFORM _m7_t06_record(1, 'fixture Org A setup completed', v_ok);
END $$;

-- 2: session payload exposes requires_center_setup false for completed owner
DO $$
DECLARE
  v_json jsonb;
BEGIN
  PERFORM _m7_t06_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT public.fetch_session_commercial_access() INTO v_json;
  PERFORM _m7_t06_record(
    2,
    'completed owner requires_center_setup false',
    v_json->>'requires_center_setup' = 'false'
  );
END $$;

-- 3: staff requires_center_setup false
DO $$
DECLARE
  v_json jsonb;
BEGIN
  PERFORM _m7_t06_as_auth('a2222222-2222-4222-8222-222222222222');
  SELECT public.fetch_session_commercial_access() INTO v_json;
  PERFORM _m7_t06_record(
    3,
    'staff requires_center_setup false',
    v_json->>'requires_center_setup' = 'false'
  );
END $$;

-- 4: incomplete setup + provisioning owner requires setup
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_json jsonb;
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
  UPDATE public.organization SET setup_completed_at = NULL WHERE id = v_org;
  UPDATE public.organization_subscription
  SET status = 'provisioning', activated_at = NULL, suspended_at = NULL, cancelled_at = NULL
  WHERE organization_id = v_org;

  PERFORM _m7_t06_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT public.fetch_session_commercial_access() INTO v_json;
  PERFORM _m7_t06_record(
    4,
    'provisioning owner with incomplete setup requires_center_setup true',
    v_json->>'requires_center_setup' = 'true'
      AND v_json->>'allows_normal_use' = 'false'
  );

  RESET ROLE;
  SET LOCAL ROLE postgres;
  UPDATE public.organization SET setup_completed_at = now() WHERE id = v_org;
  UPDATE public.organization_subscription
  SET status = 'active', activated_at = COALESCE(activated_at, now()), suspended_at = NULL, cancelled_at = NULL
  WHERE organization_id = v_org;
END $$;

-- 5: complete_center_setup persists fields and timestamp (provisioning)
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_json jsonb;
  v_completed timestamptz;
  v_prev_name text;
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
  SELECT name INTO v_prev_name FROM public.organization WHERE id = v_org;
  UPDATE public.organization SET setup_completed_at = NULL WHERE id = v_org;
  UPDATE public.organization_subscription
  SET status = 'provisioning', activated_at = NULL, suspended_at = NULL, cancelled_at = NULL
  WHERE organization_id = v_org;

  PERFORM _m7_t06_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT public.complete_center_setup(
    'Renamed Center',
    'en',
    'Asia/Bangkok',
    'en'
  ) INTO v_json;

  SELECT setup_completed_at INTO v_completed FROM public.organization WHERE id = v_org;

  PERFORM _m7_t06_record(
    5,
    'complete_center_setup sets setup_completed_at and org fields',
    v_completed IS NOT NULL
      AND (SELECT name FROM public.organization WHERE id = v_org) = 'Renamed Center'
      AND (SELECT default_locale FROM public.organization WHERE id = v_org) = 'en'
      AND v_json->>'allows_normal_use' = 'false'
  );

  RESET ROLE;
  SET LOCAL ROLE postgres;
  UPDATE public.organization
  SET name = v_prev_name, default_locale = 'vi', timezone = 'Asia/Ho_Chi_Minh', setup_completed_at = now()
  WHERE id = v_org;
  UPDATE public.organization_subscription
  SET status = 'active', activated_at = COALESCE(activated_at, now()), suspended_at = NULL, cancelled_at = NULL
  WHERE organization_id = v_org;
END $$;

-- 6: staff cannot complete_center_setup
DO $$
DECLARE
  v_denied boolean := false;
BEGIN
  PERFORM _m7_t06_as_auth('a2222222-2222-4222-8222-222222222222');
  BEGIN
    PERFORM public.complete_center_setup('X', 'vi', 'Asia/Ho_Chi_Minh', NULL);
  EXCEPTION WHEN OTHERS THEN
    v_denied := SQLERRM LIKE '%not_primary_owner%';
  END;
  PERFORM _m7_t06_record(6, 'staff denied complete_center_setup', v_denied);
END $$;

-- 7: suspended org cannot complete setup
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_denied boolean := false;
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
  UPDATE public.organization SET setup_completed_at = NULL WHERE id = v_org;
  UPDATE public.organization_subscription
  SET status = 'active', activated_at = COALESCE(activated_at, now()), suspended_at = NULL, cancelled_at = NULL
  WHERE organization_id = v_org;
  UPDATE public.organization_subscription
  SET status = 'suspended', suspended_at = now()
  WHERE organization_id = v_org;

  PERFORM _m7_t06_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.complete_center_setup('Blocked', 'vi', 'Asia/Ho_Chi_Minh', NULL);
  EXCEPTION WHEN OTHERS THEN
    v_denied := SQLERRM LIKE '%commercial_access_restricted%';
  END;

  RESET ROLE;
  SET LOCAL ROLE postgres;
  UPDATE public.organization SET setup_completed_at = now() WHERE id = v_org;
  UPDATE public.organization_subscription
  SET status = 'active', suspended_at = NULL, activated_at = COALESCE(activated_at, now()), cancelled_at = NULL
  WHERE organization_id = v_org;

  PERFORM _m7_t06_record(7, 'suspended owner denied complete_center_setup', v_denied);
END $$;

-- 8: cancelled org cannot complete setup
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_denied boolean := false;
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
  UPDATE public.organization SET setup_completed_at = NULL WHERE id = v_org;
  UPDATE public.organization_subscription
  SET status = 'active', activated_at = COALESCE(activated_at, now()), suspended_at = NULL, cancelled_at = NULL
  WHERE organization_id = v_org;
  PERFORM public.cancel_organization_subscription(v_org);

  PERFORM _m7_t06_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.complete_center_setup('Blocked', 'vi', 'Asia/Ho_Chi_Minh', NULL);
  EXCEPTION WHEN OTHERS THEN
    v_denied := SQLERRM LIKE '%commercial_access_restricted%';
  END;

  RESET ROLE;
  SET LOCAL ROLE postgres;
  UPDATE public.organization SET setup_completed_at = now() WHERE id = v_org;
  UPDATE public.organization_subscription
  SET status = 'active', activated_at = COALESCE(activated_at, now()), suspended_at = NULL, cancelled_at = NULL
  WHERE organization_id = v_org;

  PERFORM _m7_t06_record(8, 'cancelled owner denied complete_center_setup', v_denied);
END $$;

-- Summary
DO $$
DECLARE
  v_fail integer;
BEGIN
  SELECT count(*) INTO v_fail FROM _m7_t06_results WHERE result = 'FAIL';
  IF v_fail > 0 THEN
    RAISE EXCEPTION 'M7-T06 onboarding tests failed: % case(s)', v_fail;
  END IF;
  RAISE NOTICE 'M7-T06 owner onboarding tests: all PASS';
END $$;
