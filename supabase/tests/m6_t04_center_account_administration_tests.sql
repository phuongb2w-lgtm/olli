-- M6-T04 center account administration read model tests

CREATE TEMP TABLE IF NOT EXISTS _m6_t04_results (
  test_no integer PRIMARY KEY,
  test_name text NOT NULL,
  result text NOT NULL CHECK (result IN ('PASS', 'FAIL'))
);

GRANT ALL ON TABLE _m6_t04_results TO authenticated, anon;

CREATE OR REPLACE FUNCTION _m6_t04_record(test_no integer, test_name text, passed boolean)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO _m6_t04_results (test_no, test_name, result)
  VALUES (test_no, test_name, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END);
END;
$$;

CREATE OR REPLACE FUNCTION _m6_t04_as_auth(p_auth_id uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', p_auth_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_auth_id::text, 'role', 'authenticated')::text, true);
END;
$$;

-- 1: primary owner can fetch administration payload
DO $$
DECLARE v_data jsonb;
BEGIN
  PERFORM _m6_t04_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT public.fetch_center_account_administration() INTO v_data;
  PERFORM _m6_t04_record(
    1,
    'owner can fetch center account administration',
    v_data ? 'staff_limit'
      AND v_data ? 'staff_seats_used'
      AND v_data ? 'primary_owner'
      AND v_data ? 'staff'
  );
END $$;

-- 2: non-owner staff denied
DO $$
DECLARE v_denied boolean := false;
BEGIN
  PERFORM _m6_t04_as_auth('a2222222-2222-4222-8222-222222222222');
  BEGIN
    PERFORM public.fetch_center_account_administration();
    v_denied := false;
  EXCEPTION WHEN OTHERS THEN
    v_denied := SQLERRM LIKE '%permission_denied%';
  END;
  PERFORM _m6_t04_record(2, 'non-owner cannot fetch administration', v_denied);
END $$;

-- 3: staff_limit matches entitlement
DO $$
DECLARE v_data jsonb; v_limit integer;
BEGIN
  PERFORM _m6_t04_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT public.fetch_center_account_administration() INTO v_data;
  SELECT staff_limit INTO v_limit
  FROM organization_entitlement
  WHERE organization_id = 'a0000000-0000-4000-8000-000000000001';
  PERFORM _m6_t04_record(
    3,
    'staff_limit authoritative from entitlement',
    (v_data->>'staff_limit')::integer = v_limit
  );
END $$;

-- 4: staff_seats_used matches count_member_staff_seats
DO $$
DECLARE v_data jsonb; v_count integer;
BEGIN
  PERFORM _m6_t04_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT public.fetch_center_account_administration() INTO v_data;
  RESET ROLE;
  SET LOCAL ROLE postgres;
  SELECT public.count_member_staff_seats('a0000000-0000-4000-8000-000000000001') INTO v_count;
  PERFORM _m6_t04_record(
    4,
    'staff_seats_used matches member seat counter',
    (v_data->>'staff_seats_used')::integer = v_count
  );
END $$;

-- 5: primary owner excluded from staff array
DO $$
DECLARE v_data jsonb; v_primary uuid; v_in_staff boolean;
BEGIN
  PERFORM _m6_t04_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT public.fetch_center_account_administration() INTO v_data;
  v_primary := (v_data->'primary_owner'->>'app_user_id')::uuid;
  SELECT EXISTS (
    SELECT 1
    FROM jsonb_array_elements(v_data->'staff') elem
    WHERE (elem->>'app_user_id')::uuid = v_primary
  ) INTO v_in_staff;
  PERFORM _m6_t04_record(5, 'primary owner excluded from staff list', NOT v_in_staff);
END $$;

-- 6: removed member excluded from staff list
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_removed uuid := 'a7000000-0000-4000-8000-000000000001';
  v_data jsonb;
  v_present boolean;
BEGIN
  INSERT INTO app_user (id, organization_id, email, display_name, status, membership_status)
  VALUES (v_removed, v_org, 'm6-t04-removed@olli.local', 'Removed Staff', 'inactive', 'removed');

  PERFORM _m6_t04_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT public.fetch_center_account_administration() INTO v_data;
  SELECT EXISTS (
    SELECT 1
    FROM jsonb_array_elements(v_data->'staff') elem
    WHERE elem->>'email' = 'm6-t04-removed@olli.local'
  ) INTO v_present;
  PERFORM _m6_t04_record(6, 'removed staff excluded from default list', NOT v_present);
END $$;

-- 7: inactive member still counted in staff_seats_used
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_data jsonb;
  v_before integer;
  v_after integer;
BEGIN
  PERFORM _m6_t04_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT public.fetch_center_account_administration() INTO v_data;
  v_before := (v_data->>'staff_seats_used')::integer;

  RESET ROLE;
  SET LOCAL ROLE postgres;
  UPDATE app_user SET status = 'inactive'
  WHERE id = 'a2000000-0000-4000-8000-000000000001';

  PERFORM _m6_t04_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT public.fetch_center_account_administration() INTO v_data;
  v_after := (v_data->>'staff_seats_used')::integer;

  RESET ROLE;
  SET LOCAL ROLE postgres;
  UPDATE app_user SET status = 'active'
  WHERE id = 'a2000000-0000-4000-8000-000000000001';

  PERFORM _m6_t04_record(
    7,
    'inactive member still occupies seat count',
    v_before = v_after
  );
END $$;

-- 8: locked member still counted in staff_seats_used
DO $$
DECLARE v_data jsonb; v_before integer; v_after integer;
BEGIN
  PERFORM _m6_t04_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT public.fetch_center_account_administration() INTO v_data;
  v_before := (v_data->>'staff_seats_used')::integer;

  RESET ROLE;
  SET LOCAL ROLE postgres;
  UPDATE app_user SET status = 'locked'
  WHERE id = 'a2000000-0000-4000-8000-000000000001';

  PERFORM _m6_t04_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT public.fetch_center_account_administration() INTO v_data;
  v_after := (v_data->>'staff_seats_used')::integer;

  RESET ROLE;
  SET LOCAL ROLE postgres;
  UPDATE app_user SET status = 'active'
  WHERE id = 'a2000000-0000-4000-8000-000000000001';

  PERFORM _m6_t04_record(
    8,
    'locked member still occupies seat count',
    v_before = v_after
  );
END $$;

-- 9: payload omits auth_user_id and provisioning internals
DO $$
DECLARE v_data jsonb; v_text text;
BEGIN
  PERFORM _m6_t04_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT public.fetch_center_account_administration() INTO v_data;
  v_text := v_data::text;
  PERFORM _m6_t04_record(
    9,
    'payload omits auth and provisioning internals',
    v_text NOT LIKE '%auth_user_id%'
      AND v_text NOT LIKE '%processing_token%'
      AND v_text NOT LIKE '%staff_provisioning_request%'
  );
END $$;

-- 10: cross-org staff not included
DO $$
DECLARE v_data jsonb; v_cross boolean;
BEGIN
  PERFORM _m6_t04_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT public.fetch_center_account_administration() INTO v_data;
  SELECT EXISTS (
    SELECT 1
    FROM jsonb_array_elements(v_data->'staff') elem
    WHERE elem->>'email' = 'org-b-staff@olli.local'
  ) INTO v_cross;
  PERFORM _m6_t04_record(10, 'cross-org accounts absent', NOT v_cross);
END $$;

DO $$
DECLARE v_fail integer;
BEGIN
  SELECT count(*) INTO v_fail FROM _m6_t04_results WHERE result = 'FAIL';
  IF v_fail > 0 THEN
    RAISE EXCEPTION 'M6-T04 center account administration tests failed: % failing', v_fail;
  END IF;
  RAISE NOTICE 'M6-T04 center account administration tests: 10/10 PASS';
END $$;
