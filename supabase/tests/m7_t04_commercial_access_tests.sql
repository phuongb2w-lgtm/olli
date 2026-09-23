-- M7-T04 commercial access enforcement tests

CREATE TEMP TABLE IF NOT EXISTS _m7_t04_results (
  test_no integer PRIMARY KEY,
  test_name text NOT NULL,
  result text NOT NULL CHECK (result IN ('PASS', 'FAIL'))
);

GRANT ALL ON TABLE _m7_t04_results TO authenticated, anon;

CREATE OR REPLACE FUNCTION _m7_t04_record(test_no integer, test_name text, passed boolean)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO _m7_t04_results (test_no, test_name, result)
  VALUES (test_no, test_name, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END);
END;
$$;

CREATE OR REPLACE FUNCTION _m7_t04_as_auth(p_auth_id uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', p_auth_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_auth_id::text, 'role', 'authenticated')::text, true);
END;
$$;

CREATE OR REPLACE FUNCTION _m7_t04_seed_auth(p_auth uuid)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v_email text := p_auth::text || '@m7t04.local';
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
    v_email,
    '',
    now(),
    now(),
    now(),
    false,
    false
  );
  RETURN v_email;
END;
$$;

-- 1: active org A owner commercially entitled
DO $$
DECLARE v_ok boolean;
BEGIN
  PERFORM _m7_t04_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT public.is_active_app_user() INTO v_ok;
  PERFORM _m7_t04_record(1, 'active owner is_active_app_user', v_ok);
END $$;

-- 2: active org A staff has enrollment.read when entitled
DO $$
DECLARE v_ok boolean;
BEGIN
  PERFORM _m7_t04_as_auth('a2222222-2222-4222-8222-222222222222');
  SELECT public.has_permission('enrollment.read') INTO v_ok;
  PERFORM _m7_t04_record(2, 'active staff RBAC permission allowed', v_ok);
END $$;

-- 3: provisioning owner operational but not commercially active
DO $$
DECLARE
  v_org uuid := gen_random_uuid();
  v_auth uuid := gen_random_uuid();
  v_app uuid := gen_random_uuid();
  v_active boolean;
  v_oper boolean;
  v_owner_read boolean := false;
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
  INSERT INTO organization (id, name) VALUES (v_org, 'M7 T04 Prov Owner');
  UPDATE public.organization_subscription
  SET status = 'provisioning', activated_at = NULL, suspended_at = NULL, cancelled_at = NULL
  WHERE organization_id = v_org;
  PERFORM _m7_t04_seed_auth(v_auth);
  INSERT INTO app_user (id, organization_id, email, display_name, auth_user_id, status, membership_status)
  VALUES (v_app, v_org, v_auth::text || '@m7t04.local', 'Prov Owner', v_auth, 'active', 'member');
  UPDATE organization_entitlement SET primary_app_user_id = v_app WHERE organization_id = v_org;
  PERFORM _m7_t04_as_auth(v_auth);
  SELECT public.is_active_app_user(), public.is_operationally_active_app_user()
    INTO v_active, v_oper;
  BEGIN
    PERFORM public.fetch_owner_commercial_status();
    v_owner_read := true;
  EXCEPTION WHEN OTHERS THEN
    v_owner_read := false;
  END;
  PERFORM _m7_t04_record(
    3,
    'provisioning owner restricted from normal use but can read status',
    NOT v_active AND v_oper AND v_owner_read
  );
END $$;

-- 4: provisioning staff restricted
DO $$
DECLARE
  v_org uuid := gen_random_uuid();
  v_auth uuid := gen_random_uuid();
  v_active boolean;
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
  INSERT INTO organization (id, name) VALUES (v_org, 'M7 T04 Prov Staff');
  UPDATE public.organization_subscription
  SET status = 'provisioning', activated_at = NULL, suspended_at = NULL, cancelled_at = NULL
  WHERE organization_id = v_org;
  PERFORM _m7_t04_seed_auth(v_auth);
  INSERT INTO app_user (id, organization_id, email, display_name, auth_user_id, status, membership_status)
  VALUES (gen_random_uuid(), v_org, v_auth::text || '@m7t04.local', 'Prov Staff', v_auth, 'active', 'member');
  PERFORM _m7_t04_as_auth(v_auth);
  SELECT public.is_active_app_user() INTO v_active;
  PERFORM _m7_t04_record(4, 'provisioning staff is_active_app_user false', NOT v_active);
END $$;

-- 5: suspended owner domain mutation denied (has_permission)
DO $$
DECLARE
  v_org uuid := gen_random_uuid();
  v_auth uuid := gen_random_uuid();
  v_app uuid := gen_random_uuid();
  v_perm boolean;
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
  INSERT INTO organization (id, name) VALUES (v_org, 'M7 T04 Suspend Owner');
  PERFORM public._m7_initialize_organization_subscription(v_org, 'active');
  PERFORM _m7_t04_seed_auth(v_auth);
  INSERT INTO app_user (id, organization_id, email, display_name, auth_user_id, status, membership_status)
  VALUES (v_app, v_org, v_auth::text || '@m7t04.local', 'Susp Owner', v_auth, 'active', 'member');
  UPDATE organization_entitlement SET primary_app_user_id = v_app WHERE organization_id = v_org;
  PERFORM public.suspend_organization_subscription(v_org);
  PERFORM _m7_t04_as_auth(v_auth);
  SELECT public.has_permission('center_account.manage') INTO v_perm;
  PERFORM _m7_t04_record(5, 'suspended owner center_account.manage denied', NOT v_perm);
END $$;

-- 6: suspended staff mutation denied
DO $$
DECLARE
  v_org uuid := gen_random_uuid();
  v_auth uuid := gen_random_uuid();
  v_perm boolean;
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
  INSERT INTO organization (id, name) VALUES (v_org, 'M7 T04 Suspend Staff');
  PERFORM public._m7_initialize_organization_subscription(v_org, 'active');
  PERFORM _m7_t04_seed_auth(v_auth);
  INSERT INTO app_user (id, organization_id, email, display_name, auth_user_id, status, membership_status)
  VALUES (gen_random_uuid(), v_org, v_auth::text || '@m7t04.local', 'Susp Staff', v_auth, 'active', 'member');
  PERFORM public.suspend_organization_subscription(v_org);
  PERFORM _m7_t04_as_auth(v_auth);
  SELECT public.has_permission('enrollment.read') INTO v_perm;
  PERFORM _m7_t04_record(6, 'suspended staff permission denied', NOT v_perm);
END $$;

-- 7: cancelled owner mutation denied
DO $$
DECLARE
  v_org uuid := gen_random_uuid();
  v_auth uuid := gen_random_uuid();
  v_app uuid := gen_random_uuid();
  v_perm boolean;
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
  INSERT INTO organization (id, name) VALUES (v_org, 'M7 T04 Cancel Owner');
  PERFORM public._m7_initialize_organization_subscription(v_org, 'active');
  PERFORM _m7_t04_seed_auth(v_auth);
  INSERT INTO app_user (id, organization_id, email, display_name, auth_user_id, status, membership_status)
  VALUES (v_app, v_org, v_auth::text || '@m7t04.local', 'Canc Owner', v_auth, 'active', 'member');
  UPDATE organization_entitlement SET primary_app_user_id = v_app WHERE organization_id = v_org;
  PERFORM public.cancel_organization_subscription(v_org);
  PERFORM _m7_t04_as_auth(v_auth);
  SELECT public.has_permission('report.executive.read') INTO v_perm;
  PERFORM _m7_t04_record(7, 'cancelled owner executive read denied', NOT v_perm);
END $$;

-- 8: cancelled staff mutation denied
DO $$
DECLARE
  v_org uuid := gen_random_uuid();
  v_auth uuid := gen_random_uuid();
  v_perm boolean;
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
  INSERT INTO organization (id, name) VALUES (v_org, 'M7 T04 Cancel Staff');
  PERFORM public._m7_initialize_organization_subscription(v_org, 'active');
  PERFORM _m7_t04_seed_auth(v_auth);
  INSERT INTO app_user (id, organization_id, email, display_name, auth_user_id, status, membership_status)
  VALUES (gen_random_uuid(), v_org, v_auth::text || '@m7t04.local', 'Canc Staff', v_auth, 'active', 'member');
  PERFORM public.cancel_organization_subscription(v_org);
  PERFORM _m7_t04_as_auth(v_auth);
  SELECT public.has_permission('student.read') INTO v_perm;
  PERFORM _m7_t04_record(8, 'cancelled staff student.read denied', NOT v_perm);
END $$;

-- 9: restricted owner fetch commercial status
DO $$
DECLARE
  v_org uuid := gen_random_uuid();
  v_auth uuid := gen_random_uuid();
  v_app uuid := gen_random_uuid();
  v_json jsonb;
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
  INSERT INTO organization (id, name) VALUES (v_org, 'M7 T04 Owner Status');
  PERFORM public._m7_initialize_organization_subscription(v_org, 'active');
  PERFORM public.suspend_organization_subscription(v_org);
  PERFORM _m7_t04_seed_auth(v_auth);
  INSERT INTO app_user (id, organization_id, email, display_name, auth_user_id, status, membership_status)
  VALUES (v_app, v_org, v_auth::text || '@m7t04.local', 'Status Owner', v_auth, 'active', 'member');
  UPDATE organization_entitlement SET primary_app_user_id = v_app WHERE organization_id = v_org;
  PERFORM _m7_t04_as_auth(v_auth);
  SELECT public.fetch_owner_commercial_status() INTO v_json;
  PERFORM _m7_t04_record(
    9,
    'restricted owner fetch_owner_commercial_status',
    (v_json->>'subscription_status') = 'suspended'
  );
END $$;

-- 10: staff cannot fetch owner commercial status
DO $$
DECLARE v_denied boolean := false;
BEGIN
  PERFORM _m7_t04_as_auth('a2222222-2222-4222-8222-222222222222');
  BEGIN
    PERFORM public.fetch_owner_commercial_status();
    v_denied := false;
  EXCEPTION WHEN OTHERS THEN
    v_denied := SQLERRM LIKE '%permission_denied%';
  END;
  PERFORM _m7_t04_record(10, 'staff cannot fetch owner commercial status', v_denied);
END $$;

-- 11: direct RPC bypass denied when suspended
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_denied boolean := false;
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
  PERFORM public.suspend_organization_subscription(v_org);
  PERFORM _m7_t04_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.assert_organization_commercially_entitled();
    v_denied := false;
  EXCEPTION WHEN OTHERS THEN
    v_denied := SQLERRM LIKE '%commercial_access_restricted%';
  END;
  SET LOCAL ROLE postgres;
  PERFORM public.reactivate_organization_subscription(v_org);
  PERFORM _m7_t04_record(11, 'direct RPC denied when suspended', v_denied);
END $$;

-- 12: direct DML bypass denied when suspended
DO $$
DECLARE
  v_org uuid := gen_random_uuid();
  v_auth uuid := gen_random_uuid();
  v_denied boolean := false;
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
  INSERT INTO organization (id, name) VALUES (v_org, 'M7 T04 DML');
  PERFORM public._m7_initialize_organization_subscription(v_org, 'active');
  PERFORM _m7_t04_seed_auth(v_auth);
  INSERT INTO app_user (id, organization_id, email, display_name, auth_user_id, status, membership_status)
  VALUES (gen_random_uuid(), v_org, v_auth::text || '@m7t04.local', 'DML Staff', v_auth, 'active', 'member');
  PERFORM public.suspend_organization_subscription(v_org);
  PERFORM _m7_t04_as_auth(v_auth);
  BEGIN
    INSERT INTO student (organization_id, given_name, family_name, status)
    VALUES (v_org, 'Blocked', 'Student', 'active');
    v_denied := false;
  EXCEPTION WHEN OTHERS THEN
    v_denied := true;
  END;
  PERFORM _m7_t04_record(12, 'direct student insert denied when suspended', v_denied);
END $$;

-- 13: primary owner special-case contained (is_primary_owner false when suspended)
DO $$
DECLARE
  v_org uuid := gen_random_uuid();
  v_auth uuid := gen_random_uuid();
  v_app uuid := gen_random_uuid();
  v_owner boolean;
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
  INSERT INTO organization (id, name) VALUES (v_org, 'M7 T04 Owner Special');
  PERFORM public._m7_initialize_organization_subscription(v_org, 'active');
  PERFORM _m7_t04_seed_auth(v_auth);
  INSERT INTO app_user (id, organization_id, email, display_name, auth_user_id, status, membership_status)
  VALUES (v_app, v_org, v_auth::text || '@m7t04.local', 'Special Owner', v_auth, 'active', 'member');
  UPDATE organization_entitlement SET primary_app_user_id = v_app WHERE organization_id = v_org;
  PERFORM public.suspend_organization_subscription(v_org);
  PERFORM _m7_t04_as_auth(v_auth);
  SELECT public.is_primary_owner() INTO v_owner;
  PERFORM _m7_t04_record(13, 'suspended owner is_primary_owner false', NOT v_owner);
END $$;

-- 14: service_role commercial actions still work
DO $$
DECLARE v_org uuid := gen_random_uuid(); v_ok boolean;
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
  INSERT INTO organization (id, name) VALUES (v_org, 'M7 T04 Operator');
  PERFORM public._m7_initialize_organization_subscription(v_org, 'provisioning');
  PERFORM public.activate_organization_subscription(v_org);
  SELECT EXISTS (
    SELECT 1 FROM organization_subscription os
    WHERE os.organization_id = v_org AND os.status = 'active'
  ) INTO v_ok;
  PERFORM _m7_t04_record(14, 'service_role activate subscription', v_ok);
END $$;

-- 15: reactivation restores normal use
DO $$
DECLARE
  v_org uuid := gen_random_uuid();
  v_auth uuid := gen_random_uuid();
  v_active boolean;
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
  INSERT INTO organization (id, name) VALUES (v_org, 'M7 T04 Reactivate Use');
  PERFORM public._m7_initialize_organization_subscription(v_org, 'active');
  PERFORM _m7_t04_seed_auth(v_auth);
  INSERT INTO app_user (id, organization_id, email, display_name, auth_user_id, status, membership_status)
  VALUES (gen_random_uuid(), v_org, v_auth::text || '@m7t04.local', 'React Staff', v_auth, 'active', 'member');
  PERFORM public.suspend_organization_subscription(v_org);
  PERFORM public.reactivate_organization_subscription(v_org);
  PERFORM _m7_t04_as_auth(v_auth);
  SELECT public.is_active_app_user() INTO v_active;
  PERFORM _m7_t04_record(15, 'reactivation restores is_active_app_user', v_active);
END $$;

-- 16: reactivation does not mutate staff lifecycle
DO $$
DECLARE
  v_org uuid := gen_random_uuid();
  v_auth uuid := gen_random_uuid();
  v_app uuid := gen_random_uuid();
  v_membership_before text;
  v_membership_after text;
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
  INSERT INTO organization (id, name) VALUES (v_org, 'M7 T04 Reactivate Lifecycle');
  PERFORM public._m7_initialize_organization_subscription(v_org, 'active');
  PERFORM _m7_t04_seed_auth(v_auth);
  INSERT INTO app_user (id, organization_id, email, display_name, auth_user_id, status, membership_status)
  VALUES (v_app, v_org, v_auth::text || '@m7t04.local', 'React Life', v_auth, 'active', 'member');
  SELECT membership_status INTO v_membership_before FROM app_user WHERE id = v_app;
  PERFORM public.suspend_organization_subscription(v_org);
  PERFORM public.reactivate_organization_subscription(v_org);
  SELECT membership_status INTO v_membership_after FROM app_user WHERE id = v_app;
  PERFORM _m7_t04_record(
    16,
    'reactivation preserves staff membership_status',
    v_membership_before = 'member' AND v_membership_after = 'member'
  );
END $$;

-- 17: cancellation does not delete domain data
DO $$
DECLARE
  v_org uuid := gen_random_uuid();
  v_students integer;
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
  INSERT INTO organization (id, name) VALUES (v_org, 'M7 T04 Cancel Data');
  PERFORM public._m7_initialize_organization_subscription(v_org, 'active');
  INSERT INTO student (organization_id, given_name, family_name, status)
  VALUES (v_org, 'Keep', 'Me', 'active');
  PERFORM public.cancel_organization_subscription(v_org);
  SELECT count(*) INTO v_students FROM student WHERE organization_id = v_org;
  PERFORM _m7_t04_record(17, 'cancellation preserves student rows', v_students = 1);
END $$;

-- 18: missing subscription fails closed
DO $$
DECLARE
  v_org uuid := gen_random_uuid();
  v_auth uuid := gen_random_uuid();
  v_allows boolean;
  v_active boolean;
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
  INSERT INTO organization (id, name) VALUES (v_org, 'M7 T04 Missing Sub');
  UPDATE public.organization_entitlement
  SET organization_subscription_id = NULL, commercial_plan_id = NULL
  WHERE organization_id = v_org;
  DELETE FROM public.organization_subscription WHERE organization_id = v_org;
  PERFORM _m7_t04_seed_auth(v_auth);
  INSERT INTO app_user (id, organization_id, email, display_name, auth_user_id, status, membership_status)
  VALUES (gen_random_uuid(), v_org, v_auth::text || '@m7t04.local', 'Missing Sub', v_auth, 'active', 'member');
  PERFORM _m7_t04_as_auth(v_auth);
  SELECT
    public.organization_subscription_allows_normal_use(v_org),
    public.is_active_app_user()
  INTO v_allows, v_active;
  PERFORM _m7_t04_record(
    18,
    'missing subscription fails closed',
    NOT v_allows AND NOT v_active
  );
END $$;

-- 19: organization inactive remains independently blocked
DO $$
DECLARE
  v_org uuid := gen_random_uuid();
  v_auth uuid := gen_random_uuid();
  v_oper boolean;
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
  INSERT INTO organization (id, name, status) VALUES (v_org, 'M7 T04 Inactive Org', 'inactive');
  PERFORM public._m7_initialize_organization_subscription(v_org, 'active');
  PERFORM _m7_t04_seed_auth(v_auth);
  INSERT INTO app_user (id, organization_id, email, display_name, auth_user_id, status, membership_status)
  VALUES (gen_random_uuid(), v_org, v_auth::text || '@m7t04.local', 'Inactive Org User', v_auth, 'active', 'member');
  PERFORM _m7_t04_as_auth(v_auth);
  SELECT public.is_operationally_active_app_user() INTO v_oper;
  PERFORM _m7_t04_record(19, 'inactive organization blocks operational identity', NOT v_oper);
END $$;

-- 20: cross-org access remains denied
DO $$
DECLARE v_count integer;
BEGIN
  PERFORM _m7_t04_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_count
  FROM student
  WHERE organization_id = 'b0000000-0000-4000-8000-000000000001';
  PERFORM _m7_t04_record(20, 'cross-org student read denied by RLS', v_count = 0);
END $$;

SELECT test_no, test_name, result FROM _m7_t04_results ORDER BY test_no;

DO $$
DECLARE v_fail integer;
BEGIN
  SELECT count(*) INTO v_fail FROM _m7_t04_results WHERE result = 'FAIL';
  IF v_fail > 0 THEN
    RAISE EXCEPTION 'M7-T04 commercial access tests failed: % case(s)', v_fail;
  END IF;
END $$;
