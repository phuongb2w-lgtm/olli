-- M7-T07 Commercialization integration (cross-task state consistency)

CREATE TEMP TABLE IF NOT EXISTS _m7_t07_results (
  test_no integer PRIMARY KEY,
  test_name text NOT NULL,
  result text NOT NULL CHECK (result IN ('PASS', 'FAIL'))
);

GRANT ALL ON TABLE _m7_t07_results TO authenticated, anon;

CREATE OR REPLACE FUNCTION _m7_t07_record(test_no integer, test_name text, passed boolean)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO _m7_t07_results (test_no, test_name, result)
  VALUES (test_no, test_name, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END);
END;
$$;

CREATE OR REPLACE FUNCTION _m7_t07_as_auth(p_auth_id uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', p_auth_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_auth_id::text, 'role', 'authenticated')::text, true);
END;
$$;

-- 1: active fixture org — normal use, setup complete, no onboarding required
DO $$
DECLARE
  v_json jsonb;
BEGIN
  PERFORM _m7_t07_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT public.fetch_session_commercial_access() INTO v_json;
  PERFORM _m7_t07_record(
    1,
    'active complete owner session allows normal use',
    v_json->>'allows_normal_use' = 'true'
      AND v_json->>'requires_center_setup' = 'false'
      AND v_json->>'setup_completed' = 'true'
  );
END $$;

-- 2: provisioning + incomplete setup — onboarding required, no normal use
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

  PERFORM _m7_t07_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT public.fetch_session_commercial_access() INTO v_json;
  PERFORM _m7_t07_record(
    2,
    'provisioning incomplete owner requires setup blocks normal use',
    v_json->>'requires_center_setup' = 'true'
      AND v_json->>'allows_normal_use' = 'false'
      AND v_json->>'subscription_status' = 'provisioning'
  );

  RESET ROLE;
  SET LOCAL ROLE postgres;
  UPDATE public.organization SET setup_completed_at = now() WHERE id = v_org;
  UPDATE public.organization_subscription
  SET status = 'active', activated_at = COALESCE(activated_at, now()), suspended_at = NULL, cancelled_at = NULL
  WHERE organization_id = v_org;
END $$;

-- 3: provisioning + setup complete — subscription status only, no onboarding
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_json jsonb;
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
  UPDATE public.organization SET setup_completed_at = now() WHERE id = v_org;
  UPDATE public.organization_subscription
  SET status = 'provisioning', activated_at = NULL, suspended_at = NULL, cancelled_at = NULL
  WHERE organization_id = v_org;

  PERFORM _m7_t07_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT public.fetch_session_commercial_access() INTO v_json;
  PERFORM _m7_t07_record(
    3,
    'provisioning complete setup skips onboarding gate',
    v_json->>'requires_center_setup' = 'false'
      AND v_json->>'allows_normal_use' = 'false'
      AND v_json->>'setup_completed' = 'true'
  );

  RESET ROLE;
  SET LOCAL ROLE postgres;
  UPDATE public.organization_subscription
  SET status = 'active', activated_at = COALESCE(activated_at, now()), suspended_at = NULL, cancelled_at = NULL
  WHERE organization_id = v_org;
END $$;

-- 4: active + incomplete setup — onboarding before workspace
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_json jsonb;
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
  UPDATE public.organization SET setup_completed_at = NULL WHERE id = v_org;
  UPDATE public.organization_subscription
  SET status = 'active', activated_at = COALESCE(activated_at, now()), suspended_at = NULL, cancelled_at = NULL
  WHERE organization_id = v_org;

  PERFORM _m7_t07_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT public.fetch_session_commercial_access() INTO v_json;
  PERFORM _m7_t07_record(
    4,
    'active incomplete owner requires setup with normal commercial entitlement',
    v_json->>'requires_center_setup' = 'true'
      AND v_json->>'allows_normal_use' = 'true'
  );

  RESET ROLE;
  SET LOCAL ROLE postgres;
  UPDATE public.organization SET setup_completed_at = now() WHERE id = v_org;
END $$;

-- 5: suspended blocks onboarding even if setup incomplete
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_json jsonb;
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

  PERFORM _m7_t07_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT public.fetch_session_commercial_access() INTO v_json;
  PERFORM _m7_t07_record(
    5,
    'suspended owner cannot enter onboarding gate',
    v_json->>'requires_center_setup' = 'false'
      AND v_json->>'allows_normal_use' = 'false'
  );

  RESET ROLE;
  SET LOCAL ROLE postgres;
  UPDATE public.organization SET setup_completed_at = now() WHERE id = v_org;
  UPDATE public.organization_subscription
  SET status = 'active', suspended_at = NULL, activated_at = COALESCE(activated_at, now()), cancelled_at = NULL
  WHERE organization_id = v_org;
END $$;

-- 6: staff never requires onboarding
DO $$
DECLARE
  v_json jsonb;
BEGIN
  PERFORM _m7_t07_as_auth('a2222222-2222-4222-8222-222222222222');
  SELECT public.fetch_session_commercial_access() INTO v_json;
  PERFORM _m7_t07_record(
    6,
    'staff session never requires center setup',
    v_json->>'requires_center_setup' = 'false'
      AND v_json->>'is_primary_owner' = 'false'
  );
END $$;

-- 7: owner commercial status seats align with entitlement + counter
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_json jsonb;
  v_limit integer;
  v_used integer;
  v_ent_limit integer;
BEGIN
  PERFORM _m7_t07_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT public.fetch_owner_commercial_status() INTO v_json;
  v_limit := (v_json->>'staff_limit')::integer;
  v_used := (v_json->>'staff_seats_used')::integer;

  RESET ROLE;
  SET LOCAL ROLE postgres;
  SELECT oe.staff_limit INTO v_ent_limit
  FROM public.organization_entitlement oe
  WHERE oe.organization_id = v_org;

  PERFORM _m7_t07_record(
    7,
    'owner commercial status staff_limit matches entitlement',
    v_limit = v_ent_limit
      AND v_used = public.count_member_staff_seats(v_org)
  );
END $$;

-- 8: authenticated cannot operator-activate subscription
DO $$
DECLARE
  v_denied boolean := false;
BEGIN
  PERFORM _m7_t07_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.activate_organization_subscription('a0000000-0000-4000-8000-000000000001');
  EXCEPTION WHEN insufficient_privilege THEN
    v_denied := true;
  WHEN OTHERS THEN
    v_denied := SQLERRM LIKE '%permission%' OR SQLSTATE = '42501';
  END;
  PERFORM _m7_t07_record(8, 'owner cannot activate subscription via RPC', v_denied);
END $$;

-- 9: setup completion is one-time
DO $$
DECLARE
  v_denied boolean := false;
BEGIN
  PERFORM _m7_t07_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.complete_center_setup('Repeat', 'vi', 'Asia/Ho_Chi_Minh', NULL);
  EXCEPTION WHEN OTHERS THEN
    v_denied := SQLERRM LIKE '%setup_already_complete%';
  END;
  PERFORM _m7_t07_record(9, 'complete_center_setup rejected when already complete', v_denied);
END $$;

-- 10: reactivation preserves setup_completed_at
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_before timestamptz;
  v_after timestamptz;
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
  SELECT setup_completed_at INTO v_before FROM public.organization WHERE id = v_org;
  UPDATE public.organization_subscription
  SET status = 'active', activated_at = COALESCE(activated_at, now()), suspended_at = NULL, cancelled_at = NULL
  WHERE organization_id = v_org;
  PERFORM public.suspend_organization_subscription(v_org);
  PERFORM public.reactivate_organization_subscription(v_org);
  SELECT setup_completed_at INTO v_after FROM public.organization WHERE id = v_org;

  PERFORM _m7_t07_record(
    10,
    'reactivation preserves setup_completed_at',
    v_before IS NOT NULL AND v_before = v_after
  );
END $$;

-- Summary
DO $$
DECLARE
  v_fail integer;
BEGIN
  SELECT count(*) INTO v_fail FROM _m7_t07_results WHERE result = 'FAIL';
  IF v_fail > 0 THEN
    RAISE EXCEPTION 'M7-T07 integration tests failed: % case(s)', v_fail;
  END IF;
  RAISE NOTICE 'M7-T07 commercialization integration tests: all PASS (10 cases)';
END $$;
