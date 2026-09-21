-- M6-T03 trusted staff provisioning tests

CREATE TEMP TABLE IF NOT EXISTS _m6_t03_results (
  test_no integer PRIMARY KEY,
  test_name text NOT NULL,
  result text NOT NULL CHECK (result IN ('PASS', 'FAIL'))
);

GRANT ALL ON TABLE _m6_t03_results TO authenticated, anon;

CREATE OR REPLACE FUNCTION _m6_t03_record(test_no integer, test_name text, passed boolean)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO _m6_t03_results (test_no, test_name, result)
  VALUES (test_no, test_name, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END);
END;
$$;

CREATE OR REPLACE FUNCTION _m6_t03_as_auth(p_auth_id uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', p_auth_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_auth_id::text, 'role', 'authenticated')::text, true);
END;
$$;

-- 1: begin requires primary owner
DO $$
DECLARE v_failed boolean := false;
BEGIN
  PERFORM _m6_t03_as_auth('a2222222-2222-4222-8222-222222222222');
  BEGIN
    PERFORM public.begin_staff_provisioning('k1', 't1@olli.local', 'T1', 'teacher');
    v_failed := false;
  EXCEPTION WHEN OTHERS THEN
    v_failed := SQLERRM LIKE '%not_primary_owner%';
  END;
  PERFORM _m6_t03_record(1, 'non-owner cannot begin provisioning', v_failed);
END $$;

-- 2: begin rejects center_manager role
DO $$
DECLARE v_failed boolean := false;
BEGIN
  PERFORM _m6_t03_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.begin_staff_provisioning('k2', 't2@olli.local', 'T2', 'center_manager');
    v_failed := false;
  EXCEPTION WHEN OTHERS THEN
    v_failed := SQLERRM LIKE '%invalid_role%';
  END;
  PERFORM _m6_t03_record(2, 'begin rejects center_manager', v_failed);
END $$;

-- 3: member_already_exists for current org member email
DO $$
DECLARE v_failed boolean := false;
BEGIN
  PERFORM _m6_t03_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.begin_staff_provisioning('k3', 'org-a-staff@olli.local', 'Dup', 'teacher');
    v_failed := false;
  EXCEPTION WHEN OTHERS THEN
    v_failed := SQLERRM LIKE '%member_already_exists%';
  END;
  PERFORM _m6_t03_record(3, 'duplicate same-org member email rejected', v_failed);
END $$;

-- 4: idempotency conflict on different payload
DO $$
DECLARE v_failed boolean := false; v_id uuid; v_begin jsonb;
BEGIN
  PERFORM _m6_t03_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT public.begin_staff_provisioning('k4', 'm6-idem-a@olli.local', 'A', 'teacher') INTO v_begin;
  v_id := (v_begin->>'request_id')::uuid;
  BEGIN
    PERFORM public.begin_staff_provisioning('k4', 'm6-idem-b@olli.local', 'B', 'teacher');
    v_failed := false;
  EXCEPTION WHEN OTHERS THEN
    v_failed := SQLERRM LIKE '%idempotency_conflict%';
  END;
  DELETE FROM staff_provisioning_request WHERE id = v_id;
  PERFORM _m6_t03_record(4, 'idempotency key payload conflict rejected', v_failed);
END $$;

-- 5: service finalize + record denied to authenticated
DO $$
DECLARE v_failed boolean := true; v_req uuid := gen_random_uuid();
BEGIN
  PERFORM _m6_t03_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.record_provisioning_auth_created(v_req, gen_random_uuid(), gen_random_uuid());
    v_failed := false;
  EXCEPTION WHEN insufficient_privilege THEN
    v_failed := true;
  END;
  BEGIN
    PERFORM public.finalize_staff_provisioning(v_req);
    v_failed := false;
  EXCEPTION WHEN insufficient_privilege THEN
    v_failed := v_failed AND true;
  END;
  PERFORM _m6_t03_record(5, 'authenticated cannot record or finalize', v_failed);
END $$;

-- 6: finalize requires auth_created correlation
DO $$
DECLARE v_req uuid; v_ok boolean := false;
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
  INSERT INTO staff_provisioning_request (
    organization_id, requesting_owner_app_user_id, idempotency_key, payload_fingerprint,
    normalized_email, display_name, canonical_role, status
  ) VALUES (
    'a0000000-0000-4000-8000-000000000001',
    'a1000000-0000-4000-8000-000000000001',
    'k6-' || gen_random_uuid()::text,
    'fp',
    'm6-noauth@olli.local',
    'No Auth',
    'teacher',
    'requested'
  ) RETURNING id INTO v_req;
  BEGIN
    PERFORM public.finalize_staff_provisioning(v_req);
    v_ok := false;
  EXCEPTION WHEN OTHERS THEN
    v_ok := true;
  END;
  DELETE FROM staff_provisioning_request WHERE id = v_req;
  PERFORM _m6_t03_record(6, 'finalize rejects without auth_created state', v_ok);
END $$;

-- 7: end-to-end finalize with correlated auth (postgres path)
DO $$
DECLARE
  v_org uuid := gen_random_uuid();
  v_owner uuid;
  v_req uuid;
  v_email text := 'm6-finalize-' || gen_random_uuid()::text || '@olli.local';
  v_auth uuid := gen_random_uuid();
  v_token uuid := gen_random_uuid();
  v_result jsonb;
  v_app uuid;
  v_seats_before integer;
  v_seats_after integer;
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
  INSERT INTO organization (id, name) VALUES (v_org, 'M6 T03 Finalize Org');
  v_owner := public.test_fixture_insert_app_user(v_org, 'm6-owner-' || v_org::text || '@olli.local', 'Owner');
  PERFORM public.set_primary_owner_for_organization(v_org, v_owner);
  SELECT public.count_member_staff_seats(v_org) INTO v_seats_before;
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
  INSERT INTO staff_provisioning_request (
    organization_id, requesting_owner_app_user_id, idempotency_key, payload_fingerprint,
    normalized_email, display_name, canonical_role, preferred_locale, status,
    processing_token, processing_started_at, lease_expires_at
  ) VALUES (
    v_org,
    v_owner,
    'k7-' || gen_random_uuid()::text,
    public._m6_provisioning_payload_fingerprint(v_email, 'Finalize User', 'accountant', 'vi'),
    v_email,
    'Finalize User',
    'accountant',
    'vi',
    'auth_pending',
    v_token,
    now(),
    now() + interval '5 minutes'
  ) RETURNING id INTO v_req;

  PERFORM public.record_provisioning_auth_created(v_req, v_auth, v_token);
  SELECT public.finalize_staff_provisioning(v_req) INTO v_result;
  v_app := (v_result->>'app_user_id')::uuid;
  SELECT public.count_member_staff_seats(v_org) INTO v_seats_after;

  DELETE FROM user_role WHERE user_id = v_app;
  DELETE FROM app_user WHERE id = v_app;
  DELETE FROM auth.users WHERE id = v_auth;
  DELETE FROM staff_provisioning_request WHERE id = v_req;

  PERFORM _m6_t03_record(
    7,
    'finalize creates member with role and consumes seat',
    (v_result->>'status') = 'completed'
      AND v_app IS NOT NULL
      AND v_seats_after = v_seats_before + 1
  );
END $$;

-- 8: staff seat limit on finalize sets compensation_pending
DO $$
DECLARE
  v_org uuid := gen_random_uuid();
  v_owner uuid;
  v_i integer;
  v_req uuid;
  v_auth uuid;
  v_token uuid;
  v_status text;
  v_seats integer;
  v_result_code text;
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
  INSERT INTO organization (id, name) VALUES (v_org, 'M6 T03 Seat Limit Org');
  v_owner := public.test_fixture_insert_app_user(v_org, 'm6-limit-owner-' || v_org::text || '@olli.local', 'Owner');
  PERFORM public.set_primary_owner_for_organization(v_org, v_owner);
  FOR v_i IN 1..5 LOOP
    BEGIN
      PERFORM public.create_staff_membership_record(
        v_org,
        'm6-limit-' || v_i || '-' || gen_random_uuid()::text || '@olli.local',
        'Limit ' || v_i
      );
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END LOOP;
  SELECT public.count_member_staff_seats(v_org) INTO v_seats;
  v_auth := gen_random_uuid();
  v_token := gen_random_uuid();
  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at, is_sso_user, is_anonymous
  )
  VALUES (
    v_auth,
    (SELECT id FROM auth.instances LIMIT 1),
    'authenticated',
    'authenticated',
    'm6-over-limit-' || v_org::text || '@olli.local',
    '',
    now(),
    now(),
    now(),
    false,
    false
  );
  INSERT INTO staff_provisioning_request (
    organization_id, requesting_owner_app_user_id, idempotency_key, payload_fingerprint,
    normalized_email, display_name, canonical_role, status,
    auth_user_id, auth_created_by_this_request,
    processing_token, lease_expires_at
  ) VALUES (
    v_org,
    v_owner,
    'k8-' || gen_random_uuid()::text,
    'fp8',
    'm6-over-limit-' || v_org::text || '@olli.local',
    'Over',
    'teacher',
    'auth_created',
    v_auth,
    true,
    v_token,
    now() + interval '5 minutes'
  ) RETURNING id INTO v_req;
  BEGIN
    PERFORM public.finalize_staff_provisioning(v_req);
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;
  SELECT status, result_code INTO v_status, v_result_code
  FROM staff_provisioning_request WHERE id = v_req;
  DELETE FROM staff_provisioning_request WHERE id = v_req;
  DELETE FROM auth.users WHERE id = v_auth;
  PERFORM _m6_t03_record(
    8,
    'finalize over staff_limit enters compensation_pending',
    v_seats >= 5
      AND v_status = 'compensation_pending'
      AND v_result_code = 'staff_seat_limit_exceeded'
  );
END $$;

-- 9: claim returns provisioning_pending when lease held
DO $$
DECLARE
  v_req uuid;
  v_claim jsonb;
BEGIN
  PERFORM _m6_t03_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT public.begin_staff_provisioning(
    'k9-' || gen_random_uuid()::text,
    'm6-claim-pending@olli.local',
    'Claim',
    'teacher'
  ) INTO v_claim;
  v_req := (v_claim->>'request_id')::uuid;
  PERFORM public.claim_provisioning_auth_execution(v_req, NULL);
  SELECT public.claim_provisioning_auth_execution(v_req, NULL) INTO v_claim;
  DELETE FROM staff_provisioning_request WHERE id = v_req;
  PERFORM _m6_t03_record(9, 'concurrent claim yields provisioning_pending', v_claim->>'outcome' = 'provisioning_pending');
END $$;

-- 10: create_staff_membership_record still denied to authenticated
DO $$
DECLARE v_failed boolean := false;
BEGIN
  PERFORM _m6_t03_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.create_staff_membership_record('a0000000-0000-4000-8000-000000000001', 'hack@olli.local', 'Hack');
    v_failed := false;
  EXCEPTION WHEN insufficient_privilege THEN
    v_failed := true;
  END;
  PERFORM _m6_t03_record(10, 'T02 membership primitive still service-only', v_failed);
END $$;

DO $$
DECLARE v_fail integer;
BEGIN
  SELECT count(*) INTO v_fail FROM _m6_t03_results WHERE result = 'FAIL';
  IF v_fail > 0 THEN
    RAISE EXCEPTION 'M6-T03 tests failed: % — %', v_fail,
      (SELECT string_agg(test_no::text || ':' || test_name, '; ') FROM _m6_t03_results WHERE result = 'FAIL');
  END IF;
  RAISE NOTICE 'M6-T03 staff provisioning tests: all passed (10/10)';
END $$;
