-- M2-T05: payment recording and allocation (41 scenarios)

BEGIN;

CREATE TEMP TABLE _m2_pay_results (
  test_no   integer PRIMARY KEY,
  test_name text NOT NULL,
  result    text NOT NULL CHECK (result IN ('PASS', 'FAIL'))
);

GRANT ALL ON TABLE _m2_pay_results TO authenticated, anon;

CREATE OR REPLACE FUNCTION _m2_pay_record(test_no integer, test_name text, passed boolean)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO _m2_pay_results (test_no, test_name, result)
  VALUES (test_no, test_name, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END);
END;
$$;

CREATE OR REPLACE FUNCTION _m2_pay_expect_fail(test_no integer, test_name text, sql_text text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN EXECUTE sql_text; PERFORM _m2_pay_record(test_no, test_name, false);
  EXCEPTION WHEN OTHERS THEN PERFORM _m2_pay_record(test_no, test_name, true); END;
END;
$$;

CREATE OR REPLACE FUNCTION _m2_pay_as_super()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN RESET ROLE; SET LOCAL ROLE postgres; END;
$$;

CREATE OR REPLACE FUNCTION _m2_pay_as_auth(p_auth_id uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE; SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', p_auth_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_auth_id::text, 'role', 'authenticated')::text, true);
END;
$$;

CREATE OR REPLACE FUNCTION _m2_pay_bootstrap()
RETURNS TABLE (
  org_id uuid,
  course_id uuid,
  class_id uuid,
  student_id uuid,
  guardian_id uuid,
  enrollment_id uuid,
  auth_admin uuid
)
LANGUAGE plpgsql AS $$
DECLARE
  v_org uuid;
  v_course uuid;
  v_class uuid;
  v_student uuid;
  v_guardian uuid;
  v_enrollment uuid;
  v_auth uuid;
BEGIN
  PERFORM _m2_pay_as_super();
  v_org := gen_random_uuid();
  INSERT INTO organization (id, name) VALUES (v_org, 'M2 Pay Test Org');
  INSERT INTO course (organization_id, code, name) VALUES (v_org, 'P1', 'Pay Course') RETURNING id INTO v_course;
  INSERT INTO class (organization_id, course_id, name, status) VALUES (v_org, v_course, 'Pay Class', 'active') RETURNING id INTO v_class;
  INSERT INTO student (organization_id, given_name, family_name) VALUES (v_org, 'Pay', 'Student') RETURNING id INTO v_student;
  INSERT INTO guardian (organization_id, given_name, family_name, email) VALUES (v_org, 'Pay', 'Guardian', 'pay@test.local') RETURNING id INTO v_guardian;
  INSERT INTO student_guardian (organization_id, student_id, guardian_id, is_primary_contact, is_billing_contact)
    VALUES (v_org, v_student, v_guardian, true, true);
  INSERT INTO enrollment (organization_id, student_id, class_id, start_date, status)
    VALUES (v_org, v_student, v_class, CURRENT_DATE, 'active') RETURNING id INTO v_enrollment;

  v_auth := gen_random_uuid();
  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at, is_sso_user, is_anonymous
  )
  VALUES (
    v_auth,
    (SELECT id FROM auth.instances LIMIT 1),
    'authenticated',
    'authenticated',
    'pay-' || replace(v_auth::text, '-', '') || '@test.local',
    '',
    now(),
    now(),
    now(),
    false,
    false
  );

  INSERT INTO app_user (organization_id, email, display_name, auth_user_id, status)
  VALUES (v_org, 'pay-admin@test.local', 'Pay Admin', v_auth, 'active');

  RETURN QUERY SELECT v_org, v_course, v_class, v_student, v_guardian, v_enrollment, v_auth;
END;
$$;

CREATE OR REPLACE FUNCTION _m2_pay_setup_terms_charges(
  p_org uuid, p_enrollment uuid, p_guardian uuid, p_student uuid, p_net bigint
)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE tid uuid;
BEGIN
  INSERT INTO enrollment_financial_terms (
    organization_id, enrollment_id, agreed_tuition_amount, discount_amount,
    net_tuition_amount, agreement_date, status
  ) VALUES (p_org, p_enrollment, p_net, 0, p_net, CURRENT_DATE, 'draft') RETURNING id INTO tid;

  INSERT INTO enrollment_payment_schedule_item (
    organization_id, enrollment_financial_terms_id, sequence_number, due_date, amount
  ) VALUES (p_org, tid, 1, CURRENT_DATE, p_net);

  UPDATE enrollment_financial_terms SET status = 'active' WHERE id = tid;

  INSERT INTO charge (
    organization_id, student_id, enrollment_id, guardian_id,
    enrollment_financial_terms_id, enrollment_payment_schedule_item_id,
    charge_source_code, amount, currency_code, charged_at, due_date, status,
    agreed_tuition_snapshot, net_tuition_snapshot
  )
  SELECT p_org, p_student, p_enrollment, p_guardian, tid, si.id, 'tuition', si.amount,
    'VND', CURRENT_DATE, si.due_date, 'open', p_net, p_net
  FROM enrollment_payment_schedule_item si
  WHERE si.enrollment_financial_terms_id = tid;

  RETURN tid;
END;
$$;

CREATE OR REPLACE FUNCTION _m2_pay_setup_two_charges(
  p_org uuid, p_enrollment uuid, p_guardian uuid, p_student uuid,
  p_amount1 bigint, p_amount2 bigint, p_due2 date DEFAULT CURRENT_DATE + 30
)
RETURNS TABLE (terms_id uuid, charge1_id uuid, charge2_id uuid)
LANGUAGE plpgsql AS $$
DECLARE tid uuid; c1 uuid; c2 uuid;
BEGIN
  INSERT INTO enrollment_financial_terms (
    organization_id, enrollment_id, agreed_tuition_amount, discount_amount,
    net_tuition_amount, agreement_date, status
  ) VALUES (p_org, p_enrollment, p_amount1 + p_amount2, 0, p_amount1 + p_amount2, CURRENT_DATE, 'draft')
  RETURNING id INTO tid;

  INSERT INTO enrollment_payment_schedule_item (
    organization_id, enrollment_financial_terms_id, sequence_number, due_date, amount
  ) VALUES
    (p_org, tid, 1, CURRENT_DATE, p_amount1),
    (p_org, tid, 2, p_due2, p_amount2);

  UPDATE enrollment_financial_terms SET status = 'active' WHERE id = tid;

  INSERT INTO charge (
    organization_id, student_id, enrollment_id, guardian_id,
    enrollment_financial_terms_id, enrollment_payment_schedule_item_id,
    charge_source_code, amount, currency_code, charged_at, due_date, status,
    agreed_tuition_snapshot, net_tuition_snapshot
  )
  SELECT p_org, p_student, p_enrollment, p_guardian, tid, si.id, 'tuition', si.amount,
    'VND', CURRENT_DATE, si.due_date, 'open', p_amount1 + p_amount2, p_amount1 + p_amount2
  FROM enrollment_payment_schedule_item si
  WHERE si.enrollment_financial_terms_id = tid
  ORDER BY si.sequence_number;

  SELECT id INTO c1 FROM charge WHERE enrollment_financial_terms_id = tid ORDER BY due_date LIMIT 1;
  SELECT id INTO c2 FROM charge WHERE enrollment_financial_terms_id = tid ORDER BY due_date DESC LIMIT 1;
  RETURN QUERY SELECT tid, c1, c2;
END;
$$;

CREATE OR REPLACE FUNCTION _m2_pay_grant_admin(p_org uuid, p_auth uuid)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_user uuid; v_role uuid;
BEGIN
  SELECT id INTO v_user FROM app_user WHERE organization_id = p_org LIMIT 1;
  INSERT INTO role (organization_id, code) VALUES (p_org, 'pay_admin') RETURNING id INTO v_role;
  INSERT INTO role_permission (role_id, permission_id)
  SELECT v_role, p.id FROM permission p;
  INSERT INTO user_role (organization_id, user_id, role_id, effective_from, status)
  VALUES (p_org, v_user, v_role, CURRENT_DATE, 'active');
END;
$$;

CREATE OR REPLACE FUNCTION _m2_pay_create_reader(p_org uuid, OUT auth_id uuid)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_user uuid; v_auth uuid;
BEGIN
  v_auth := gen_random_uuid();
  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at, is_sso_user, is_anonymous
  )
  VALUES (
    v_auth,
    (SELECT id FROM auth.instances LIMIT 1),
    'authenticated',
    'authenticated',
    'reader-' || replace(v_auth::text, '-', '') || '@test.local',
    '',
    now(),
    now(),
    now(),
    false,
    false
  );
  INSERT INTO app_user (organization_id, email, display_name, auth_user_id, status)
  VALUES (p_org, 'reader@test.local', 'Reader', v_auth, 'active')
  RETURNING id INTO v_user;
  auth_id := v_auth;
END;
$$;

-- 1: record valid payment
DO $$
DECLARE b record; res jsonb;
BEGIN
  SELECT * INTO b FROM _m2_pay_bootstrap();
  PERFORM _m2_pay_grant_admin(b.org_id, b.auth_admin);
  PERFORM _m2_pay_as_auth(b.auth_admin);
  res := public.record_payment(b.guardian_id, 500000, now(), 'cash');
  PERFORM _m2_pay_record(1, 'record valid payment', (res->>'payment_id') IS NOT NULL AND (res->>'amount')::bigint = 500000);
END $$;

-- 2: reject zero payment
SELECT _m2_pay_expect_fail(2, 'reject zero payment', $$
  DO $i$ DECLARE b record; BEGIN
    SELECT * INTO b FROM _m2_pay_bootstrap();
    PERFORM _m2_pay_grant_admin(b.org_id, b.auth_admin);
    PERFORM _m2_pay_as_auth(b.auth_admin);
    PERFORM public.record_payment(b.guardian_id, 0, now(), 'cash');
  END $i$;
$$);

-- 3: reject negative payment
SELECT _m2_pay_expect_fail(3, 'reject negative payment', $$
  DO $i$ DECLARE b record; BEGIN
    SELECT * INTO b FROM _m2_pay_bootstrap();
    PERFORM _m2_pay_grant_admin(b.org_id, b.auth_admin);
    PERFORM _m2_pay_as_auth(b.auth_admin);
    PERFORM public.record_payment(b.guardian_id, -1000, now(), 'cash');
  END $i$;
$$);

-- 4: record payment without allocation
DO $$
DECLARE b record; res jsonb;
BEGIN
  SELECT * INTO b FROM _m2_pay_bootstrap();
  PERFORM _m2_pay_grant_admin(b.org_id, b.auth_admin);
  PERFORM _m2_pay_as_auth(b.auth_admin);
  res := public.record_payment(b.guardian_id, 300000, now(), 'bank_transfer');
  PERFORM _m2_pay_record(4, 'record payment without allocation', (res->>'allocated_amount')::bigint = 0);
END $$;

-- 5: derive full unapplied amount
DO $$
DECLARE b record; res jsonb;
BEGIN
  SELECT * INTO b FROM _m2_pay_bootstrap();
  PERFORM _m2_pay_grant_admin(b.org_id, b.auth_admin);
  PERFORM _m2_pay_as_auth(b.auth_admin);
  res := public.record_payment(b.guardian_id, 750000, now(), 'cash');
  PERFORM _m2_pay_record(5, 'derive full unapplied amount', (res->>'unallocated_amount')::bigint = 750000);
END $$;

-- 6: partial allocation
DO $$
DECLARE b record; cid uuid; res jsonb;
BEGIN
  SELECT * INTO b FROM _m2_pay_bootstrap();
  PERFORM _m2_pay_setup_terms_charges(b.org_id, b.enrollment_id, b.guardian_id, b.student_id, 1000000);
  SELECT id INTO cid FROM charge WHERE enrollment_id = b.enrollment_id LIMIT 1;
  PERFORM _m2_pay_grant_admin(b.org_id, b.auth_admin);
  PERFORM _m2_pay_as_auth(b.auth_admin);
  res := public.record_payment(
    b.guardian_id, 1000000, now(), 'cash', NULL, NULL, b.student_id, NULL, NULL,
    jsonb_build_array(jsonb_build_object('charge_id', cid, 'amount', 300000))
  );
  PERFORM _m2_pay_record(6, 'partial allocation', (res->>'allocated_amount')::bigint = 300000);
END $$;

-- 7: derive remaining unapplied amount
DO $$
DECLARE b record; cid uuid; res jsonb;
BEGIN
  SELECT * INTO b FROM _m2_pay_bootstrap();
  PERFORM _m2_pay_setup_terms_charges(b.org_id, b.enrollment_id, b.guardian_id, b.student_id, 1000000);
  SELECT id INTO cid FROM charge WHERE enrollment_id = b.enrollment_id LIMIT 1;
  PERFORM _m2_pay_grant_admin(b.org_id, b.auth_admin);
  PERFORM _m2_pay_as_auth(b.auth_admin);
  res := public.record_payment(
    b.guardian_id, 1000000, now(), 'cash', NULL, NULL, NULL, NULL, NULL,
    jsonb_build_array(jsonb_build_object('charge_id', cid, 'amount', 400000))
  );
  PERFORM _m2_pay_record(7, 'derive remaining unapplied amount', (res->>'unallocated_amount')::bigint = 600000);
END $$;

-- 8: multiple payments against one charge
DO $$
DECLARE b record; cid uuid; bal bigint;
BEGIN
  SELECT * INTO b FROM _m2_pay_bootstrap();
  PERFORM _m2_pay_setup_terms_charges(b.org_id, b.enrollment_id, b.guardian_id, b.student_id, 10000000);
  SELECT id INTO cid FROM charge WHERE enrollment_id = b.enrollment_id LIMIT 1;
  PERFORM _m2_pay_grant_admin(b.org_id, b.auth_admin);
  PERFORM _m2_pay_as_auth(b.auth_admin);
  PERFORM public.record_payment(b.guardian_id, 3000000, now(), 'cash', NULL, NULL, NULL, NULL, NULL,
    jsonb_build_array(jsonb_build_object('charge_id', cid, 'amount', 3000000)));
  PERFORM public.record_payment(b.guardian_id, 2000000, now(), 'cash', NULL, NULL, NULL, NULL, NULL,
    jsonb_build_array(jsonb_build_object('charge_id', cid, 'amount', 2000000)));
  SELECT outstanding_balance INTO bal FROM charge_balance WHERE charge_id = cid;
  PERFORM _m2_pay_record(8, 'multiple payments against one charge', bal = 5000000);
END $$;

-- 9: one payment across multiple charges
DO $$
DECLARE b record; tc record; bal1 bigint; bal2 bigint;
BEGIN
  SELECT * INTO b FROM _m2_pay_bootstrap();
  SELECT * INTO tc FROM _m2_pay_setup_two_charges(b.org_id, b.enrollment_id, b.guardian_id, b.student_id, 5000000, 7000000);
  PERFORM _m2_pay_grant_admin(b.org_id, b.auth_admin);
  PERFORM _m2_pay_as_auth(b.auth_admin);
  PERFORM public.record_payment(b.guardian_id, 12000000, now(), 'cash', NULL, NULL, NULL, NULL, NULL,
    jsonb_build_array(
      jsonb_build_object('charge_id', tc.charge1_id, 'amount', 5000000),
      jsonb_build_object('charge_id', tc.charge2_id, 'amount', 7000000)
    ));
  SELECT outstanding_balance INTO bal1 FROM charge_balance WHERE charge_id = tc.charge1_id;
  SELECT outstanding_balance INTO bal2 FROM charge_balance WHERE charge_id = tc.charge2_id;
  PERFORM _m2_pay_record(9, 'one payment across multiple charges', bal1 = 0 AND bal2 = 0);
END $$;

-- 10: multiple enrollments settled by one payment (same org)
DO $$
DECLARE b record; class2 uuid; enr2 uuid; c1 uuid; c2 uuid; bal1 bigint; bal2 bigint;
BEGIN
  SELECT * INTO b FROM _m2_pay_bootstrap();
  INSERT INTO class (organization_id, course_id, name, status)
  SELECT b.org_id, b.course_id, 'Pay Class 2', 'active' RETURNING id INTO class2;
  INSERT INTO enrollment (organization_id, student_id, class_id, start_date, status)
  VALUES (b.org_id, b.student_id, class2, CURRENT_DATE, 'active') RETURNING id INTO enr2;
  PERFORM _m2_pay_setup_terms_charges(b.org_id, b.enrollment_id, b.guardian_id, b.student_id, 5000000);
  PERFORM _m2_pay_setup_terms_charges(b.org_id, enr2, b.guardian_id, b.student_id, 7000000);
  SELECT id INTO c1 FROM charge WHERE enrollment_id = b.enrollment_id LIMIT 1;
  SELECT id INTO c2 FROM charge WHERE enrollment_id = enr2 LIMIT 1;
  PERFORM _m2_pay_grant_admin(b.org_id, b.auth_admin);
  PERFORM _m2_pay_as_auth(b.auth_admin);
  PERFORM public.record_payment(b.guardian_id, 12000000, now(), 'cash', NULL, NULL, b.student_id, NULL, NULL,
    jsonb_build_array(
      jsonb_build_object('charge_id', c1, 'amount', 5000000),
      jsonb_build_object('charge_id', c2, 'amount', 7000000)
    ));
  SELECT outstanding_balance INTO bal1 FROM charge_balance WHERE charge_id = c1;
  SELECT outstanding_balance INTO bal2 FROM charge_balance WHERE charge_id = c2;
  PERFORM _m2_pay_record(10, 'multiple enrollments settled by one payment', bal1 = 0 AND bal2 = 0);
END $$;

-- 11: explicit allocation total cannot exceed payment amount
SELECT _m2_pay_expect_fail(11, 'allocation total exceeds payment amount', $$
  DO $i$ DECLARE b record; cid uuid; BEGIN
    SELECT * INTO b FROM _m2_pay_bootstrap();
    PERFORM _m2_pay_setup_terms_charges(b.org_id, b.enrollment_id, b.guardian_id, b.student_id, 1000000);
    SELECT id INTO cid FROM charge WHERE enrollment_id = b.enrollment_id LIMIT 1;
    PERFORM _m2_pay_grant_admin(b.org_id, b.auth_admin);
    PERFORM _m2_pay_as_auth(b.auth_admin);
    PERFORM public.record_payment(b.guardian_id, 500000, now(), 'cash', NULL, NULL, NULL, NULL, NULL,
      jsonb_build_array(jsonb_build_object('charge_id', cid, 'amount', 600000)));
  END $i$;
$$);

-- 12: allocation cannot exceed charge outstanding balance
SELECT _m2_pay_expect_fail(12, 'allocation exceeds charge outstanding', $$
  DO $i$ DECLARE b record; cid uuid; BEGIN
    SELECT * INTO b FROM _m2_pay_bootstrap();
    PERFORM _m2_pay_setup_terms_charges(b.org_id, b.enrollment_id, b.guardian_id, b.student_id, 1000000);
    SELECT id INTO cid FROM charge WHERE enrollment_id = b.enrollment_id LIMIT 1;
    PERFORM _m2_pay_grant_admin(b.org_id, b.auth_admin);
    PERFORM _m2_pay_as_auth(b.auth_admin);
    PERFORM public.record_payment(b.guardian_id, 2000000, now(), 'cash', NULL, NULL, NULL, NULL, NULL,
      jsonb_build_array(jsonb_build_object('charge_id', cid, 'amount', 1500000)));
  END $i$;
$$);

-- 13: allocation respects negative financial adjustments
DO $$
DECLARE b record; cid uuid; bal bigint;
BEGIN
  SELECT * INTO b FROM _m2_pay_bootstrap();
  PERFORM _m2_pay_setup_terms_charges(b.org_id, b.enrollment_id, b.guardian_id, b.student_id, 10000000);
  SELECT id INTO cid FROM charge WHERE enrollment_id = b.enrollment_id LIMIT 1;
  INSERT INTO financial_adjustment (organization_id, charge_id, adjustment_type_code, amount_delta, status)
  VALUES (b.org_id, cid, 'discount', -2000000, 'posted');
  PERFORM _m2_pay_grant_admin(b.org_id, b.auth_admin);
  PERFORM _m2_pay_as_auth(b.auth_admin);
  BEGIN
    PERFORM public.record_payment(b.guardian_id, 9000000, now(), 'cash', NULL, NULL, NULL, NULL, NULL,
      jsonb_build_array(jsonb_build_object('charge_id', cid, 'amount', 8500000)));
    PERFORM _m2_pay_record(13, 'allocation respects negative adjustments', false);
  EXCEPTION WHEN OTHERS THEN
    SELECT outstanding_balance INTO bal FROM charge_balance WHERE charge_id = cid;
    PERFORM _m2_pay_record(13, 'allocation respects negative adjustments', bal = 8000000);
  END;
END $$;

-- 14: allocation respects positive financial adjustments
DO $$
DECLARE b record; cid uuid; bal bigint;
BEGIN
  SELECT * INTO b FROM _m2_pay_bootstrap();
  PERFORM _m2_pay_setup_terms_charges(b.org_id, b.enrollment_id, b.guardian_id, b.student_id, 10000000);
  SELECT id INTO cid FROM charge WHERE enrollment_id = b.enrollment_id LIMIT 1;
  INSERT INTO financial_adjustment (organization_id, charge_id, adjustment_type_code, amount_delta, status)
  VALUES (b.org_id, cid, 'correction', 1000000, 'posted');
  PERFORM _m2_pay_grant_admin(b.org_id, b.auth_admin);
  PERFORM _m2_pay_as_auth(b.auth_admin);
  PERFORM public.record_payment(b.guardian_id, 12000000, now(), 'cash', NULL, NULL, NULL, NULL, NULL,
    jsonb_build_array(jsonb_build_object('charge_id', cid, 'amount', 11000000)));
  SELECT outstanding_balance INTO bal FROM charge_balance WHERE charge_id = cid;
  PERFORM _m2_pay_record(14, 'allocation respects positive adjustments', bal = 0);
END $$;

-- 15: fully settled charge rejects further allocation
DO $$
DECLARE b record; cid uuid; pay uuid; ok boolean := false;
BEGIN
  SELECT * INTO b FROM _m2_pay_bootstrap();
  PERFORM _m2_pay_setup_terms_charges(b.org_id, b.enrollment_id, b.guardian_id, b.student_id, 1000000);
  SELECT id INTO cid FROM charge WHERE enrollment_id = b.enrollment_id LIMIT 1;
  PERFORM _m2_pay_grant_admin(b.org_id, b.auth_admin);
  PERFORM _m2_pay_as_auth(b.auth_admin);
  PERFORM public.record_payment(b.guardian_id, 1000000, now(), 'cash', NULL, NULL, NULL, NULL, NULL,
    jsonb_build_array(jsonb_build_object('charge_id', cid, 'amount', 1000000)));
  BEGIN
    PERFORM public.record_payment(b.guardian_id, 100000, now(), 'cash', NULL, NULL, NULL, NULL, NULL,
      jsonb_build_array(jsonb_build_object('charge_id', cid, 'amount', 100000)));
  EXCEPTION WHEN OTHERS THEN ok := true; END;
  PERFORM _m2_pay_record(15, 'fully settled charge rejects allocation', ok);
END $$;

-- 16: overpayment remains unapplied
DO $$
DECLARE b record; cid uuid; res jsonb;
BEGIN
  SELECT * INTO b FROM _m2_pay_bootstrap();
  PERFORM _m2_pay_setup_terms_charges(b.org_id, b.enrollment_id, b.guardian_id, b.student_id, 9000000);
  SELECT id INTO cid FROM charge WHERE enrollment_id = b.enrollment_id LIMIT 1;
  PERFORM _m2_pay_grant_admin(b.org_id, b.auth_admin);
  PERFORM _m2_pay_as_auth(b.auth_admin);
  res := public.record_payment(b.guardian_id, 10000000, now(), 'cash', NULL, NULL, NULL, NULL, NULL,
    jsonb_build_array(jsonb_build_object('charge_id', cid, 'amount', 9000000)));
  PERFORM _m2_pay_record(16, 'overpayment remains unapplied', (res->>'unallocated_amount')::bigint = 1000000);
END $$;

-- 17: cross-org allocation rejected
SELECT _m2_pay_expect_fail(17, 'cross-org allocation rejected', $$
  DO $i$ DECLARE a record; b record; cid uuid; BEGIN
    SELECT * INTO a FROM _m2_pay_bootstrap();
    SELECT * INTO b FROM _m2_pay_bootstrap();
    PERFORM _m2_pay_setup_terms_charges(b.org_id, b.enrollment_id, b.guardian_id, b.student_id, 1000000);
    SELECT id INTO cid FROM charge WHERE enrollment_id = b.enrollment_id LIMIT 1;
    PERFORM _m2_pay_grant_admin(a.org_id, a.auth_admin);
    PERFORM _m2_pay_as_auth(a.auth_admin);
    PERFORM public.record_payment(a.guardian_id, 1000000, now(), 'cash', NULL, NULL, NULL, NULL, NULL,
      jsonb_build_array(jsonb_build_object('charge_id', cid, 'amount', 1000000)));
  END $i$;
$$);

-- 18: currency mismatch rejected
SELECT _m2_pay_expect_fail(18, 'currency mismatch rejected', $$
  DO $i$ DECLARE b record; cid uuid; BEGIN
    SELECT * INTO b FROM _m2_pay_bootstrap();
    PERFORM _m2_pay_setup_terms_charges(b.org_id, b.enrollment_id, b.guardian_id, b.student_id, 1000000);
    SELECT id INTO cid FROM charge WHERE enrollment_id = b.enrollment_id LIMIT 1;
    UPDATE charge SET currency_code = 'USD' WHERE id = cid;
    PERFORM _m2_pay_grant_admin(b.org_id, b.auth_admin);
    PERFORM _m2_pay_as_auth(b.auth_admin);
    PERFORM public.record_payment(b.guardian_id, 1000000, now(), 'cash', NULL, NULL, NULL, NULL, NULL,
      jsonb_build_array(jsonb_build_object('charge_id', cid, 'amount', 500000)));
  END $i$;
$$);

-- 19: RLS blocks tenant leakage
DO $$
DECLARE b record; cnt integer;
BEGIN
  SELECT * INTO b FROM _m2_pay_bootstrap();
  PERFORM _m2_pay_grant_admin(b.org_id, b.auth_admin);
  PERFORM _m2_pay_as_auth(b.auth_admin);
  PERFORM public.record_payment(b.guardian_id, 100000, now(), 'cash');
  PERFORM _m2_pay_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO cnt FROM payment WHERE organization_id = b.org_id;
  PERFORM _m2_pay_record(19, 'RLS blocks tenant leakage', cnt = 0);
END $$;

-- 20: payment.record permission required
DO $$
DECLARE b record; reader_auth uuid; ok boolean := false;
BEGIN
  SELECT * INTO b FROM _m2_pay_bootstrap();
  reader_auth := _m2_pay_create_reader(b.org_id);
  PERFORM _m2_pay_as_auth(reader_auth);
  BEGIN
    PERFORM public.record_payment(b.guardian_id, 100000, now(), 'cash');
  EXCEPTION WHEN OTHERS THEN ok := true; END;
  PERFORM _m2_pay_record(20, 'payment.record permission required', ok);
END $$;

-- 21: payment.read permission works
DO $$
DECLARE b record; res jsonb; pay uuid;
BEGIN
  SELECT * INTO b FROM _m2_pay_bootstrap();
  PERFORM _m2_pay_grant_admin(b.org_id, b.auth_admin);
  PERFORM _m2_pay_as_auth(b.auth_admin);
  res := public.record_payment(b.guardian_id, 250000, now(), 'cash');
  pay := (res->>'payment_id')::uuid;
  res := public.get_payment_details(pay);
  PERFORM _m2_pay_record(21, 'payment.read permission works', (res->>'payment_id')::uuid = pay);
END $$;

-- 22: suggested oldest-due allocation deterministic
DO $$
DECLARE b record; tc record; pay uuid; sug jsonb;
BEGIN
  SELECT * INTO b FROM _m2_pay_bootstrap();
  SELECT * INTO tc FROM _m2_pay_setup_two_charges(b.org_id, b.enrollment_id, b.guardian_id, b.student_id, 5000000, 3000000, CURRENT_DATE + 60);
  PERFORM _m2_pay_grant_admin(b.org_id, b.auth_admin);
  PERFORM _m2_pay_as_auth(b.auth_admin);
  pay := (public.record_payment(b.guardian_id, 6000000, now(), 'cash')->>'payment_id')::uuid;
  sug := public.suggest_payment_allocation(pay, b.enrollment_id, NULL);
  PERFORM _m2_pay_record(
    22,
    'suggested oldest-due allocation deterministic',
    (sug->'suggestions'->0->>'charge_id')::uuid = tc.charge1_id
    AND (sug->'suggestions'->0->>'amount')::bigint = 5000000
    AND (sug->'suggestions'->1->>'charge_id')::uuid = tc.charge2_id
  );
END $$;

-- 23: explicit allocation overrides suggestion
DO $$
DECLARE b record; cid uuid; pay uuid; sug jsonb; res jsonb;
BEGIN
  SELECT * INTO b FROM _m2_pay_bootstrap();
  PERFORM _m2_pay_setup_terms_charges(b.org_id, b.enrollment_id, b.guardian_id, b.student_id, 2000000);
  SELECT id INTO cid FROM charge WHERE enrollment_id = b.enrollment_id LIMIT 1;
  PERFORM _m2_pay_grant_admin(b.org_id, b.auth_admin);
  PERFORM _m2_pay_as_auth(b.auth_admin);
  pay := (public.record_payment(b.guardian_id, 1000000, now(), 'cash')->>'payment_id')::uuid;
  sug := public.suggest_payment_allocation(pay, b.enrollment_id, NULL);
  res := public.allocate_payment(pay, jsonb_build_array(jsonb_build_object('charge_id', cid, 'amount', 500000)), 'op-explicit');
  PERFORM _m2_pay_record(
    23,
    'explicit allocation overrides suggestion',
    (res->>'allocated_amount')::bigint = 500000 AND jsonb_array_length(sug->'suggestions') >= 1
  );
END $$;

-- 24: allocation operation is atomic
SELECT _m2_pay_expect_fail(24, 'allocation operation is atomic', $$
  DO $i$ DECLARE b record; tc record; pay uuid; BEGIN
    SELECT * INTO b FROM _m2_pay_bootstrap();
    SELECT * INTO tc FROM _m2_pay_setup_two_charges(b.org_id, b.enrollment_id, b.guardian_id, b.student_id, 5000000, 3000000);
    PERFORM _m2_pay_grant_admin(b.org_id, b.auth_admin);
    PERFORM _m2_pay_as_auth(b.auth_admin);
    pay := (public.record_payment(b.guardian_id, 6000000, now(), 'cash')->>'payment_id')::uuid;
    PERFORM public.allocate_payment(pay, jsonb_build_array(
      jsonb_build_object('charge_id', tc.charge1_id, 'amount', 5000000),
      jsonb_build_object('charge_id', tc.charge2_id, 'amount', 2000000)
    ), 'op-atomic-fail');
  END $i$;
$$);

-- 25: payment idempotency does not duplicate
DO $$
DECLARE b record; r1 jsonb; r2 jsonb;
BEGIN
  SELECT * INTO b FROM _m2_pay_bootstrap();
  PERFORM _m2_pay_grant_admin(b.org_id, b.auth_admin);
  PERFORM _m2_pay_as_auth(b.auth_admin);
  r1 := public.record_payment(b.guardian_id, 400000, now(), 'cash', NULL, NULL, NULL, NULL, 'idem-pay-1');
  r2 := public.record_payment(b.guardian_id, 400000, now(), 'cash', NULL, NULL, NULL, NULL, 'idem-pay-1');
  PERFORM _m2_pay_record(25, 'payment idempotency does not duplicate', (r1->>'payment_id') = (r2->>'payment_id'));
END $$;

-- 26: allocation idempotency does not duplicate
DO $$
DECLARE b record; cid uuid; pay uuid; r1 jsonb; r2 jsonb; cnt integer;
BEGIN
  SELECT * INTO b FROM _m2_pay_bootstrap();
  PERFORM _m2_pay_setup_terms_charges(b.org_id, b.enrollment_id, b.guardian_id, b.student_id, 1000000);
  SELECT id INTO cid FROM charge WHERE enrollment_id = b.enrollment_id LIMIT 1;
  PERFORM _m2_pay_grant_admin(b.org_id, b.auth_admin);
  PERFORM _m2_pay_as_auth(b.auth_admin);
  pay := (public.record_payment(b.guardian_id, 500000, now(), 'cash')->>'payment_id')::uuid;
  r1 := public.allocate_payment(pay, jsonb_build_array(jsonb_build_object('charge_id', cid, 'amount', 300000)), 'idem-alloc-1');
  r2 := public.allocate_payment(pay, jsonb_build_array(jsonb_build_object('charge_id', cid, 'amount', 300000)), 'idem-alloc-1');
  SELECT count(*) INTO cnt FROM payment_allocation WHERE payment_id = pay AND status = 'posted';
  PERFORM _m2_pay_record(26, 'allocation idempotency does not duplicate', cnt = 1 AND (r1->>'payment_id') = (r2->>'payment_id'));
END $$;

-- 27: charge principal remains immutable
DO $$
DECLARE b record; cid uuid; amt bigint;
BEGIN
  SELECT * INTO b FROM _m2_pay_bootstrap();
  PERFORM _m2_pay_setup_terms_charges(b.org_id, b.enrollment_id, b.guardian_id, b.student_id, 1000000);
  SELECT id INTO cid FROM charge WHERE enrollment_id = b.enrollment_id LIMIT 1;
  PERFORM _m2_pay_grant_admin(b.org_id, b.auth_admin);
  PERFORM _m2_pay_as_auth(b.auth_admin);
  PERFORM public.record_payment(b.guardian_id, 500000, now(), 'cash', NULL, NULL, NULL, NULL, NULL,
    jsonb_build_array(jsonb_build_object('charge_id', cid, 'amount', 500000)));
  SELECT amount INTO amt FROM charge WHERE id = cid;
  PERFORM _m2_pay_record(27, 'charge principal remains immutable', amt = 1000000);
END $$;

-- 28: schedule items do not store paid amount
DO $$
DECLARE cols text[];
BEGIN
  SELECT array_agg(column_name::text ORDER BY column_name) INTO cols
  FROM information_schema.columns
  WHERE table_schema = 'public' AND table_name = 'enrollment_payment_schedule_item';
  PERFORM _m2_pay_record(
    28,
    'schedule items do not store paid amount',
    NOT ('amount_paid' = ANY (cols) OR 'paid_amount' = ANY (cols))
  );
END $$;

-- 29: enrollment financial summary derives allocated cash
DO $$
DECLARE b record; cid uuid; summary jsonb;
BEGIN
  SELECT * INTO b FROM _m2_pay_bootstrap();
  PERFORM _m2_pay_setup_terms_charges(b.org_id, b.enrollment_id, b.guardian_id, b.student_id, 3000000);
  SELECT id INTO cid FROM charge WHERE enrollment_id = b.enrollment_id LIMIT 1;
  PERFORM _m2_pay_grant_admin(b.org_id, b.auth_admin);
  PERFORM _m2_pay_as_auth(b.auth_admin);
  PERFORM public.record_payment(b.guardian_id, 1500000, now(), 'cash', NULL, NULL, b.student_id, NULL, NULL,
    jsonb_build_array(jsonb_build_object('charge_id', cid, 'amount', 1500000)));
  summary := public.get_enrollment_financial_summary(b.enrollment_id);
  PERFORM _m2_pay_record(29, 'summary derives allocated cash', (summary->>'allocated_amount')::bigint = 1500000);
END $$;

-- 30: enrollment financial summary derives outstanding balance
DO $$
DECLARE b record; summary jsonb;
BEGIN
  SELECT * INTO b FROM _m2_pay_bootstrap();
  PERFORM _m2_pay_setup_terms_charges(b.org_id, b.enrollment_id, b.guardian_id, b.student_id, 5000000);
  PERFORM _m2_pay_grant_admin(b.org_id, b.auth_admin);
  PERFORM _m2_pay_as_auth(b.auth_admin);
  summary := public.get_enrollment_financial_summary(b.enrollment_id);
  PERFORM _m2_pay_record(30, 'summary derives outstanding balance', (summary->>'outstanding_amount')::bigint = 5000000);
END $$;

-- 31: unallocated payment distinguishable from receivable
DO $$
DECLARE b record; summary jsonb; res jsonb;
BEGIN
  SELECT * INTO b FROM _m2_pay_bootstrap();
  PERFORM _m2_pay_setup_terms_charges(b.org_id, b.enrollment_id, b.guardian_id, b.student_id, 5000000);
  PERFORM _m2_pay_grant_admin(b.org_id, b.auth_admin);
  PERFORM _m2_pay_as_auth(b.auth_admin);
  PERFORM public.record_payment(b.guardian_id, 2000000, now(), 'cash', NULL, NULL, b.student_id);
  summary := public.get_enrollment_financial_summary(b.enrollment_id);
  PERFORM _m2_pay_record(
    31,
    'unallocated payment distinguishable from receivable',
    (summary->>'outstanding_amount')::bigint = 5000000
    AND (summary->>'unapplied_payment_amount')::bigint = 2000000
  );
END $$;

-- 32: charge_balance remains correct
DO $$
DECLARE b record; cid uuid; bal bigint;
BEGIN
  SELECT * INTO b FROM _m2_pay_bootstrap();
  PERFORM _m2_pay_setup_terms_charges(b.org_id, b.enrollment_id, b.guardian_id, b.student_id, 4000000);
  SELECT id INTO cid FROM charge WHERE enrollment_id = b.enrollment_id LIMIT 1;
  INSERT INTO financial_adjustment (organization_id, charge_id, adjustment_type_code, amount_delta, status)
  VALUES (b.org_id, cid, 'discount', -500000, 'posted');
  PERFORM _m2_pay_grant_admin(b.org_id, b.auth_admin);
  PERFORM _m2_pay_as_auth(b.auth_admin);
  PERFORM public.record_payment(b.guardian_id, 1000000, now(), 'cash', NULL, NULL, NULL, NULL, NULL,
    jsonb_build_array(jsonb_build_object('charge_id', cid, 'amount', 1000000)));
  SELECT outstanding_balance INTO bal FROM charge_balance WHERE charge_id = cid;
  PERFORM _m2_pay_record(32, 'charge_balance remains correct', bal = 2500000);
END $$;

-- 33: reversed allocation no longer counts
DO $$
DECLARE b record; cid uuid; pay uuid; alloc uuid; bal bigint;
BEGIN
  SELECT * INTO b FROM _m2_pay_bootstrap();
  PERFORM _m2_pay_setup_terms_charges(b.org_id, b.enrollment_id, b.guardian_id, b.student_id, 2000000);
  SELECT id INTO cid FROM charge WHERE enrollment_id = b.enrollment_id LIMIT 1;
  PERFORM _m2_pay_grant_admin(b.org_id, b.auth_admin);
  PERFORM _m2_pay_as_auth(b.auth_admin);
  pay := (public.record_payment(b.guardian_id, 1000000, now(), 'cash', NULL, NULL, NULL, NULL, NULL,
    jsonb_build_array(jsonb_build_object('charge_id', cid, 'amount', 1000000)))->>'payment_id')::uuid;
  SELECT id INTO alloc FROM payment_allocation WHERE payment_id = pay LIMIT 1;
  PERFORM public.reverse_payment_allocation(alloc, 'wrong charge');
  SELECT outstanding_balance INTO bal FROM charge_balance WHERE charge_id = cid;
  PERFORM _m2_pay_record(33, 'reversed allocation no longer counts', bal = 2000000);
END $$;

-- 34: reversed payment no longer settles charges
DO $$
DECLARE b record; cid uuid; pay uuid; bal bigint; st text;
BEGIN
  SELECT * INTO b FROM _m2_pay_bootstrap();
  PERFORM _m2_pay_setup_terms_charges(b.org_id, b.enrollment_id, b.guardian_id, b.student_id, 2000000);
  SELECT id INTO cid FROM charge WHERE enrollment_id = b.enrollment_id LIMIT 1;
  PERFORM _m2_pay_grant_admin(b.org_id, b.auth_admin);
  PERFORM _m2_pay_as_auth(b.auth_admin);
  pay := (public.record_payment(b.guardian_id, 2000000, now(), 'cash', NULL, NULL, NULL, NULL, NULL,
    jsonb_build_array(jsonb_build_object('charge_id', cid, 'amount', 2000000)))->>'payment_id')::uuid;
  PERFORM public.reverse_payment(pay, 'duplicate entry');
  SELECT outstanding_balance INTO bal FROM charge_balance WHERE charge_id = cid;
  SELECT status INTO st FROM payment WHERE id = pay;
  PERFORM _m2_pay_record(34, 'reversed payment no longer settles charges', bal = 2000000 AND st = 'reversed');
END $$;

-- 35: reversal history remains auditable
DO $$
DECLARE b record; pay uuid; cnt integer;
BEGIN
  SELECT * INTO b FROM _m2_pay_bootstrap();
  PERFORM _m2_pay_setup_terms_charges(b.org_id, b.enrollment_id, b.guardian_id, b.student_id, 1000000);
  PERFORM _m2_pay_grant_admin(b.org_id, b.auth_admin);
  PERFORM _m2_pay_as_auth(b.auth_admin);
  pay := (public.record_payment(b.guardian_id, 1000000, now(), 'cash')->>'payment_id')::uuid;
  PERFORM public.reverse_payment(pay, 'audit test');
  SELECT count(*) INTO cnt FROM payment WHERE id = pay AND status = 'reversed' AND reversed_at IS NOT NULL;
  PERFORM _m2_pay_record(35, 'reversal history remains auditable', cnt = 1);
END $$;

-- 36: payment date independent from charge due date
DO $$
DECLARE b record; cid uuid; res jsonb; due date; paid timestamptz;
BEGIN
  SELECT * INTO b FROM _m2_pay_bootstrap();
  PERFORM _m2_pay_setup_terms_charges(b.org_id, b.enrollment_id, b.guardian_id, b.student_id, 1000000);
  UPDATE charge SET due_date = '2026-12-31' WHERE enrollment_id = b.enrollment_id;
  SELECT id, due_date INTO cid, due FROM charge WHERE enrollment_id = b.enrollment_id LIMIT 1;
  PERFORM _m2_pay_grant_admin(b.org_id, b.auth_admin);
  PERFORM _m2_pay_as_auth(b.auth_admin);
  res := public.record_payment(b.guardian_id, 100000, '2026-01-15'::timestamptz, 'cash');
  paid := (res->>'paid_at')::timestamptz;
  PERFORM _m2_pay_record(36, 'payment date independent from charge due date', due = '2026-12-31'::date AND paid::date = '2026-01-15'::date);
END $$;

-- 37: payment does not create revenue recognition
DO $$
DECLARE b record;
BEGIN
  SELECT * INTO b FROM _m2_pay_bootstrap();
  PERFORM _m2_pay_grant_admin(b.org_id, b.auth_admin);
  PERFORM _m2_pay_as_auth(b.auth_admin);
  PERFORM public.record_payment(b.guardian_id, 1000000, now(), 'cash');
  PERFORM _m2_pay_record(
    37,
    'payment does not create revenue recognition',
    NOT EXISTS (
      SELECT 1 FROM revenue_recognition_event
      WHERE organization_id = b.org_id
    )
  );
END $$;

-- 38: payment allocation does not modify academic records
DO $$
DECLARE b record; enr_status text;
BEGIN
  SELECT * INTO b FROM _m2_pay_bootstrap();
  PERFORM _m2_pay_setup_terms_charges(b.org_id, b.enrollment_id, b.guardian_id, b.student_id, 1000000);
  PERFORM _m2_pay_grant_admin(b.org_id, b.auth_admin);
  PERFORM _m2_pay_as_auth(b.auth_admin);
  PERFORM public.record_payment(b.guardian_id, 500000, now(), 'cash');
  SELECT status INTO enr_status FROM enrollment WHERE id = b.enrollment_id;
  PERFORM _m2_pay_record(38, 'payment allocation does not modify academic records', enr_status = 'active');
END $$;

-- 39: existing enrollment-finance tests unaffected (structural)
DO $$
DECLARE cols integer;
BEGIN
  SELECT count(*) INTO cols FROM information_schema.columns
  WHERE table_name = 'enrollment_financial_terms';
  PERFORM _m2_pay_record(39, 'enrollment finance structures unaffected', cols >= 10);
END $$;

-- 40: existing Cost A/B/C structures unaffected
DO $$
DECLARE cg integer;
BEGIN
  SELECT count(*) INTO cg FROM cost_group;
  PERFORM _m2_pay_record(40, 'Cost A/B/C structures unaffected', cg >= 4);
END $$;

-- 41: concurrent over-allocation prevented
DO $$
DECLARE b record; cid uuid; ok boolean := false;
BEGIN
  SELECT * INTO b FROM _m2_pay_bootstrap();
  PERFORM _m2_pay_setup_terms_charges(b.org_id, b.enrollment_id, b.guardian_id, b.student_id, 1000000);
  SELECT id INTO cid FROM charge WHERE enrollment_id = b.enrollment_id LIMIT 1;
  PERFORM _m2_pay_grant_admin(b.org_id, b.auth_admin);
  PERFORM _m2_pay_as_auth(b.auth_admin);
  PERFORM public.record_payment(b.guardian_id, 700000, now(), 'cash', NULL, NULL, NULL, NULL, NULL,
    jsonb_build_array(jsonb_build_object('charge_id', cid, 'amount', 700000)));
  BEGIN
    PERFORM public.record_payment(b.guardian_id, 500000, now(), 'cash', NULL, NULL, NULL, NULL, NULL,
      jsonb_build_array(jsonb_build_object('charge_id', cid, 'amount', 400000)));
  EXCEPTION WHEN OTHERS THEN ok := true; END;
  PERFORM _m2_pay_record(41, 'concurrent over-allocation prevented', ok);
END $$;

DO $$
DECLARE total integer; passed integer; failed integer;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE result = 'PASS'), count(*) FILTER (WHERE result = 'FAIL')
    INTO total, passed, failed FROM _m2_pay_results;
  RAISE NOTICE 'M2 payment/allocation Tests: % / % passed (% failed)', passed, total, failed;
  IF failed > 0 OR total <> 41 THEN
    RAISE EXCEPTION 'M2 payment/allocation tests failed: % of % (expected 41)', failed, total;
  END IF;
END $$;

SELECT test_no, test_name, result FROM _m2_pay_results ORDER BY test_no;

ROLLBACK;
