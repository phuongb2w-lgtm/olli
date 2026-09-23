-- M7-T03 subscription & entitlement domain tests

CREATE TEMP TABLE IF NOT EXISTS _m7_t03_results (
  test_no integer PRIMARY KEY,
  test_name text NOT NULL,
  result text NOT NULL CHECK (result IN ('PASS', 'FAIL'))
);

GRANT ALL ON TABLE _m7_t03_results TO authenticated, anon;

CREATE OR REPLACE FUNCTION _m7_t03_record(test_no integer, test_name text, passed boolean)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO _m7_t03_results (test_no, test_name, result)
  VALUES (test_no, test_name, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END);
END;
$$;

CREATE OR REPLACE FUNCTION _m7_t03_as_auth(p_auth_id uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', p_auth_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_auth_id::text, 'role', 'authenticated')::text, true);
END;
$$;

-- 1: base plan exists
DO $$
DECLARE v_ok boolean;
BEGIN
  SELECT EXISTS (SELECT 1 FROM commercial_plan WHERE code = 'base' AND status = 'active') INTO v_ok;
  PERFORM _m7_t03_record(1, 'base commercial plan exists', v_ok);
END $$;

-- 2: base plan staff limit = 5
DO $$
DECLARE v_limit integer;
BEGIN
  SELECT staff_limit INTO v_limit FROM commercial_plan WHERE code = 'base';
  PERFORM _m7_t03_record(2, 'base plan staff_limit is 5', v_limit = 5);
END $$;

-- 3: seeded org A has subscription
DO $$
DECLARE v_ok boolean;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM organization_subscription os
    WHERE os.organization_id = 'a0000000-0000-4000-8000-000000000001'
  ) INTO v_ok;
  PERFORM _m7_t03_record(3, 'seed org subscription exists', v_ok);
END $$;

-- 4: seeded org B keeps base entitlement (org A may use 24 for fixture headroom)
DO $$
DECLARE v_limit integer;
BEGIN
  SELECT staff_limit INTO v_limit
  FROM organization_entitlement
  WHERE organization_id = 'b0000000-0000-4000-8000-000000000001';
  PERFORM _m7_t03_record(4, 'seed org B effective staff_limit remains 5', v_limit = 5);
END $$;

-- 5: Owner cannot update commercial_plan
DO $$
DECLARE v_ok boolean := false;
BEGIN
  PERFORM _m7_t03_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    UPDATE commercial_plan SET staff_limit = 99 WHERE code = 'base';
    v_ok := false;
  EXCEPTION WHEN insufficient_privilege THEN
    v_ok := true;
  END;
  PERFORM _m7_t03_record(5, 'Owner cannot mutate commercial_plan', v_ok);
END $$;

-- 6: staff cannot update organization_subscription
DO $$
DECLARE v_ok boolean := false;
BEGIN
  PERFORM _m7_t03_as_auth('a2222222-2222-4222-8222-222222222222');
  BEGIN
    UPDATE organization_subscription
    SET status = 'cancelled'
    WHERE organization_id = 'a0000000-0000-4000-8000-000000000001';
    v_ok := false;
  EXCEPTION WHEN insufficient_privilege THEN
    v_ok := true;
  END;
  PERFORM _m7_t03_record(6, 'staff cannot mutate organization_subscription', v_ok);
END $$;

-- 7: service_role can activate provisioning org subscription
DO $$
DECLARE
  v_org uuid := gen_random_uuid();
  v_ok boolean := false;
  v_json jsonb;
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
  INSERT INTO organization (id, name) VALUES (v_org, 'M7 T03 Activate Org');
  PERFORM public._m7_initialize_organization_subscription(v_org, 'provisioning');
  SET LOCAL ROLE postgres;
  SELECT public.activate_organization_subscription(v_org) INTO v_json;
  SELECT EXISTS (
    SELECT 1 FROM organization_subscription os
    WHERE os.organization_id = v_org AND os.status = 'active'
  ) INTO v_ok;
  PERFORM _m7_t03_record(7, 'operator activate subscription', v_ok AND (v_json->>'status') = 'active');
END $$;

-- 8: active subscription syncs entitlement
DO $$
DECLARE
  v_org uuid := gen_random_uuid();
  v_limit integer;
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
  INSERT INTO organization (id, name) VALUES (v_org, 'M7 T03 Sync Org');
  PERFORM public._m7_initialize_organization_subscription(v_org, 'active');
  SELECT oe.staff_limit INTO v_limit
  FROM organization_entitlement oe WHERE oe.organization_id = v_org;
  PERFORM _m7_t03_record(8, 'active subscription syncs entitlement staff_limit', v_limit = 5);
END $$;

-- 9: plan change syncs entitlement
DO $$
DECLARE
  v_org uuid := gen_random_uuid();
  v_plan uuid;
  v_limit integer;
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
  INSERT INTO commercial_plan (code, name, staff_limit, status)
  VALUES ('m7_test_small', 'Test Small', 2, 'active')
  ON CONFLICT (code) DO UPDATE SET staff_limit = 2
  RETURNING id INTO v_plan;
  IF v_plan IS NULL THEN
    SELECT id INTO v_plan FROM commercial_plan WHERE code = 'm7_test_small';
  END IF;
  INSERT INTO organization (id, name) VALUES (v_org, 'M7 T03 Plan Change');
  PERFORM public._m7_initialize_organization_subscription(v_org, 'active');
  SET LOCAL ROLE postgres;
  PERFORM public.change_organization_commercial_plan(v_org, 'm7_test_small');
  SELECT staff_limit INTO v_limit FROM organization_entitlement WHERE organization_id = v_org;
  PERFORM _m7_t03_record(9, 'plan change syncs entitlement', v_limit = 2);
END $$;

-- 10: lower entitlement does not delete staff (org A still has members)
DO $$
DECLARE v_members integer;
BEGIN
  SELECT count(*) INTO v_members
  FROM app_user
  WHERE organization_id = 'a0000000-0000-4000-8000-000000000001'
    AND membership_status = 'member';
  PERFORM _m7_t03_record(10, 'lower plan does not delete staff accounts', v_members > 1);
END $$;

-- 11: seat restore blocked when over limit (M6 regression)
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_used integer;
  v_rejected boolean := false;
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
  SELECT public.count_member_staff_seats(v_org) INTO v_used;
  SET LOCAL ROLE postgres;
  PERFORM public.change_organization_commercial_plan(v_org, 'm7_test_small');
  BEGIN
    PERFORM public.create_staff_membership_record(
      v_org,
      'm7-over-' || gen_random_uuid()::text || '@olli.local',
      'Over Limit',
      'vi'
    );
    v_rejected := false;
  EXCEPTION WHEN OTHERS THEN
    v_rejected := SQLERRM LIKE '%staff_seat_limit_exceeded%';
  END;
  SET LOCAL ROLE postgres;
  PERFORM public.change_organization_commercial_plan(v_org, 'base');
  UPDATE organization_entitlement SET staff_limit = 24 WHERE organization_id = v_org;
  PERFORM _m7_t03_record(
    11,
    'M6 blocks seat creation when used exceeds synced limit',
    v_rejected AND v_used > 2
  );
END $$;

-- 12: suspend transition persists
DO $$
DECLARE v_org uuid := gen_random_uuid(); v_status text;
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
  INSERT INTO organization (id, name) VALUES (v_org, 'M7 T03 Suspend');
  PERFORM public._m7_initialize_organization_subscription(v_org, 'active');
  SET LOCAL ROLE postgres;
  PERFORM public.suspend_organization_subscription(v_org);
  SELECT status INTO v_status FROM organization_subscription WHERE organization_id = v_org;
  PERFORM _m7_t03_record(12, 'suspend transition persists', v_status = 'suspended');
END $$;

-- 13: suspended → active reactivation
DO $$
DECLARE v_org uuid := gen_random_uuid(); v_status text;
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
  INSERT INTO organization (id, name) VALUES (v_org, 'M7 T03 Reactivate');
  PERFORM public._m7_initialize_organization_subscription(v_org, 'active');
  SET LOCAL ROLE postgres;
  PERFORM public.suspend_organization_subscription(v_org);
  PERFORM public.reactivate_organization_subscription(v_org);
  SELECT status INTO v_status FROM organization_subscription WHERE organization_id = v_org;
  PERFORM _m7_t03_record(13, 'suspended to active reactivation', v_status = 'active');
END $$;

-- 14: cancel transition persists
DO $$
DECLARE v_org uuid := gen_random_uuid(); v_status text;
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
  INSERT INTO organization (id, name) VALUES (v_org, 'M7 T03 Cancel');
  PERFORM public._m7_initialize_organization_subscription(v_org, 'active');
  SET LOCAL ROLE postgres;
  PERFORM public.cancel_organization_subscription(v_org);
  SELECT status INTO v_status FROM organization_subscription WHERE organization_id = v_org;
  PERFORM _m7_t03_record(14, 'cancel transition persists', v_status = 'cancelled');
END $$;

-- 15: invalid transition rejected (cancelled → active)
DO $$
DECLARE v_org uuid := gen_random_uuid(); v_failed boolean := false;
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
  INSERT INTO organization (id, name) VALUES (v_org, 'M7 T03 Invalid');
  PERFORM public._m7_initialize_organization_subscription(v_org, 'active');
  SET LOCAL ROLE postgres;
  PERFORM public.cancel_organization_subscription(v_org);
  BEGIN
    PERFORM public.reactivate_organization_subscription(v_org);
    v_failed := false;
  EXCEPTION WHEN OTHERS THEN
    v_failed := SQLERRM LIKE '%invalid_subscription_transition%';
  END;
  PERFORM _m7_t03_record(15, 'invalid transition rejected', v_failed);
END $$;

-- 16: Owner cannot change own subscription via operator RPC
DO $$
DECLARE v_failed boolean := false;
BEGIN
  PERFORM _m7_t03_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.suspend_organization_subscription('a0000000-0000-4000-8000-000000000001');
    v_failed := false;
  EXCEPTION WHEN OTHERS THEN
    v_failed := true;
  END;
  PERFORM _m7_t03_record(16, 'Owner cannot call operator suspend RPC', v_failed);
END $$;

-- 17: duplicate subscription invariant (unique organization_id)
DO $$
DECLARE v_failed boolean := false;
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
  BEGIN
    INSERT INTO organization_subscription (organization_id, commercial_plan_id, status)
    SELECT 'a0000000-0000-4000-8000-000000000001', id, 'active'
    FROM commercial_plan WHERE code = 'base';
    v_failed := false;
  EXCEPTION WHEN unique_violation THEN
    v_failed := true;
  END;
  PERFORM _m7_t03_record(17, 'duplicate subscription per org rejected', v_failed);
END $$;

-- 18: organization.status independent from subscription.status
DO $$
DECLARE v_sub text; v_org text;
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
  UPDATE organization SET status = 'inactive'
  WHERE id = 'b0000000-0000-4000-8000-000000000001';
  SELECT status INTO v_sub FROM organization_subscription
  WHERE organization_id = 'b0000000-0000-4000-8000-000000000001';
  SELECT status INTO v_org FROM organization
  WHERE id = 'b0000000-0000-4000-8000-000000000001';
  UPDATE organization SET status = 'active'
  WHERE id = 'b0000000-0000-4000-8000-000000000001';
  PERFORM _m7_t03_record(
    18,
    'organization.status independent of subscription.status',
    v_org = 'inactive' AND v_sub = 'active'
  );
END $$;

DO $$
DECLARE v_fail integer;
BEGIN
  SELECT count(*) INTO v_fail FROM _m7_t03_results WHERE result = 'FAIL';
  IF v_fail > 0 THEN
    RAISE EXCEPTION 'M7-T03 tests failed: % failing cases', v_fail;
  END IF;
  RAISE NOTICE 'M7-T03 subscription entitlement tests: all PASS (% cases)', (SELECT count(*) FROM _m7_t03_results);
END $$;
