-- M6-T05 staff lifecycle, role change, identity gate, and historical integrity

CREATE TEMP TABLE IF NOT EXISTS _m6_t05_results (
  test_no integer PRIMARY KEY,
  test_name text NOT NULL,
  result text NOT NULL CHECK (result IN ('PASS', 'FAIL'))
);

GRANT ALL ON TABLE _m6_t05_results TO authenticated, anon;

-- Leftover T05 fixtures from a prior dirty run must not block uniqueness / FKs.
DO $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
  DELETE FROM public.staff_lifecycle_event
  WHERE target_app_user_id IN (SELECT id FROM public.app_user WHERE email LIKE 'm6-t05-%');
  DELETE FROM public.user_role
  WHERE user_id IN (SELECT id FROM public.app_user WHERE email LIKE 'm6-t05-%' AND email <> 'm6-t05-locked@olli.local');
  DELETE FROM public.payment
  WHERE created_by IN (SELECT id FROM public.app_user WHERE email LIKE 'm6-t05-%');
  DELETE FROM public.teacher
  WHERE user_id IN (SELECT id FROM public.app_user WHERE email LIKE 'm6-t05-%');
  DELETE FROM public.staff_provisioning_request
  WHERE normalized_email LIKE 'm6-t05-%' OR idempotency_key LIKE 'm6-t05-%';
  DELETE FROM public.organization_entitlement
  WHERE primary_app_user_id IN (SELECT id FROM public.app_user WHERE email LIKE 'm6-t05-%');
  DELETE FROM public.app_user
  WHERE email LIKE 'm6-t05-%' AND email <> 'm6-t05-locked@olli.local';
END $$;

CREATE OR REPLACE FUNCTION _m6_t05_record(test_no integer, test_name text, passed boolean)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO _m6_t05_results (test_no, test_name, result)
  VALUES (test_no, test_name, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END);
END;
$$;

CREATE OR REPLACE FUNCTION _m6_t05_as_auth(p_auth_id uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', p_auth_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_auth_id::text, 'role', 'authenticated')::text, true);
END;
$$;

CREATE OR REPLACE FUNCTION _m6_t05_count_seats()
RETURNS integer LANGUAGE plpgsql AS $$
DECLARE v_count integer;
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
  SELECT public.count_member_staff_seats('a0000000-0000-4000-8000-000000000001') INTO v_count;
  RETURN v_count;
END;
$$;

CREATE OR REPLACE FUNCTION _m6_t05_make_staff(
  p_email text,
  p_name text,
  p_role text DEFAULT 'teacher',
  p_status text DEFAULT 'active',
  p_membership text DEFAULT 'member',
  p_auth uuid DEFAULT NULL
)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
  v_id uuid;
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
  v_id := public.test_fixture_insert_app_user(
    v_org, p_email, p_name, p_auth, p_status, p_membership
  );
  IF p_membership = 'member' AND p_role IS NOT NULL THEN
    INSERT INTO public.user_role (organization_id, user_id, role_id, effective_from, status)
    SELECT v_org, v_id, r.id, CURRENT_DATE, 'active'
    FROM public.role r
    WHERE r.organization_id = v_org
      AND r.is_canonical_template
      AND r.canonical_code = p_role
    LIMIT 1;
  END IF;
  RETURN v_id;
END;
$$;

-- =============================================================================
-- 1–4 Owner protection
-- =============================================================================

DO $$
DECLARE v_failed boolean := false;
BEGIN
  PERFORM _m6_t05_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.suspend_staff_member('a1000000-0000-4000-8000-000000000001');
    v_failed := false;
  EXCEPTION WHEN OTHERS THEN
    v_failed := SQLERRM LIKE '%target_is_primary_owner%';
  END;
  PERFORM _m6_t05_record(1, 'cannot suspend primary Owner', v_failed);
END $$;

DO $$
DECLARE v_failed boolean := false;
BEGIN
  PERFORM _m6_t05_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.remove_staff_from_center('a1000000-0000-4000-8000-000000000001');
    v_failed := false;
  EXCEPTION WHEN OTHERS THEN
    v_failed := SQLERRM LIKE '%target_is_primary_owner%';
  END;
  PERFORM _m6_t05_record(2, 'cannot remove primary Owner', v_failed);
END $$;

DO $$
DECLARE v_failed boolean := false;
BEGIN
  PERFORM _m6_t05_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.assign_canonical_staff_role('a1000000-0000-4000-8000-000000000001', 'teacher');
    v_failed := false;
  EXCEPTION WHEN OTHERS THEN
    v_failed := SQLERRM LIKE '%target_is_primary_owner%';
  END;
  PERFORM _m6_t05_record(3, 'cannot assign primary Owner a staff role', v_failed);
END $$;

DO $$
DECLARE v_failed boolean := false;
BEGIN
  PERFORM _m6_t05_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.restore_removed_staff('a1000000-0000-4000-8000-000000000001', 'teacher');
    v_failed := false;
  EXCEPTION WHEN OTHERS THEN
    v_failed := SQLERRM LIKE '%target_is_primary_owner%';
  END;
  PERFORM _m6_t05_record(4, 'cannot restore primary Owner as staff', v_failed);
END $$;

-- =============================================================================
-- 5–11 Suspend
-- =============================================================================

DO $$
DECLARE
  v_id uuid;
  v_role_id uuid;
  v_role_status text;
  v_seats_before integer;
  v_seats_after integer;
  v_status text;
  v_membership text;
  v_events integer;
  v_ok boolean;
BEGIN
  v_id := _m6_t05_make_staff('m6-t05-suspend@olli.local', 'T05 Suspend', 'consultant');
  SELECT ur.id, ur.status INTO v_role_id, v_role_status
  FROM user_role ur WHERE ur.user_id = v_id AND ur.status = 'active' LIMIT 1;
  v_seats_before := _m6_t05_count_seats();

  PERFORM _m6_t05_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.suspend_staff_member(v_id);

  SELECT status, membership_status INTO v_status, v_membership
  FROM app_user WHERE id = v_id;
  v_seats_after := _m6_t05_count_seats();
  SELECT status INTO v_role_status FROM user_role WHERE id = v_role_id;
  SELECT count(*) INTO v_events FROM staff_lifecycle_event
  WHERE target_app_user_id = v_id AND event_type = 'suspended';

  PERFORM _m6_t05_record(5, 'suspend: active -> inactive member', v_status = 'inactive' AND v_membership = 'member');
  PERFORM _m6_t05_record(6, 'suspend: seat unchanged', v_seats_before = v_seats_after);
  PERFORM _m6_t05_record(7, 'suspend: role row remains active', v_role_status = 'active');
  PERFORM _m6_t05_record(8, 'suspend: lifecycle event written', v_events = 1);

  RESET ROLE;
  SET LOCAL ROLE postgres;
  UPDATE app_user SET auth_user_id = 'c1111111-1111-4111-8111-111111111111' WHERE id = v_id;
  PERFORM _m6_t05_as_auth('c1111111-1111-4111-8111-111111111111');
  SELECT public.current_app_user_id() IS NULL INTO v_ok;
  PERFORM _m6_t05_record(9, 'suspend: identity helper denied', v_ok);
  SELECT NOT public.has_permission('lead.read') INTO v_ok;
  PERFORM _m6_t05_record(10, 'suspend: permissions denied', v_ok);

  RESET ROLE;
  SET LOCAL ROLE postgres;
  UPDATE app_user SET auth_user_id = NULL WHERE id = v_id;
  PERFORM _m6_t05_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.suspend_staff_member(v_id);
  SELECT count(*) INTO v_events FROM staff_lifecycle_event
  WHERE target_app_user_id = v_id AND event_type = 'suspended';
  PERFORM _m6_t05_record(11, 'suspend retry is idempotent no-op', v_events = 1);
END $$;

-- =============================================================================
-- 12–16 Reactivate
-- =============================================================================

DO $$
DECLARE
  v_id uuid;
  v_role_id uuid;
  v_seats_before integer;
  v_seats_after integer;
  v_status text;
  v_membership text;
  v_role_status text;
  v_events integer;
BEGIN
  v_id := _m6_t05_make_staff('m6-t05-reactivate@olli.local', 'T05 Reactivate', 'teacher', 'inactive');
  SELECT ur.id INTO v_role_id FROM user_role ur WHERE ur.user_id = v_id AND ur.status = 'active' LIMIT 1;
  v_seats_before := _m6_t05_count_seats();

  PERFORM _m6_t05_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.reactivate_staff_member(v_id);

  SELECT status, membership_status INTO v_status, v_membership FROM app_user WHERE id = v_id;
  v_seats_after := _m6_t05_count_seats();
  SELECT status INTO v_role_status FROM user_role WHERE id = v_role_id;
  SELECT count(*) INTO v_events FROM staff_lifecycle_event
  WHERE target_app_user_id = v_id AND event_type = 'reactivated';

  PERFORM _m6_t05_record(12, 'reactivate: inactive -> active member', v_status = 'active' AND v_membership = 'member');
  PERFORM _m6_t05_record(13, 'reactivate: seat unchanged', v_seats_before = v_seats_after);
  PERFORM _m6_t05_record(14, 'reactivate: same role row preserved', v_role_status = 'active');
  PERFORM _m6_t05_record(15, 'reactivate: lifecycle event written', v_events = 1);

  PERFORM public.reactivate_staff_member(v_id);
  SELECT count(*) INTO v_events FROM staff_lifecycle_event
  WHERE target_app_user_id = v_id AND event_type = 'reactivated';
  PERFORM _m6_t05_record(16, 'reactivate retry is idempotent no-op', v_events = 1);
END $$;

-- =============================================================================
-- 17–24 Remove
-- =============================================================================

DO $$
DECLARE
  v_id uuid;
  v_auth uuid := 'a7770002-0000-4000-8000-000000000002';
  v_teacher uuid;
  v_payment uuid;
  v_seats_before integer;
  v_seats_after integer;
  v_status text;
  v_membership text;
  v_auth_after uuid;
  v_active_roles integer;
  v_ended_roles integer;
  v_teacher_status text;
  v_teacher_user uuid;
  v_payment_by uuid;
  v_events integer;
  v_email text;
BEGIN
  v_id := _m6_t05_make_staff('m6-t05-remove@olli.local', 'T05 Remove', 'teacher', 'active', 'member');
  UPDATE app_user SET auth_user_id = 'c1111111-1111-4111-8111-111111111111' WHERE id = v_id;
  v_auth := 'c1111111-1111-4111-8111-111111111111';

  RESET ROLE;
  SET LOCAL ROLE postgres;
  INSERT INTO teacher (organization_id, user_id, given_name, family_name, status)
  VALUES ('a0000000-0000-4000-8000-000000000001', v_id, 'Hist', 'Teacher', 'active')
  RETURNING id INTO v_teacher;

  INSERT INTO payment (organization_id, guardian_id, amount, created_by)
  VALUES (
    'a0000000-0000-4000-8000-000000000001',
    'a5200000-0000-4000-8000-000000000001',
    25000,
    v_id
  )
  RETURNING id INTO v_payment;

  SELECT public.count_member_staff_seats('a0000000-0000-4000-8000-000000000001') INTO v_seats_before;

  PERFORM _m6_t05_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.remove_staff_from_center(v_id);

  SELECT status, membership_status, auth_user_id, email
    INTO v_status, v_membership, v_auth_after, v_email
  FROM app_user WHERE id = v_id;
  v_seats_after := _m6_t05_count_seats();
  SELECT count(*) INTO v_active_roles FROM user_role
  WHERE user_id = v_id AND status = 'active';
  SELECT count(*) INTO v_ended_roles FROM user_role
  WHERE user_id = v_id AND status = 'ended';
  SELECT status, user_id INTO v_teacher_status, v_teacher_user FROM teacher WHERE id = v_teacher;
  SELECT created_by INTO v_payment_by FROM payment WHERE id = v_payment;
  SELECT count(*) INTO v_events FROM staff_lifecycle_event
  WHERE target_app_user_id = v_id AND event_type = 'removed';

  PERFORM _m6_t05_record(17, 'remove: member -> removed inactive', v_status = 'inactive' AND v_membership = 'removed');
  PERFORM _m6_t05_record(18, 'remove: seat released by one', v_seats_after = v_seats_before - 1);
  PERFORM _m6_t05_record(19, 'remove: no active canonical role', v_active_roles = 0 AND v_ended_roles >= 1);
  PERFORM _m6_t05_record(20, 'remove: app_user and auth link preserved', v_email = 'm6-t05-remove@olli.local' AND v_auth_after = v_auth);
  PERFORM _m6_t05_record(21, 'remove: teacher row untouched', v_teacher_status = 'active' AND v_teacher_user = v_id);
  PERFORM _m6_t05_record(22, 'remove: finance created_by preserved', v_payment_by = v_id);
  PERFORM _m6_t05_record(23, 'remove: lifecycle event written', v_events = 1);

  PERFORM public.remove_staff_from_center(v_id);
  SELECT count(*) INTO v_events FROM staff_lifecycle_event
  WHERE target_app_user_id = v_id AND event_type = 'removed';
  PERFORM _m6_t05_record(24, 'remove retry is idempotent no-op', v_events = 1);

  RESET ROLE;
  SET LOCAL ROLE postgres;
  UPDATE app_user SET auth_user_id = NULL WHERE id = v_id;
END $$;

-- =============================================================================
-- 25–31 Restore
-- =============================================================================

DO $$
DECLARE
  v_id uuid;
  v_auth uuid := 'c1111111-1111-4111-8111-111111111111';
  v_seats_before integer;
  v_seats_after integer;
  v_status text;
  v_membership text;
  v_auth_after uuid;
  v_role text;
  v_active_roles integer;
  v_events integer;
  v_same boolean;
BEGIN
  v_id := _m6_t05_make_staff(
    'm6-t05-restore@olli.local', 'T05 Restore', 'consultant', 'inactive', 'removed'
  );
  UPDATE app_user SET auth_user_id = v_auth WHERE id = v_id;
  v_seats_before := _m6_t05_count_seats();

  PERFORM _m6_t05_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.restore_removed_staff(v_id, 'accountant');

  SELECT status, membership_status, auth_user_id
    INTO v_status, v_membership, v_auth_after
  FROM app_user WHERE id = v_id;
  v_seats_after := _m6_t05_count_seats();
  SELECT r.canonical_code INTO v_role
  FROM user_role ur
  JOIN role r ON r.id = ur.role_id
  WHERE ur.user_id = v_id AND ur.status = 'active' AND r.is_canonical_template
  LIMIT 1;
  SELECT count(*) INTO v_active_roles FROM user_role ur
  JOIN role r ON r.id = ur.role_id
  WHERE ur.user_id = v_id AND ur.status = 'active' AND r.is_canonical_template;
  SELECT count(*) INTO v_events FROM staff_lifecycle_event
  WHERE target_app_user_id = v_id AND event_type = 'restored';
  v_same := EXISTS (SELECT 1 FROM app_user WHERE id = v_id AND email = 'm6-t05-restore@olli.local');

  PERFORM _m6_t05_record(25, 'restore: same app_user id and auth', v_same AND v_auth_after = v_auth);
  PERFORM _m6_t05_record(26, 'restore: member + active', v_status = 'active' AND v_membership = 'member');
  PERFORM _m6_t05_record(27, 'restore: seat +1', v_seats_after = v_seats_before + 1);
  PERFORM _m6_t05_record(28, 'restore: one assigned staff role', v_role = 'accountant' AND v_active_roles = 1);
  PERFORM _m6_t05_record(29, 'restore: no duplicate identity', (
    SELECT count(*) FROM app_user
    WHERE organization_id = 'a0000000-0000-4000-8000-000000000001'
      AND email = 'm6-t05-restore@olli.local'
  ) = 1);

  PERFORM public.restore_removed_staff(v_id, 'accountant');
  SELECT count(*) INTO v_events FROM staff_lifecycle_event
  WHERE target_app_user_id = v_id AND event_type = 'restored';
  PERFORM _m6_t05_record(30, 'restore same-state retry is idempotent', v_events = 1);
END $$;

DO $$
DECLARE v_failed boolean := false; v_id uuid;
BEGIN
  SELECT id INTO v_id FROM app_user WHERE email = 'm6-t05-restore@olli.local';
  PERFORM _m6_t05_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.restore_removed_staff(v_id, 'teacher');
    v_failed := false;
  EXCEPTION WHEN OTHERS THEN
    v_failed := SQLERRM LIKE '%lifecycle_conflict%';
  END;
  PERFORM _m6_t05_record(31, 'restore different role after restore is conflict', v_failed);
END $$;

-- =============================================================================
-- 32–36 Last-seat restore + failed restore remains removed
-- =============================================================================

DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_limit integer;
  v_used integer;
  v_need integer;
  v_i integer;
  v_a uuid;
  v_b uuid;
  v_ok_a boolean := false;
  v_fail_b boolean := false;
  v_status text;
  v_membership text;
  v_roles integer;
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
  SELECT staff_limit INTO v_limit FROM organization_entitlement WHERE organization_id = v_org;
  SELECT public.count_member_staff_seats(v_org) INTO v_used;
  v_need := v_limit - v_used;
  IF v_need < 1 THEN
    UPDATE organization_entitlement SET staff_limit = v_used + 1 WHERE organization_id = v_org;
    v_need := 1;
    v_limit := v_used + 1;
  END IF;
  FOR v_i IN 1..(v_need - 1) LOOP
    PERFORM public.create_staff_membership_record(
      v_org,
      'm6-t05-fill-' || v_i || '@olli.local',
      'Fill ' || v_i
    );
  END LOOP;

  v_a := _m6_t05_make_staff('m6-t05-last-a@olli.local', 'Last A', NULL, 'inactive', 'removed');
  v_b := _m6_t05_make_staff('m6-t05-last-b@olli.local', 'Last B', NULL, 'inactive', 'removed');

  PERFORM _m6_t05_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.restore_removed_staff(v_a, 'teacher');
    v_ok_a := true;
  EXCEPTION WHEN OTHERS THEN
    v_ok_a := false;
  END;
  BEGIN
    PERFORM public.restore_removed_staff(v_b, 'teacher');
    v_fail_b := false;
  EXCEPTION WHEN OTHERS THEN
    v_fail_b := SQLERRM LIKE '%staff_seat_limit_exceeded%';
  END;

  SELECT status, membership_status INTO v_status, v_membership FROM app_user WHERE id = v_b;
  SELECT count(*) INTO v_roles FROM user_role WHERE user_id = v_b AND status = 'active';

  PERFORM _m6_t05_record(32, 'last-seat restore: one succeeds', v_ok_a);
  PERFORM _m6_t05_record(33, 'last-seat restore: other seat-limit exceeded', v_fail_b);
  PERFORM _m6_t05_record(
    34,
    'failed restore leaves target fully removed',
    v_status = 'inactive' AND v_membership = 'removed' AND v_roles = 0
  );

  RESET ROLE;
  SET LOCAL ROLE postgres;
  DELETE FROM user_role WHERE user_id = v_a;
  UPDATE app_user SET status = 'inactive', membership_status = 'removed' WHERE id = v_a;
  DELETE FROM app_user WHERE email LIKE 'm6-t05-fill-%@olli.local';
  UPDATE organization_entitlement SET staff_limit = 24 WHERE organization_id = v_org;
END $$;

-- =============================================================================
-- 35–42 Role change
-- =============================================================================

DO $$
DECLARE
  v_id uuid;
  v_old uuid;
  v_new_count integer;
  v_ended integer;
  v_active integer;
  v_code text;
BEGIN
  v_id := _m6_t05_make_staff('m6-t05-role@olli.local', 'T05 Role', 'consultant');
  SELECT ur.id INTO v_old FROM user_role ur WHERE ur.user_id = v_id AND ur.status = 'active' LIMIT 1;

  PERFORM _m6_t05_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.assign_canonical_staff_role(v_id, 'teacher');

  SELECT count(*) INTO v_ended FROM user_role WHERE id = v_old AND status = 'ended';
  SELECT count(*) INTO v_active FROM user_role ur
  JOIN role r ON r.id = ur.role_id
  WHERE ur.user_id = v_id AND ur.status = 'active' AND r.is_canonical_template;
  SELECT r.canonical_code INTO v_code
  FROM user_role ur
  JOIN role r ON r.id = ur.role_id
  WHERE ur.user_id = v_id AND ur.status = 'active' AND r.is_canonical_template
  LIMIT 1;

  PERFORM _m6_t05_record(35, 'role change: previous row ended and preserved', v_ended = 1);
  PERFORM _m6_t05_record(36, 'role change: exactly one active canonical role', v_active = 1 AND v_code = 'teacher');

  SELECT count(*) INTO v_new_count FROM user_role WHERE user_id = v_id;
  PERFORM public.assign_canonical_staff_role(v_id, 'teacher');
  PERFORM _m6_t05_record(
    37,
    'same-role retry creates no new user_role row',
    (SELECT count(*) FROM user_role WHERE user_id = v_id) = v_new_count
  );
END $$;

DO $$
DECLARE v_id uuid; v_code text;
BEGIN
  v_id := _m6_t05_make_staff('m6-t05-role-susp@olli.local', 'T05 Role Susp', 'accountant', 'inactive');
  PERFORM _m6_t05_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.assign_canonical_staff_role(v_id, 'consultant');
  SELECT r.canonical_code INTO v_code
  FROM user_role ur
  JOIN role r ON r.id = ur.role_id
  WHERE ur.user_id = v_id AND ur.status = 'active' AND r.is_canonical_template
  LIMIT 1;
  PERFORM _m6_t05_record(38, 'suspended member may change role', v_code = 'consultant');
END $$;

DO $$
DECLARE v_failed boolean := false; v_id uuid;
BEGIN
  v_id := _m6_t05_make_staff('m6-t05-role-rem@olli.local', 'T05 Role Rem', NULL, 'inactive', 'removed');
  PERFORM _m6_t05_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.assign_canonical_staff_role(v_id, 'teacher');
    v_failed := false;
  EXCEPTION WHEN OTHERS THEN
    v_failed := SQLERRM LIKE '%target_already_removed%';
  END;
  PERFORM _m6_t05_record(39, 'removed target cannot change role', v_failed);
END $$;

DO $$
DECLARE v_failed boolean := false; v_id uuid;
BEGIN
  v_id := _m6_t05_make_staff('m6-t05-role-lock@olli.local', 'T05 Role Lock', 'teacher', 'locked');
  PERFORM _m6_t05_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.assign_canonical_staff_role(v_id, 'consultant');
    v_failed := false;
  EXCEPTION WHEN OTHERS THEN
    v_failed := SQLERRM LIKE '%lifecycle_conflict%';
  END;
  PERFORM _m6_t05_record(40, 'locked target cannot change role', v_failed);
END $$;

DO $$
DECLARE v_failed boolean := false; v_id uuid;
BEGIN
  v_id := _m6_t05_make_staff('m6-t05-role-cm@olli.local', 'T05 Role CM', 'teacher');
  PERFORM _m6_t05_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.assign_canonical_staff_role(v_id, 'center_manager');
    v_failed := false;
  EXCEPTION WHEN OTHERS THEN
    v_failed := SQLERRM LIKE '%invalid_role%';
  END;
  PERFORM _m6_t05_record(41, 'center_manager rejected for staff', v_failed);
END $$;

-- =============================================================================
-- 42–48 Security
-- =============================================================================

DO $$
DECLARE v_failed boolean := false; v_id uuid;
BEGIN
  v_id := _m6_t05_make_staff('m6-t05-sec-staff@olli.local', 'T05 Sec Staff', 'teacher');
  PERFORM _m6_t05_as_auth('a2222222-2222-4222-8222-222222222222');
  BEGIN
    PERFORM public.suspend_staff_member(v_id);
    v_failed := false;
  EXCEPTION WHEN OTHERS THEN
    v_failed := SQLERRM LIKE '%not_primary_owner%';
  END;
  PERFORM _m6_t05_record(42, 'non-Owner lifecycle RPC denied', v_failed);
END $$;

DO $$
DECLARE
  v_failed boolean := false;
  v_status text;
BEGIN
  PERFORM _m6_t05_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.suspend_staff_member('b2000000-0000-4000-8000-000000000001');
    v_failed := false;
  EXCEPTION WHEN OTHERS THEN
    v_failed := SQLERRM LIKE '%target_not_found%';
  END;
  RESET ROLE;
  SET LOCAL ROLE postgres;
  SELECT status INTO v_status FROM app_user WHERE id = 'b2000000-0000-4000-8000-000000000001';
  PERFORM _m6_t05_record(43, 'cross-org UUID denied without leak', v_failed AND v_status = 'active');
END $$;

DO $$
DECLARE
  v_blocked boolean := false;
  v_rows integer := 0;
  v_status text;
BEGIN
  PERFORM _m6_t05_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    UPDATE app_user SET status = 'inactive'
    WHERE id = 'a2000000-0000-4000-8000-000000000001';
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    v_blocked := false;
  EXCEPTION WHEN OTHERS THEN
    v_blocked := SQLERRM LIKE '%trusted administration%' OR SQLERRM LIKE '%permission%';
  END;
  RESET ROLE;
  SET LOCAL ROLE postgres;
  SELECT status INTO v_status FROM app_user WHERE id = 'a2000000-0000-4000-8000-000000000001';
  PERFORM _m6_t05_record(
    44,
    'authenticated direct status UPDATE denied',
    v_status = 'active' AND (v_blocked OR v_rows = 0)
  );
END $$;

DO $$
DECLARE v_blocked boolean := false;
BEGIN
  PERFORM _m6_t05_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    INSERT INTO user_role (organization_id, user_id, role_id, effective_from, status)
    SELECT 'a0000000-0000-4000-8000-000000000001',
           'a2000000-0000-4000-8000-000000000001',
           r.id, CURRENT_DATE, 'active'
    FROM role r
    WHERE r.organization_id = 'a0000000-0000-4000-8000-000000000001'
      AND r.canonical_code = 'accountant'
    LIMIT 1;
    v_blocked := false;
  EXCEPTION WHEN insufficient_privilege THEN
    v_blocked := true;
  WHEN OTHERS THEN
    v_blocked := true;
  END;
  PERFORM _m6_t05_record(45, 'authenticated direct user_role write denied', v_blocked);
END $$;

DO $$
DECLARE v_blocked boolean := false;
BEGIN
  PERFORM _m6_t05_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    INSERT INTO staff_lifecycle_event (
      organization_id, target_app_user_id, actor_app_user_id,
      event_type, from_status, to_status, from_membership, to_membership
    ) VALUES (
      'a0000000-0000-4000-8000-000000000001',
      'a2000000-0000-4000-8000-000000000001',
      'a1000000-0000-4000-8000-000000000001',
      'suspended', 'active', 'inactive', 'member', 'member'
    );
    v_blocked := false;
  EXCEPTION WHEN insufficient_privilege THEN
    v_blocked := true;
  WHEN OTHERS THEN
    v_blocked := true;
  END;
  PERFORM _m6_t05_record(46, 'authenticated direct lifecycle_event insert denied', v_blocked);
END $$;

DO $$
DECLARE
  v_id uuid;
  v_auth uuid := 'c1111111-1111-4111-8111-111111111111';
  v_denied boolean;
BEGIN
  v_id := _m6_t05_make_staff(
    'm6-t05-malformed@olli.local', 'T05 Malformed', NULL, 'active', 'removed'
  );
  RESET ROLE;
  SET LOCAL ROLE postgres;
  UPDATE app_user SET auth_user_id = NULL
  WHERE auth_user_id = v_auth AND id IS DISTINCT FROM v_id;
  UPDATE app_user SET auth_user_id = v_auth WHERE id = v_id;
  PERFORM _m6_t05_as_auth(v_auth);
  SELECT public.current_app_user_id() IS NULL AND NOT public.is_active_app_user()
    INTO v_denied;
  PERFORM _m6_t05_record(47, 'removed+active malformed identity cannot resolve', v_denied);
END $$;

-- =============================================================================
-- 48–52 Locked + removed-target errors + T03 removed email
-- =============================================================================

DO $$
DECLARE v_failed boolean := false; v_id uuid;
BEGIN
  v_id := _m6_t05_make_staff('m6-t05-lock-susp@olli.local', 'T05 Lock Susp', 'teacher', 'locked');
  PERFORM _m6_t05_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.suspend_staff_member(v_id);
    v_failed := false;
  EXCEPTION WHEN OTHERS THEN
    v_failed := SQLERRM LIKE '%lifecycle_conflict%';
  END;
  PERFORM _m6_t05_record(48, 'locked member cannot be suspended', v_failed);
END $$;

DO $$
DECLARE v_failed boolean := false; v_id uuid;
BEGIN
  SELECT id INTO v_id FROM app_user WHERE email = 'm6-t05-remove@olli.local';
  PERFORM _m6_t05_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.suspend_staff_member(v_id);
    v_failed := false;
  EXCEPTION WHEN OTHERS THEN
    v_failed := SQLERRM LIKE '%target_already_removed%';
  END;
  PERFORM _m6_t05_record(49, 'suspend of removed target rejected', v_failed);
END $$;

DO $$
DECLARE v_failed boolean := false;
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
  DELETE FROM staff_provisioning_request
  WHERE normalized_email = 'm6-t05-remove@olli.local'
     OR idempotency_key LIKE 'm6-t05-removed-email%';
  PERFORM _m6_t05_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.begin_staff_provisioning(
      'm6-t05-removed-email-' || gen_random_uuid()::text,
      'm6-t05-remove@olli.local',
      'Should Restore',
      'teacher'
    );
    v_failed := false;
  EXCEPTION WHEN OTHERS THEN
    v_failed := SQLERRM LIKE '%removed_member_exists%';
  END;
  PERFORM _m6_t05_record(50, 'T03 provisioning of removed email is removed_member_exists', v_failed);
END $$;

-- =============================================================================
-- 51–54 Seat anti-abuse + role vs remove invariant
-- =============================================================================

DO $$
DECLARE
  v_id uuid;
  v_before integer;
  v_after_susp integer;
  v_after_rem integer;
  v_after_res integer;
  v_create_rejected boolean := false;
BEGIN
  v_id := _m6_t05_make_staff('m6-t05-seats@olli.local', 'T05 Seats', 'teacher');
  v_before := _m6_t05_count_seats();

  PERFORM _m6_t05_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.suspend_staff_member(v_id);
  v_after_susp := _m6_t05_count_seats();

  RESET ROLE;
  SET LOCAL ROLE postgres;
  BEGIN
    PERFORM public.create_staff_membership_record(
      'a0000000-0000-4000-8000-000000000001',
      'm6-t05-should-fail-limit@olli.local',
      'Should Fail If Full'
    );
  EXCEPTION WHEN OTHERS THEN
    v_create_rejected := SQLERRM LIKE '%staff_seat_limit_exceeded%';
  END;

  PERFORM _m6_t05_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.remove_staff_from_center(v_id);
  v_after_rem := _m6_t05_count_seats();
  PERFORM public.restore_removed_staff(v_id, 'teacher');
  v_after_res := _m6_t05_count_seats();

  PERFORM _m6_t05_record(51, 'suspend does not free a seat', v_after_susp = v_before);
  PERFORM _m6_t05_record(52, 'remove releases a seat and restore reacquires', v_after_rem = v_before - 1 AND v_after_res = v_before);
END $$;

DO $$
DECLARE
  v_id uuid;
  v_active integer;
  v_membership text;
BEGIN
  v_id := _m6_t05_make_staff('m6-t05-role-vs-remove@olli.local', 'T05 RoleVsRemove', 'consultant');
  PERFORM _m6_t05_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.assign_canonical_staff_role(v_id, 'teacher');
  PERFORM public.remove_staff_from_center(v_id);
  SELECT membership_status INTO v_membership FROM app_user WHERE id = v_id;
  SELECT count(*) INTO v_active FROM user_role ur
  JOIN role r ON r.id = ur.role_id
  WHERE ur.user_id = v_id AND ur.status = 'active' AND r.is_canonical_template;
  PERFORM _m6_t05_record(
    53,
    'role change then remove never leaves removed+active role',
    v_membership = 'removed' AND v_active = 0
  );
END $$;

DO $$
DECLARE
  v_present boolean;
BEGIN
  PERFORM _m6_t05_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT EXISTS (
    SELECT 1
    FROM jsonb_array_elements(public.fetch_center_account_administration()->'removed_staff') elem
    WHERE elem->>'email' = 'm6-t05-remove@olli.local'
  ) INTO v_present;
  PERFORM _m6_t05_record(54, 'removed staff appear in read-model removed_staff', v_present);
END $$;

DO $$
DECLARE
  v_id uuid;
  v_failed boolean := false;
  v_membership text;
  v_status text;
BEGIN
  v_id := _m6_t05_make_staff('m6-t05-restore-cm@olli.local', 'T05 Restore CM', NULL, 'inactive', 'removed');
  PERFORM _m6_t05_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.restore_removed_staff(v_id, 'center_manager');
    v_failed := false;
  EXCEPTION WHEN OTHERS THEN
    v_failed := SQLERRM LIKE '%invalid_role%';
  END;
  SELECT status, membership_status INTO v_status, v_membership FROM app_user WHERE id = v_id;
  PERFORM _m6_t05_record(
    55,
    'restore rejects center_manager and leaves removed',
    v_failed AND v_status = 'inactive' AND v_membership = 'removed'
  );
END $$;

DO $$
DECLARE
  v_org uuid := gen_random_uuid();
  v_owner uuid := gen_random_uuid();
  v_staff uuid;
  v_rejected boolean := false;
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
  INSERT INTO organization (id, name) VALUES (v_org, 'M6 T05 Seat Anti-Abuse');
  INSERT INTO app_user (id, organization_id, email, display_name, status, membership_status)
  VALUES (v_owner, v_org, 'm6-t05-abuse-owner@olli.local', 'Abuse Owner', 'active', 'member');
  PERFORM public.set_primary_owner_for_organization(v_org, v_owner);
  UPDATE organization_entitlement SET staff_limit = 1 WHERE organization_id = v_org;
  v_staff := public.create_staff_membership_record(v_org, 'm6-t05-abuse-staff@olli.local', 'Abuse Staff');
  INSERT INTO user_role (organization_id, user_id, role_id, effective_from, status)
  SELECT v_org, v_staff, r.id, CURRENT_DATE, 'active'
  FROM role r WHERE r.organization_id = v_org AND r.canonical_code = 'teacher' LIMIT 1;
  UPDATE app_user SET status = 'inactive' WHERE id = v_staff;
  BEGIN
    PERFORM public.create_staff_membership_record(v_org, 'm6-t05-abuse-extra@olli.local', 'Extra');
  EXCEPTION WHEN OTHERS THEN
    v_rejected := SQLERRM LIKE '%staff_seat_limit_exceeded%';
  END;
  PERFORM _m6_t05_record(
    56,
    'suspend/create cannot bypass staff_limit',
    v_rejected AND (SELECT membership_status FROM app_user WHERE id = v_staff) = 'member'
  );

  RESET ROLE;
  SET LOCAL ROLE postgres;
  DELETE FROM public.user_role WHERE organization_id = v_org;
  DELETE FROM public.organization_entitlement WHERE organization_id = v_org;
  DELETE FROM public.app_user WHERE organization_id = v_org;
END $$;

-- Release org A seats so later Playwright provisioning still has headroom.
-- Keep the locked seed fixture used by T05 E2E.
DO $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
  DELETE FROM public.staff_lifecycle_event
  WHERE target_app_user_id IN (
    SELECT id FROM public.app_user
    WHERE email LIKE 'm6-t05-%' AND email <> 'm6-t05-locked@olli.local'
  );
  DELETE FROM public.staff_provisioning_request
  WHERE normalized_email LIKE 'm6-t05-%' OR idempotency_key LIKE 'm6-t05-%';
  DELETE FROM public.payment
  WHERE created_by IN (
    SELECT id FROM public.app_user
    WHERE email LIKE 'm6-t05-%' AND email <> 'm6-t05-locked@olli.local'
  );
  DELETE FROM public.teacher
  WHERE user_id IN (
    SELECT id FROM public.app_user
    WHERE email LIKE 'm6-t05-%' AND email <> 'm6-t05-locked@olli.local'
  );
  DELETE FROM public.user_role
  WHERE user_id IN (
    SELECT id FROM public.app_user
    WHERE email LIKE 'm6-t05-%' AND email <> 'm6-t05-locked@olli.local'
  );
  DELETE FROM public.organization_entitlement
  WHERE primary_app_user_id IN (
    SELECT id FROM public.app_user WHERE email LIKE 'm6-t05-%'
  );
  DELETE FROM public.app_user
  WHERE email LIKE 'm6-t05-%' AND email <> 'm6-t05-locked@olli.local';
  UPDATE public.organization_entitlement
  SET staff_limit = 24
  WHERE organization_id = 'a0000000-0000-4000-8000-000000000001';
END $$;

DO $$
DECLARE
  v_fail integer;
  v_row record;
BEGIN
  SELECT count(*) INTO v_fail FROM _m6_t05_results WHERE result = 'FAIL';
  FOR v_row IN SELECT test_no, test_name FROM _m6_t05_results WHERE result = 'FAIL' ORDER BY test_no
  LOOP
    RAISE NOTICE 'FAIL %: %', v_row.test_no, v_row.test_name;
  END LOOP;
  IF v_fail > 0 THEN
    RAISE EXCEPTION 'M6-T05 staff lifecycle tests failed: % failing', v_fail;
  END IF;
  RAISE NOTICE 'M6-T05 staff lifecycle tests: 56/56 PASS';
END $$;
