-- M7-T02 trusted center + primary Owner provisioning tests

CREATE TEMP TABLE IF NOT EXISTS _m7_t02_results (
  test_no integer PRIMARY KEY,
  test_name text NOT NULL,
  result text NOT NULL CHECK (result IN ('PASS', 'FAIL'))
);

GRANT ALL ON TABLE _m7_t02_results TO authenticated, anon;

CREATE OR REPLACE FUNCTION _m7_t02_record(test_no integer, test_name text, passed boolean)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO _m7_t02_results (test_no, test_name, result)
  VALUES (test_no, test_name, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END);
END;
$$;

CREATE OR REPLACE FUNCTION _m7_t02_as_auth(p_auth_id uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', p_auth_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_auth_id::text, 'role', 'authenticated')::text, true);
END;
$$;

-- 1: authenticated cannot begin_center_provisioning
DO $$
DECLARE v_failed boolean := false;
BEGIN
  PERFORM _m7_t02_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.begin_center_provisioning(
      'm7-t02-deny-auth', 'Denied Org', 'deny@olli.local', 'Denied'
    );
    v_failed := false;
  EXCEPTION WHEN insufficient_privilege THEN
    v_failed := true;
  WHEN OTHERS THEN
    v_failed := SQLERRM LIKE '%permission denied%' OR SQLERRM LIKE '%42501%';
  END;
  PERFORM _m7_t02_record(1, 'authenticated cannot begin_center_provisioning', v_failed);
END $$;

-- 2: staff cannot begin
DO $$
DECLARE v_failed boolean := false;
BEGIN
  PERFORM _m7_t02_as_auth('a2222222-2222-4222-8222-222222222222');
  BEGIN
    PERFORM public.begin_center_provisioning(
      'm7-t02-deny-staff', 'Denied Org', 'deny-staff@olli.local', 'Denied'
    );
    v_failed := false;
  EXCEPTION WHEN OTHERS THEN
    v_failed := true;
  END;
  PERFORM _m7_t02_record(2, 'staff cannot begin_center_provisioning', v_failed);
END $$;

-- 3: idempotency conflict
DO $$
DECLARE v_failed boolean := false; v_begin jsonb;
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
  SELECT public.begin_center_provisioning(
    'm7-t02-idem-key',
    'Idem Org',
    'm7-idem-' || gen_random_uuid()::text || '@olli.local',
    'Owner A'
  ) INTO v_begin;
  BEGIN
    PERFORM public.begin_center_provisioning(
      'm7-t02-idem-key',
      'Idem Org',
      'other-' || gen_random_uuid()::text || '@olli.local',
      'Owner B'
    );
    v_failed := false;
  EXCEPTION WHEN OTHERS THEN
    v_failed := SQLERRM LIKE '%idempotency_conflict%';
  END;
  DELETE FROM center_provisioning_request WHERE idempotency_key = 'm7-t02-idem-key';
  PERFORM _m7_t02_record(3, 'idempotency_conflict on payload mismatch', v_failed);
END $$;

-- 4: finalize requires auth_created
DO $$
DECLARE v_failed boolean := false; v_req uuid;
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
  INSERT INTO center_provisioning_request (
    idempotency_key, payload_fingerprint, organization_name,
    owner_normalized_email, owner_display_name, owner_preferred_locale, status
  ) VALUES (
    'm7-t02-no-auth-' || gen_random_uuid()::text,
    'fp',
    'X',
    'm7-noauth@olli.local',
    'X',
    'vi',
    'pending_auth'
  ) RETURNING id INTO v_req;
  BEGIN
    PERFORM public.finalize_center_provisioning(v_req);
    v_failed := false;
  EXCEPTION WHEN OTHERS THEN
    v_failed := SQLERRM LIKE '%invalid_request_state%';
  END;
  DELETE FROM center_provisioning_request WHERE id = v_req;
  PERFORM _m7_t02_record(4, 'finalize rejects pending_auth', v_failed);
END $$;

-- 5: end-to-end postgres finalize creates full graph
DO $$
DECLARE
  v_email text := 'm7-finalize-' || gen_random_uuid()::text || '@olli.local';
  v_auth uuid := gen_random_uuid();
  v_req uuid;
  v_result jsonb;
  v_org uuid;
  v_owner uuid;
  v_staff_limit integer;
  v_primary uuid;
  v_roles integer;
  v_cost integer;
  v_cm boolean;
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;

  SELECT (public.begin_center_provisioning(
    'm7-t02-e2e-' || gen_random_uuid()::text,
    'M7 E2E Center',
    v_email,
    'M7 Owner',
    'vi',
    'vi',
    'Asia/Ho_Chi_Minh',
    'VND'
  )->>'request_id')::uuid INTO v_req;

  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at, is_sso_user, is_anonymous
  )
  VALUES (
    v_auth,
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

  PERFORM public.record_center_provisioning_auth_created(v_req, v_auth, true);
  SELECT public.finalize_center_provisioning(v_req) INTO v_result;

  v_org := (v_result->>'organization_id')::uuid;
  v_owner := (v_result->>'owner_app_user_id')::uuid;

  SELECT oe.staff_limit, oe.primary_app_user_id
    INTO v_staff_limit, v_primary
  FROM organization_entitlement oe
  WHERE oe.organization_id = v_org;

  SELECT count(*)::integer INTO v_roles
  FROM role r
  WHERE r.organization_id = v_org AND r.is_canonical_template AND r.status = 'active';

  SELECT count(*)::integer INTO v_cost
  FROM cost_group cg WHERE cg.organization_id = v_org;

  SELECT EXISTS (
    SELECT 1
    FROM user_role ur
    JOIN role r ON r.id = ur.role_id
    WHERE ur.organization_id = v_org
      AND ur.user_id = v_owner
      AND ur.status = 'active'
      AND r.canonical_code = 'center_manager'
  ) INTO v_cm;

  PERFORM _m7_t02_record(
    5,
    'finalize creates org bootstrap primary Owner and center_manager',
    (v_result->>'status') = 'completed'
      AND v_staff_limit = 5
      AND v_primary = v_owner
      AND v_roles = 5
      AND v_cost >= 2
      AND v_cm
  );
END $$;

-- 6: identity conflict when auth already mapped
DO $$
DECLARE
  v_failed boolean := false;
  v_req uuid;
  v_auth uuid := 'a1111111-1111-4111-8111-111111111111';
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
  SELECT (public.begin_center_provisioning(
    'm7-t02-conflict-' || gen_random_uuid()::text,
    'Conflict Org',
    'conflict-' || gen_random_uuid()::text || '@olli.local',
    'Conflict Owner'
  )->>'request_id')::uuid INTO v_req;

  BEGIN
    PERFORM public.record_center_provisioning_auth_created(v_req, v_auth, true);
    v_failed := false;
  EXCEPTION WHEN OTHERS THEN
    v_failed := SQLERRM LIKE '%identity_conflict%';
  END;

  DELETE FROM center_provisioning_request WHERE id = v_req;
  PERFORM _m7_t02_record(6, 'record auth rejects existing mapped auth user', v_failed);
END $$;

-- 7: idempotent finalize retry
DO $$
DECLARE
  v_email text := 'm7-retry-' || gen_random_uuid()::text || '@olli.local';
  v_auth uuid := gen_random_uuid();
  v_key text := 'm7-t02-retry-' || gen_random_uuid()::text;
  v_req uuid;
  v_first jsonb;
  v_second jsonb;
  v_org uuid;
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;

  SELECT (public.begin_center_provisioning(v_key, 'Retry Org', v_email, 'Retry Owner')->>'request_id')::uuid
    INTO v_req;

  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at, is_sso_user, is_anonymous
  )
  VALUES (
    v_auth, (SELECT id FROM auth.instances LIMIT 1), 'authenticated', 'authenticated',
    v_email, '', now(), now(), now(), false, false
  );

  PERFORM public.record_center_provisioning_auth_created(v_req, v_auth, true);
  SELECT public.finalize_center_provisioning(v_req) INTO v_first;
  SELECT public.finalize_center_provisioning(v_req) INTO v_second;
  v_org := (v_second->>'organization_id')::uuid;

  PERFORM _m7_t02_record(
    7,
    'finalize idempotent on completed request',
    (v_first->>'organization_id') = (v_second->>'organization_id')
      AND (v_second->>'outcome') = 'completed'
  );
END $$;

-- Summary
DO $$
DECLARE v_fail integer;
BEGIN
  SELECT count(*) INTO v_fail FROM _m7_t02_results WHERE result = 'FAIL';
  IF v_fail > 0 THEN
    RAISE EXCEPTION 'M7-T02 tests failed: % failing cases', v_fail;
  END IF;
  RAISE NOTICE 'M7-T02 center provisioning tests: all PASS';
END $$;
