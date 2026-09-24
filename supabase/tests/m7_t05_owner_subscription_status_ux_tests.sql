-- M7-T05 Owner subscription / commercial status UX (authoritative RPC read)

CREATE TEMP TABLE IF NOT EXISTS _m7_t05_results (
  test_no integer PRIMARY KEY,
  test_name text NOT NULL,
  result text NOT NULL CHECK (result IN ('PASS', 'FAIL'))
);

GRANT ALL ON TABLE _m7_t05_results TO authenticated, anon;

CREATE OR REPLACE FUNCTION _m7_t05_record(test_no integer, test_name text, passed boolean)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO _m7_t05_results (test_no, test_name, result)
  VALUES (test_no, test_name, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END);
END;
$$;

CREATE OR REPLACE FUNCTION _m7_t05_as_auth(p_auth_id uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', p_auth_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_auth_id::text, 'role', 'authenticated')::text, true);
END;
$$;

-- 1: active Org A owner payload includes plan, status, seats
DO $$
DECLARE
  v_json jsonb;
  v_ok boolean;
BEGIN
  PERFORM _m7_t05_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT public.fetch_owner_commercial_status() INTO v_json;
  v_ok := v_json ? 'plan_code'
    AND v_json ? 'plan_name'
    AND v_json->>'subscription_status' = 'active'
    AND (v_json->>'staff_limit')::integer >= 0
    AND (v_json->>'staff_seats_used')::integer >= 0;
  PERFORM _m7_t05_record(1, 'active owner commercial status payload', v_ok);
END $$;

-- 2: staff cannot fetch owner commercial status
DO $$
DECLARE
  v_denied boolean := false;
BEGIN
  PERFORM _m7_t05_as_auth('a2222222-2222-4222-8222-222222222222');
  BEGIN
    PERFORM public.fetch_owner_commercial_status();
  EXCEPTION WHEN OTHERS THEN
    v_denied := SQLERRM LIKE '%permission_denied%' OR SQLSTATE = '42501';
  END;
  PERFORM _m7_t05_record(2, 'staff denied fetch_owner_commercial_status', v_denied);
END $$;

-- 3: seat used matches authoritative counter (postgres verifies RPC field)
DO $$
DECLARE
  v_json jsonb;
  v_used integer;
  v_count integer;
BEGIN
  PERFORM _m7_t05_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT public.fetch_owner_commercial_status() INTO v_json;
  v_used := (v_json->>'staff_seats_used')::integer;
  RESET ROLE;
  SET LOCAL ROLE postgres;
  v_count := public.count_member_staff_seats('a0000000-0000-4000-8000-000000000001');
  PERFORM _m7_t05_record(3, 'staff_seats_used matches count_member_staff_seats', v_used = v_count);
END $$;

-- 4: suspended owner can still read commercial status (operational owner)
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_json jsonb;
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
  UPDATE public.organization_subscription
  SET status = 'suspended', suspended_at = now()
  WHERE organization_id = v_org;
  PERFORM _m7_t05_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT public.fetch_owner_commercial_status() INTO v_json;
  PERFORM _m7_t05_record(
    4,
    'suspended owner read subscription_status suspended',
    v_json->>'subscription_status' = 'suspended'
  );
  RESET ROLE;
  SET LOCAL ROLE postgres;
  UPDATE public.organization_subscription
  SET status = 'active', suspended_at = NULL, activated_at = COALESCE(activated_at, now())
  WHERE organization_id = v_org;
END $$;

-- 5: provisioning status readable by operational owner (Org A fixture)
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_json jsonb;
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
  UPDATE public.organization_subscription
  SET status = 'provisioning', activated_at = NULL, suspended_at = NULL, cancelled_at = NULL
  WHERE organization_id = v_org;
  PERFORM _m7_t05_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT public.fetch_owner_commercial_status() INTO v_json;
  PERFORM _m7_t05_record(
    5,
    'provisioning owner read subscription_status provisioning',
    v_json->>'subscription_status' = 'provisioning'
  );
  RESET ROLE;
  SET LOCAL ROLE postgres;
  UPDATE public.organization_subscription
  SET status = 'active', activated_at = COALESCE(activated_at, now()), suspended_at = NULL, cancelled_at = NULL
  WHERE organization_id = v_org;
END $$;

-- 6: no authenticated EXECUTE on operator subscription mutations (spot check)
DO $$
DECLARE
  v_has_suspend boolean;
BEGIN
  SELECT EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'suspend_organization_subscription'
      AND has_function_privilege('authenticated', p.oid, 'EXECUTE')
  ) INTO v_has_suspend;
  PERFORM _m7_t05_record(6, 'authenticated cannot EXECUTE suspend_organization_subscription', NOT v_has_suspend);
END $$;

DO $$
DECLARE
  v_fail integer;
  v_total integer;
BEGIN
  SELECT COUNT(*) FILTER (WHERE result = 'FAIL'), COUNT(*)
    INTO v_fail, v_total
  FROM _m7_t05_results;
  IF v_fail > 0 THEN
    RAISE EXCEPTION 'M7-T05 owner subscription UX tests: %/% FAIL (see _m7_t05_results)', v_fail, v_total;
  END IF;
  RAISE NOTICE 'M7-T05 owner subscription UX tests: %/% PASS', v_total, v_total;
END $$;
