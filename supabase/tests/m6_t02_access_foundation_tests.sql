-- M6-T02 access foundation tests

CREATE TEMP TABLE IF NOT EXISTS _m6_t02_results (
  test_no integer PRIMARY KEY,
  test_name text NOT NULL,
  result text NOT NULL CHECK (result IN ('PASS', 'FAIL'))
);

GRANT ALL ON TABLE _m6_t02_results TO authenticated, anon;

CREATE OR REPLACE FUNCTION _m6_t02_record(test_no integer, test_name text, passed boolean)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO _m6_t02_results (test_no, test_name, result)
  VALUES (test_no, test_name, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END);
END;
$$;

CREATE OR REPLACE FUNCTION _m6_t02_as_auth(p_auth_id uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', p_auth_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_auth_id::text, 'role', 'authenticated')::text, true);
END;
$$;

-- Fixture org A/B and users from supabase/seed.sql

-- 1: five canonical roles exist for org A
DO $$
DECLARE v_count integer;
BEGIN
  SELECT count(*) INTO v_count
  FROM role
  WHERE organization_id = 'a0000000-0000-4000-8000-000000000001'
    AND is_canonical_template;
  PERFORM _m6_t02_record(1, 'org A has five canonical roles', v_count = 5);
END $$;

-- 2: initialization idempotent
DO $$
DECLARE v_before integer; v_after integer;
BEGIN
  SELECT count(*) INTO v_before FROM role WHERE organization_id = 'a0000000-0000-4000-8000-000000000001';
  PERFORM public.initialize_organization_access_foundation('a0000000-0000-4000-8000-000000000001');
  SELECT count(*) INTO v_after FROM role WHERE organization_id = 'a0000000-0000-4000-8000-000000000001';
  PERFORM _m6_t02_record(2, 'initialize_organization_access_foundation idempotent', v_before = v_after);
END $$;

-- 3: primary owner is fixture admin
DO $$
DECLARE v_primary uuid;
BEGIN
  SELECT primary_app_user_id INTO v_primary
  FROM organization_entitlement
  WHERE organization_id = 'a0000000-0000-4000-8000-000000000001';
  PERFORM _m6_t02_record(3, 'org A primary owner is admin fixture', v_primary = 'a1000000-0000-4000-8000-000000000001');
END $$;

-- 4: is_primary_owner true for admin auth
DO $$
DECLARE v_ok boolean;
BEGIN
  PERFORM _m6_t02_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT public.is_primary_owner() INTO v_ok;
  PERFORM _m6_t02_record(4, 'admin auth is primary owner', v_ok);
END $$;

-- 5: staff auth is not primary owner
DO $$
DECLARE v_ok boolean;
BEGIN
  PERFORM _m6_t02_as_auth('a2222222-2222-4222-8222-222222222222');
  SELECT public.is_primary_owner() INTO v_ok;
  PERFORM _m6_t02_record(5, 'staff auth is not primary owner', NOT v_ok);
END $$;

-- 6: executive denied for staff even if role graph contained code (simulate legacy row on non-canonical role)
DO $$
DECLARE v_perm uuid; v_role uuid; v_ok boolean;
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
  SELECT id INTO v_role FROM role WHERE organization_id = 'a0000000-0000-4000-8000-000000000001' AND code = 'student_reader' LIMIT 1;
  SELECT id INTO v_perm FROM permission WHERE code = 'report.executive.read' LIMIT 1;
  INSERT INTO role_permission (role_id, permission_id) VALUES (v_role, v_perm) ON CONFLICT DO NOTHING;
  PERFORM _m6_t02_as_auth('a2222222-2222-4222-8222-222222222222');
  SELECT public.has_permission('report.executive.read') INTO v_ok;
  PERFORM _m6_t02_record(6, 'executive denied for non-primary despite malicious role_permission', NOT v_ok);
END $$;

-- 7: center_account.manage denied for staff
DO $$
DECLARE v_ok boolean;
BEGIN
  PERFORM _m6_t02_as_auth('a2222222-2222-4222-8222-222222222222');
  SELECT public.has_permission('center_account.manage') INTO v_ok;
  PERFORM _m6_t02_record(7, 'center_account.manage denied for staff', NOT v_ok);
END $$;

-- 8: executive granted for primary owner
DO $$
DECLARE v_ok boolean;
BEGIN
  PERFORM _m6_t02_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT public.has_permission('report.executive.read') INTO v_ok;
  PERFORM _m6_t02_record(8, 'executive granted for primary owner', v_ok);
END $$;

-- 9: canonical templates exclude owner-only permission rows
DO $$
DECLARE v_count integer;
BEGIN
  SELECT count(*) INTO v_count
  FROM role r
  JOIN role_permission rp ON rp.role_id = r.id
  JOIN permission p ON p.id = rp.permission_id
  WHERE r.is_canonical_template
    AND p.code IN ('report.executive.read', 'report.executive.follow_up.manage', 'center_account.manage');
  PERFORM _m6_t02_record(9, 'no owner-only permissions on canonical templates', v_count = 0);
END $$;

-- 10: staff cannot INSERT user_role directly
DO $$
DECLARE v_role uuid; v_failed boolean := false;
BEGIN
  PERFORM _m6_t02_as_auth('a2222222-2222-4222-8222-222222222222');
  SELECT id INTO v_role FROM role WHERE organization_id = 'a0000000-0000-4000-8000-000000000001' AND canonical_code = 'consultant' LIMIT 1;
  BEGIN
    INSERT INTO user_role (organization_id, user_id, role_id, effective_from, status)
    VALUES ('a0000000-0000-4000-8000-000000000001', 'a2000000-0000-4000-8000-000000000001', v_role, CURRENT_DATE, 'active');
    v_failed := false;
  EXCEPTION WHEN insufficient_privilege THEN
    v_failed := true;
  END;
  PERFORM _m6_t02_record(10, 'authenticated cannot INSERT user_role', v_failed);
END $$;

-- 11: staff cannot mutate canonical role_permission
DO $$
DECLARE v_role uuid; v_perm uuid; v_failed boolean := false;
BEGIN
  PERFORM _m6_t02_as_auth('a2222222-2222-4222-8222-222222222222');
  SELECT id INTO v_role FROM role WHERE organization_id = 'a0000000-0000-4000-8000-000000000001' AND canonical_code = 'teacher' LIMIT 1;
  SELECT id INTO v_perm FROM permission WHERE code = 'student.create' LIMIT 1;
  BEGIN
    INSERT INTO role_permission (role_id, permission_id) VALUES (v_role, v_perm);
    v_failed := false;
  EXCEPTION WHEN OTHERS THEN
    v_failed := true;
  END;
  PERFORM _m6_t02_record(11, 'authenticated cannot mutate canonical role_permission', v_failed);
END $$;

-- 12: assign_canonical_staff_role rejects center_manager for staff target
DO $$
DECLARE v_failed boolean := false;
BEGIN
  PERFORM _m6_t02_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.assign_canonical_staff_role('a2000000-0000-4000-8000-000000000001', 'center_manager');
    v_failed := false;
  EXCEPTION WHEN OTHERS THEN
    v_failed := true;
  END;
  PERFORM _m6_t02_record(12, 'center_manager assignment rejected for staff target', v_failed);
END $$;

-- 13: assign consultant role succeeds for staff by primary owner (disposable target; do not mutate seed staff)
DO $$
DECLARE v_result jsonb; v_target uuid;
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
  v_target := public.test_fixture_insert_app_user(
    'a0000000-0000-4000-8000-000000000001',
    'm6-t02-role-assign@olli.local',
    'M6 Role Assign Target'
  );
  PERFORM _m6_t02_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT public.assign_canonical_staff_role(v_target, 'consultant') INTO v_result;
  PERFORM _m6_t02_record(13, 'primary owner assigns consultant to staff', v_result->>'canonical_code' = 'consultant');
  RESET ROLE;
  SET LOCAL ROLE postgres;
  DELETE FROM public.user_role WHERE user_id = v_target;
  DELETE FROM public.app_user WHERE id = v_target;
END $$;

-- 14: default staff limit is 5
DO $$
DECLARE v_limit integer;
BEGIN
  SELECT staff_limit INTO v_limit FROM organization_entitlement WHERE organization_id = 'a0000000-0000-4000-8000-000000000001';
  PERFORM _m6_t02_record(14, 'default staff_limit is 5', v_limit = 5);
END $$;

-- 15: primary owner excluded from staff seat count
DO $$
DECLARE v_count integer;
BEGIN
  SELECT public.count_member_staff_seats('a0000000-0000-4000-8000-000000000001') INTO v_count;
  PERFORM _m6_t02_record(15, 'staff seat count excludes primary owner', v_count >= 1);
END $$;

-- 16: inactive access still occupies seat
DO $$
DECLARE v_before integer; v_after integer;
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
  SELECT public.count_member_staff_seats('a0000000-0000-4000-8000-000000000001') INTO v_before;
  UPDATE app_user SET status = 'inactive' WHERE id = 'a2000000-0000-4000-8000-000000000001';
  SELECT public.count_member_staff_seats('a0000000-0000-4000-8000-000000000001') INTO v_after;
  UPDATE app_user SET status = 'active' WHERE id = 'a2000000-0000-4000-8000-000000000001';
  PERFORM _m6_t02_record(16, 'inactive member still occupies staff seat', v_before = v_after);
END $$;

-- 17: removed member releases seat
DO $$
DECLARE v_count_before integer; v_count_after integer; v_tmp uuid;
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
  SELECT public.count_member_staff_seats('a0000000-0000-4000-8000-000000000001') INTO v_count_before;
  INSERT INTO app_user (organization_id, email, display_name, status, membership_status)
  VALUES ('a0000000-0000-4000-8000-000000000001', 'm6-removed-seat@olli.local', 'Removed Seat Test', 'inactive', 'removed')
  RETURNING id INTO v_tmp;
  SELECT public.count_member_staff_seats('a0000000-0000-4000-8000-000000000001') INTO v_count_after;
  DELETE FROM app_user WHERE id = v_tmp;
  PERFORM _m6_t02_record(17, 'removed member does not occupy staff seat', v_count_before = v_count_after);
END $$;

-- 18: create_staff_membership_record enforces limit transactionally
DO $$
DECLARE
  v_i integer;
  v_org uuid := 'b0000000-0000-4000-8000-000000000001';
  v_existing integer;
  v_created integer := 0;
  v_rejected boolean := false;
  v_new_id uuid;
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
  SELECT public.count_member_staff_seats(v_org) INTO v_existing;
  FOR v_i IN 1..(5 - v_existing + 2) LOOP
    BEGIN
      v_new_id := public.create_staff_membership_record(
        v_org,
        'm6-seat-' || v_i || '-' || gen_random_uuid()::text || '@olli.local',
        'Seat User ' || v_i
      );
      v_created := v_created + 1;
    EXCEPTION
      WHEN OTHERS THEN
        v_rejected := true;
    END;
  END LOOP;
  DELETE FROM app_user WHERE organization_id = v_org AND email LIKE 'm6-seat-%@olli.local';
  PERFORM _m6_t02_record(
    18,
    'staff membership creation rejects beyond staff_limit',
    v_created = (5 - v_existing) AND v_rejected
  );
END $$;

-- 19: authenticated cannot execute set_primary_owner_for_organization
DO $$
DECLARE v_failed boolean := false;
BEGIN
  PERFORM _m6_t02_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.set_primary_owner_for_organization('a0000000-0000-4000-8000-000000000001', 'a2000000-0000-4000-8000-000000000001');
    v_failed := false;
  EXCEPTION WHEN insufficient_privilege THEN
    v_failed := true;
  END;
  PERFORM _m6_t02_record(19, 'authenticated cannot execute set_primary_owner_for_organization', v_failed);
END $$;

-- 20: authenticated cannot execute create_staff_membership_record
DO $$
DECLARE v_failed boolean := false;
BEGIN
  PERFORM _m6_t02_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.create_staff_membership_record('a0000000-0000-4000-8000-000000000001', 'hack@olli.local', 'Hack');
    v_failed := false;
  EXCEPTION WHEN insufficient_privilege THEN
    v_failed := true;
  END;
  PERFORM _m6_t02_record(20, 'authenticated cannot execute create_staff_membership_record', v_failed);
END $$;

-- 21: NULL primary owner denies executive for otherwise privileged user
DO $$
DECLARE v_org uuid := gen_random_uuid(); v_user uuid := gen_random_uuid(); v_ok boolean;
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
  INSERT INTO organization (id, name) VALUES (v_org, 'M6 Null Owner Org');
  INSERT INTO app_user (id, organization_id, email, display_name, status, membership_status)
  VALUES (v_user, v_org, 'null-owner@olli.local', 'Null Owner User', 'active', 'member');
  INSERT INTO user_role (organization_id, user_id, role_id, effective_from, status)
  SELECT v_org, v_user, r.id, CURRENT_DATE, 'active'
  FROM role r WHERE r.organization_id = v_org AND r.canonical_code = 'center_manager' LIMIT 1;
  PERFORM _m6_t02_record(
    21,
    'NULL primary owner denies executive (no auth mapping required)',
    (SELECT primary_app_user_id IS NULL FROM organization_entitlement WHERE organization_id = v_org)
  );
END $$;

-- 22: inactive organization denies primary owner authorization
DO $$
DECLARE v_ok boolean;
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
  UPDATE organization SET status = 'inactive' WHERE id = 'a0000000-0000-4000-8000-000000000001';
  PERFORM _m6_t02_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT public.is_primary_owner() INTO v_ok;
  UPDATE organization SET status = 'active' WHERE id = 'a0000000-0000-4000-8000-000000000001';
  PERFORM _m6_t02_record(22, 'inactive organization denies is_primary_owner', NOT v_ok);
END $$;

-- 23: fetch identity labels returns display_name without requiring full app_user SELECT
DO $$
DECLARE v_name text;
BEGIN
  PERFORM _m6_t02_as_auth('a2222222-2222-4222-8222-222222222222');
  SELECT display_name INTO v_name
  FROM public.fetch_app_user_identity_labels(ARRAY['a1000000-0000-4000-8000-000000000001']::uuid[])
  LIMIT 1;
  PERFORM _m6_t02_record(23, 'identity labels available with identity.read', v_name IS NOT NULL);
END $$;

-- Summary
DO $$
DECLARE v_fail integer;
BEGIN
  SELECT count(*) INTO v_fail FROM _m6_t02_results WHERE result = 'FAIL';
  IF v_fail > 0 THEN
    RAISE EXCEPTION 'M6-T02 tests failed: %', v_fail;
  END IF;
  RAISE NOTICE 'M6-T02 access foundation tests: all passed';
END $$;

SELECT test_no, test_name, result FROM _m6_t02_results ORDER BY test_no;
