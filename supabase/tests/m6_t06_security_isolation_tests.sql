-- M6-T06: Security, RLS & organization-isolation regression (post-T05)

CREATE TEMP TABLE IF NOT EXISTS _m6_t06_results (
  test_no integer PRIMARY KEY,
  test_name text NOT NULL,
  result text NOT NULL CHECK (result IN ('PASS', 'FAIL'))
);

GRANT ALL ON TABLE _m6_t06_results TO authenticated, anon;

CREATE OR REPLACE FUNCTION _m6_t06_record(test_no integer, test_name text, passed boolean)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO _m6_t06_results (test_no, test_name, result)
  VALUES (test_no, test_name, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END);
END;
$$;

CREATE OR REPLACE FUNCTION _m6_t06_as_auth(p_auth_id uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', p_auth_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_auth_id::text, 'role', 'authenticated')::text, true);
END;
$$;

-- Fixture UUIDs (supabase/seed.sql)
-- Org A: a0000000-0000-4000-8000-000000000001
-- Org B: b0000000-0000-4000-8000-000000000001
-- Org A primary: a1000000-0000-4000-8000-000000000001  auth a1111111-...
-- Org A staff:   a2000000-0000-4000-8000-000000000001  auth a2222222-...
-- Org B staff:   b2000000-0000-4000-8000-000000000001

-- T06-01 — Cross-org lifecycle suspend
DO $$
DECLARE
  v_failed boolean := false;
  v_status text;
  v_events integer;
BEGIN
  PERFORM _m6_t06_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_events
  FROM public.staff_lifecycle_event
  WHERE organization_id = 'b0000000-0000-4000-8000-000000000001'
    AND target_app_user_id = 'b2000000-0000-4000-8000-000000000001';
  BEGIN
    PERFORM public.suspend_staff_member('b2000000-0000-4000-8000-000000000001');
    v_failed := false;
  EXCEPTION WHEN OTHERS THEN
    v_failed := SQLERRM LIKE '%target_not_found%';
  END;
  RESET ROLE;
  SET LOCAL ROLE postgres;
  SELECT status INTO v_status FROM public.app_user WHERE id = 'b2000000-0000-4000-8000-000000000001';
  SELECT count(*) INTO v_events
  FROM public.staff_lifecycle_event
  WHERE organization_id = 'b0000000-0000-4000-8000-000000000001'
    AND target_app_user_id = 'b2000000-0000-4000-8000-000000000001';
  PERFORM _m6_t06_record(
    1,
    'T06-01 cross-org suspend_staff_member',
    v_failed AND v_status = 'active' AND v_events = 0
  );
END $$;

-- T06-02 — Cross-org canonical role assignment
DO $$
DECLARE
  v_failed boolean := false;
  v_before integer;
  v_after integer;
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
  SELECT count(*) INTO v_before
  FROM public.user_role ur
  JOIN public.role r ON r.id = ur.role_id
  WHERE ur.user_id = 'b2000000-0000-4000-8000-000000000001'
    AND ur.organization_id = 'b0000000-0000-4000-8000-000000000001'
    AND ur.status = 'active'
    AND r.canonical_code = 'teacher';
  PERFORM _m6_t06_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.assign_canonical_staff_role('b2000000-0000-4000-8000-000000000001', 'teacher');
    v_failed := false;
  EXCEPTION WHEN OTHERS THEN
    v_failed := SQLERRM LIKE '%target_not_found%';
  END;
  RESET ROLE;
  SET LOCAL ROLE postgres;
  SELECT count(*) INTO v_after
  FROM public.user_role ur
  JOIN public.role r ON r.id = ur.role_id
  WHERE ur.user_id = 'b2000000-0000-4000-8000-000000000001'
    AND ur.organization_id = 'b0000000-0000-4000-8000-000000000001'
    AND ur.status = 'active'
    AND r.canonical_code = 'teacher';
  PERFORM _m6_t06_record(2, 'T06-02 cross-org assign_canonical_staff_role', v_failed AND v_before = v_after);
END $$;

-- T06-03 — Cross-org restore
DO $$
DECLARE
  v_failed boolean := false;
  v_id uuid;
  v_membership text;
  v_seats_before integer;
  v_seats_after integer;
  v_roles integer;
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
  v_id := public.test_fixture_insert_app_user(
    'b0000000-0000-4000-8000-000000000001',
    'm6-t06-removed-b@olli.local',
    'T06 Removed B',
    NULL,
    'inactive',
    'removed'
  );
  SELECT public.count_member_staff_seats('b0000000-0000-4000-8000-000000000001') INTO v_seats_before;
  PERFORM _m6_t06_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.restore_removed_staff(v_id, 'teacher');
    v_failed := false;
  EXCEPTION WHEN OTHERS THEN
    v_failed := SQLERRM LIKE '%target_not_found%';
  END;
  RESET ROLE;
  SET LOCAL ROLE postgres;
  SELECT membership_status INTO v_membership FROM public.app_user WHERE id = v_id;
  SELECT public.count_member_staff_seats('b0000000-0000-4000-8000-000000000001') INTO v_seats_after;
  SELECT count(*) INTO v_roles
  FROM public.user_role ur
  WHERE ur.user_id = v_id AND ur.status = 'active';
  DELETE FROM public.app_user WHERE id = v_id;
  PERFORM _m6_t06_record(
    3,
    'T06-03 cross-org restore_removed_staff',
    v_failed AND v_membership = 'removed' AND v_seats_before = v_seats_after AND v_roles = 0
  );
END $$;

-- T06-04 — Staff cannot call lifecycle RPCs
DO $$
DECLARE
  v_id uuid;
  v_status text;
  v_ok boolean := true;
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
  v_id := public.test_fixture_insert_app_user(
    'a0000000-0000-4000-8000-000000000001',
    'm6-t06-staff-target@olli.local',
    'T06 Staff Target',
    NULL,
    'active',
    'member'
  );
  INSERT INTO public.user_role (organization_id, user_id, role_id, effective_from, status)
  SELECT 'a0000000-0000-4000-8000-000000000001', v_id, r.id, CURRENT_DATE, 'active'
  FROM public.role r
  WHERE r.organization_id = 'a0000000-0000-4000-8000-000000000001'
    AND r.canonical_code = 'teacher'
  LIMIT 1;
  PERFORM _m6_t06_as_auth('a2222222-2222-4222-8222-222222222222');
  BEGIN PERFORM public.suspend_staff_member(v_id); v_ok := false; EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN PERFORM public.reactivate_staff_member(v_id); v_ok := false; EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN PERFORM public.remove_staff_from_center(v_id); v_ok := false; EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN PERFORM public.restore_removed_staff(v_id, 'teacher'); v_ok := false; EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN PERFORM public.assign_canonical_staff_role(v_id, 'consultant'); v_ok := false; EXCEPTION WHEN OTHERS THEN NULL; END;
  RESET ROLE;
  SET LOCAL ROLE postgres;
  SELECT status INTO v_status FROM public.app_user WHERE id = v_id;
  DELETE FROM public.user_role WHERE user_id = v_id;
  DELETE FROM public.app_user WHERE id = v_id;
  PERFORM _m6_t06_record(4, 'T06-04 staff lifecycle RPCs denied', v_ok AND v_status = 'active');
END $$;

-- T06-05 — Suspended identity loses operational access
DO $$
DECLARE
  v_students integer;
  v_gate boolean;
  v_has_student_read boolean;
  v_rpc_failed boolean := false;
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
  UPDATE public.app_user SET status = 'inactive' WHERE id = 'a2000000-0000-4000-8000-000000000001';
  PERFORM _m6_t06_as_auth('a2222222-2222-4222-8222-222222222222');
  SELECT public.current_app_user_id() IS NULL
     AND public.current_organization_id() IS NULL
     AND NOT public.is_active_app_user()
    INTO v_gate;
  SELECT public.has_permission('student.read') INTO v_has_student_read;
  SELECT count(*) INTO v_students FROM public.student;
  BEGIN
    PERFORM public.suspend_staff_member('a2000000-0000-4000-8000-000000000001');
    v_rpc_failed := false;
  EXCEPTION WHEN OTHERS THEN
    v_rpc_failed := SQLERRM LIKE '%not_primary_owner%' OR SQLERRM LIKE '%not_authenticated%';
  END;
  RESET ROLE;
  SET LOCAL ROLE postgres;
  UPDATE public.app_user SET status = 'active' WHERE id = 'a2000000-0000-4000-8000-000000000001';
  PERFORM _m6_t06_record(
    5,
    'T06-05 suspended member loses operational access',
    v_gate AND NOT v_has_student_read AND v_students = 0 AND v_rpc_failed
  );
END $$;

-- T06-06 — Malformed removed + active identity
DO $$
DECLARE
  v_id uuid;
  v_auth uuid := 'c1111111-1111-4111-8111-111111111111';
  v_gate boolean;
  v_has_perm boolean;
  v_students integer;
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
  v_id := public.test_fixture_insert_app_user(
    'a0000000-0000-4000-8000-000000000001',
    'm6-t06-malformed@olli.local',
    'T06 Malformed',
    NULL,
    'active',
    'removed'
  );
  UPDATE public.app_user SET auth_user_id = NULL
  WHERE auth_user_id = v_auth AND id IS DISTINCT FROM v_id;
  UPDATE public.app_user SET auth_user_id = v_auth WHERE id = v_id;
  PERFORM _m6_t06_as_auth(v_auth);
  SELECT public.current_app_user_id() IS NULL
     AND public.current_organization_id() IS NULL
     AND NOT public.is_active_app_user()
    INTO v_gate;
  SELECT public.has_permission('student.read') INTO v_has_perm;
  SELECT count(*) INTO v_students FROM public.student;
  RESET ROLE;
  SET LOCAL ROLE postgres;
  UPDATE public.app_user SET auth_user_id = NULL WHERE id = v_id;
  DELETE FROM public.app_user WHERE id = v_id;
  PERFORM _m6_t06_record(
    6,
    'T06-06 removed+active malformed identity denied',
    v_gate AND NOT v_has_perm AND v_students = 0
  );
END $$;

-- T06-07 — Malicious legacy role + executive permission
DO $$
DECLARE
  v_role uuid;
  v_perm uuid;
  v_has_exec boolean;
  v_rpc_denied boolean := false;
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
  DELETE FROM public.user_role ur
  USING public.role r
  WHERE ur.role_id = r.id
    AND r.organization_id = 'a0000000-0000-4000-8000-000000000001'
    AND r.code = 'm6_t06_malicious_exec';
  DELETE FROM public.role_permission rp
  USING public.role r
  WHERE rp.role_id = r.id
    AND r.code = 'm6_t06_malicious_exec';
  DELETE FROM public.role
  WHERE organization_id = 'a0000000-0000-4000-8000-000000000001'
    AND code = 'm6_t06_malicious_exec';
  INSERT INTO public.role (organization_id, code, status)
  VALUES ('a0000000-0000-4000-8000-000000000001', 'm6_t06_malicious_exec', 'active')
  RETURNING id INTO v_role;
  INSERT INTO public.user_role (organization_id, user_id, role_id, effective_from, status)
  VALUES (
    'a0000000-0000-4000-8000-000000000001',
    'a2000000-0000-4000-8000-000000000001',
    v_role,
    CURRENT_DATE,
    'active'
  );
  SELECT id INTO v_perm FROM public.permission WHERE code = 'report.executive.read' LIMIT 1;
  INSERT INTO public.role_permission (role_id, permission_id)
  VALUES (v_role, v_perm)
  ON CONFLICT DO NOTHING;
  PERFORM _m6_t06_as_auth('a2222222-2222-4222-8222-222222222222');
  SELECT public.has_permission('report.executive.read') INTO v_has_exec;
  BEGIN
    PERFORM public.get_executive_reporting_access();
    v_rpc_denied := false;
  EXCEPTION WHEN OTHERS THEN
    v_rpc_denied := SQLERRM LIKE '%permission_denied%';
  END;
  RESET ROLE;
  SET LOCAL ROLE postgres;
  DELETE FROM public.user_role WHERE user_id = 'a2000000-0000-4000-8000-000000000001' AND role_id = v_role;
  DELETE FROM public.role_permission WHERE role_id = v_role AND permission_id = v_perm;
  DELETE FROM public.role WHERE id = v_role;
  PERFORM _m6_t06_record(
    7,
    'T06-07 malicious executive graft denied',
    NOT v_has_exec AND v_rpc_denied
  );
END $$;

-- T06-08 — Service-only provisioning RPCs not executable by authenticated
DO $$
DECLARE
  v_blocked boolean := true;
BEGIN
  PERFORM _m6_t06_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.finalize_staff_provisioning(gen_random_uuid());
    v_blocked := false;
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  WHEN OTHERS THEN
    v_blocked := false;
  END;
  BEGIN
    PERFORM public.record_provisioning_auth_created(gen_random_uuid(), gen_random_uuid(), gen_random_uuid());
    v_blocked := v_blocked;
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  WHEN OTHERS THEN
    v_blocked := false;
  END;
  BEGIN
    PERFORM public.mark_provisioning_compensated(gen_random_uuid());
    v_blocked := v_blocked;
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  WHEN OTHERS THEN
    v_blocked := false;
  END;
  PERFORM _m6_t06_record(8, 'T06-08 service-only provisioning RPC EXECUTE denied', v_blocked);
END $$;

-- T06-09 — Internal lifecycle helper not executable by authenticated
DO $$
DECLARE
  v_blocked boolean := false;
BEGIN
  PERFORM _m6_t06_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public._m6_lifecycle_lock_target(
      'a0000000-0000-4000-8000-000000000001',
      'a2000000-0000-4000-8000-000000000001',
      false
    );
    v_blocked := false;
  EXCEPTION WHEN insufficient_privilege THEN
    v_blocked := true;
  END;
  PERFORM _m6_t06_record(9, 'T06-09 internal lifecycle helper EXECUTE denied', v_blocked);
END $$;

-- T06-10 — Direct membership_status and sensitive field DML denied
DO $$
DECLARE
  v_membership text;
  v_org uuid;
  v_auth uuid;
  v_blocked_mem boolean := false;
  v_blocked_org boolean := false;
  v_rows integer;
BEGIN
  PERFORM _m6_t06_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    UPDATE public.app_user SET membership_status = 'removed'
    WHERE id = 'a2000000-0000-4000-8000-000000000001';
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    v_blocked_mem := v_rows = 0;
  EXCEPTION WHEN OTHERS THEN
    v_blocked_mem := SQLERRM LIKE '%trusted administration%'
      OR SQLERRM LIKE '%permission denied%';
  END;
  BEGIN
    UPDATE public.app_user SET organization_id = 'b0000000-0000-4000-8000-000000000001'
    WHERE id = 'a2000000-0000-4000-8000-000000000001';
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    v_blocked_org := v_rows = 0;
  EXCEPTION WHEN OTHERS THEN
    v_blocked_org := SQLERRM LIKE '%trusted administration%'
      OR SQLERRM LIKE '%permission denied%';
  END;
  RESET ROLE;
  SET LOCAL ROLE postgres;
  SELECT membership_status, organization_id, auth_user_id
    INTO v_membership, v_org, v_auth
  FROM public.app_user WHERE id = 'a2000000-0000-4000-8000-000000000001';
  PERFORM _m6_t06_record(
    10,
    'T06-10 direct membership_status and org_id UPDATE denied',
    v_blocked_mem AND v_blocked_org
      AND v_membership = 'member'
      AND v_org = 'a0000000-0000-4000-8000-000000000001'
      AND v_auth IS NOT NULL
  );
END $$;

-- T06-11 — Primary Owner lifecycle invariant
DO $$
DECLARE
  v_failed_suspend boolean := false;
  v_failed_assign boolean := false;
  v_primary uuid;
  v_entitlement uuid;
BEGIN
  PERFORM _m6_t06_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.suspend_staff_member('a1000000-0000-4000-8000-000000000001');
    v_failed_suspend := false;
  EXCEPTION WHEN OTHERS THEN
    v_failed_suspend := SQLERRM LIKE '%target_is_primary_owner%';
  END;
  BEGIN
    PERFORM public.assign_canonical_staff_role('a1000000-0000-4000-8000-000000000001', 'teacher');
    v_failed_assign := false;
  EXCEPTION WHEN OTHERS THEN
    v_failed_assign := SQLERRM LIKE '%target_is_primary_owner%' OR SQLERRM LIKE '%invalid_role%';
  END;
  RESET ROLE;
  SET LOCAL ROLE postgres;
  SELECT primary_app_user_id INTO v_primary
  FROM public.organization_entitlement
  WHERE organization_id = 'a0000000-0000-4000-8000-000000000001';
  PERFORM _m6_t06_record(
    11,
    'T06-11 primary Owner lifecycle invariant',
    v_failed_suspend AND v_failed_assign AND v_primary = 'a1000000-0000-4000-8000-000000000001'
  );
END $$;

-- T06-12 — Seat entitlement cannot be bypassed; suspend does not free seat
DO $$
DECLARE
  v_org uuid := 'b0000000-0000-4000-8000-000000000001';
  v_removed uuid;
  v_limit integer;
  v_existing integer;
  v_i integer;
  v_seats_susp_before integer;
  v_seats_susp_after integer;
  v_failed boolean := false;
  v_membership text;
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
  UPDATE public.organization_entitlement SET staff_limit = 5 WHERE organization_id = v_org;
  v_removed := public.test_fixture_insert_app_user(
    v_org, 'm6-t06-seat-removed@olli.local', 'T06 Seat Removed', NULL, 'inactive', 'removed'
  );
  SELECT staff_limit INTO v_limit FROM public.organization_entitlement WHERE organization_id = v_org;
  SELECT public.count_member_staff_seats(v_org) INTO v_existing;
  FOR v_i IN 1..(v_limit - v_existing) LOOP
    PERFORM public.test_fixture_insert_app_user(
      v_org,
      'm6-t06-seat-fill-' || v_i || '@olli.local',
      'Seat Fill ' || v_i
    );
  END LOOP;
  PERFORM _m6_t06_as_auth('b1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.restore_removed_staff(v_removed, 'teacher');
    v_failed := false;
  EXCEPTION WHEN OTHERS THEN
    v_failed := SQLERRM LIKE '%staff_seat_limit_exceeded%';
  END;
  RESET ROLE;
  SET LOCAL ROLE postgres;
  SELECT membership_status INTO v_membership FROM public.app_user WHERE id = v_removed;
  SELECT public.count_member_staff_seats(v_org) INTO v_seats_susp_before;
  UPDATE public.app_user SET status = 'inactive' WHERE id = 'b2000000-0000-4000-8000-000000000001';
  SELECT public.count_member_staff_seats(v_org) INTO v_seats_susp_after;
  UPDATE public.app_user SET status = 'active' WHERE id = 'b2000000-0000-4000-8000-000000000001';
  DELETE FROM public.user_role WHERE user_id IN (
    SELECT id FROM public.app_user WHERE email LIKE 'm6-t06-seat-fill-%@olli.local'
  );
  DELETE FROM public.app_user WHERE email LIKE 'm6-t06-seat-fill-%@olli.local';
  DELETE FROM public.app_user WHERE id = v_removed;
  PERFORM _m6_t06_record(
    12,
    'T06-12 seat limit on restore; suspend keeps seat',
    v_failed AND v_membership = 'removed' AND v_seats_susp_before = v_seats_susp_after
  );
END $$;

-- T06-13 — Identity-label cross-org isolation
DO $$
DECLARE
  v_rows integer;
  v_label text;
BEGIN
  PERFORM _m6_t06_as_auth('a2222222-2222-4222-8222-222222222222');
  SELECT count(*), max(display_name) INTO v_rows, v_label
  FROM public.fetch_app_user_identity_labels(
    ARRAY['b2000000-0000-4000-8000-000000000001']::uuid[]
  );
  PERFORM _m6_t06_record(
    13,
    'T06-13 identity labels cross-org isolation',
    v_rows = 0 AND v_label IS NULL
  );
END $$;

-- T06-14 — Admin read-model authorization
DO $$
DECLARE
  v_denied boolean := false;
BEGIN
  PERFORM _m6_t06_as_auth('a2222222-2222-4222-8222-222222222222');
  BEGIN
    PERFORM public.fetch_center_account_administration();
    v_denied := false;
  EXCEPTION WHEN OTHERS THEN
    v_denied := SQLERRM LIKE '%permission_denied%';
  END;
  PERFORM _m6_t06_record(14, 'T06-14 fetch_center_account_administration non-owner denied', v_denied);
END $$;

-- T06-15 — Entitlement visibility
DO $$
DECLARE
  v_staff_count integer;
  v_owner_count integer;
BEGIN
  PERFORM _m6_t06_as_auth('a2222222-2222-4222-8222-222222222222');
  SELECT count(*) INTO v_staff_count FROM public.organization_entitlement;
  PERFORM _m6_t06_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_owner_count
  FROM public.organization_entitlement
  WHERE organization_id = 'a0000000-0000-4000-8000-000000000001';
  PERFORM _m6_t06_record(
    15,
    'T06-15 entitlement RLS staff zero owner one org',
    v_staff_count = 0 AND v_owner_count = 1
  );
END $$;

-- T06-16 — Representative M0–M5 cross-org regression (student)
DO $$
DECLARE
  v_count integer;
BEGIN
  PERFORM _m6_t06_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_count
  FROM public.student
  WHERE organization_id = 'b0000000-0000-4000-8000-000000000001';
  PERFORM _m6_t06_record(16, 'T06-16 cross-org student SELECT isolation', v_count = 0);
END $$;

-- T06-17 — Authenticated EXECUTE privilege catalog (M6 service/bootstrap/internal)
DO $$
DECLARE
  v_bad integer := 0;
BEGIN
  SELECT count(*) INTO v_bad
  FROM (
    VALUES
      ('public.set_primary_owner_for_organization(uuid, uuid)'),
      ('public.finalize_staff_provisioning(uuid)'),
      ('public.record_provisioning_auth_created(uuid, uuid, uuid)'),
      ('public.create_staff_membership_record(uuid, text, text, text)'),
      ('public.initialize_organization_access_foundation(uuid)'),
      ('public._m6_lifecycle_lock_target(uuid, uuid, boolean)'),
      ('public._m6_lifecycle_require_owner()'),
      ('public._m6_append_staff_lifecycle_event(uuid, uuid, uuid, text, text, text, text, text, text)'),
      ('public._m6_assign_canonical_staff_role_on_member(uuid, uuid, text)')
  ) AS f(sig)
  WHERE has_function_privilege('authenticated', f.sig, 'EXECUTE');
  PERFORM _m6_t06_record(17, 'T06-17 authenticated lacks service/internal EXECUTE', v_bad = 0);
END $$;

-- T06-18 — SECURITY DEFINER functions declare explicit search_path
DO $$
DECLARE
  v_unsafe integer;
BEGIN
  SELECT count(*) INTO v_unsafe
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.prosecdef
    AND p.proname NOT LIKE 'pg_%'
    AND NOT EXISTS (
      SELECT 1
      FROM unnest(COALESCE(p.proconfig, ARRAY[]::text[])) cfg
      WHERE cfg LIKE 'search_path=%'
    );
  PERFORM _m6_t06_record(
    18,
    'T06-18 SECURITY DEFINER functions have explicit search_path',
    v_unsafe = 0
  );
END $$;

DO $$
DECLARE
  v_fail integer;
  v_total integer;
  v_row record;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE result = 'FAIL')
  INTO v_total, v_fail
  FROM _m6_t06_results;
  FOR v_row IN
    SELECT test_no, test_name FROM _m6_t06_results WHERE result = 'FAIL' ORDER BY test_no
  LOOP
    RAISE NOTICE 'FAIL %: %', v_row.test_no, v_row.test_name;
  END LOOP;
  IF v_fail > 0 OR v_total <> 18 THEN
    RAISE EXCEPTION 'M6-T06 security isolation tests failed: % of % (expected 18)', v_fail, v_total;
  END IF;
  RAISE NOTICE 'M6-T06 security isolation tests: 18/18 PASS';
END $$;
