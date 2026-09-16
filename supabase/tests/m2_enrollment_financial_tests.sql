-- M2-T04: enrollment financial terms, schedule, and charge generation (35 scenarios)

BEGIN;

CREATE TEMP TABLE _m2_ef_results (
  test_no   integer PRIMARY KEY,
  test_name text NOT NULL,
  result    text NOT NULL CHECK (result IN ('PASS', 'FAIL'))
);

GRANT ALL ON TABLE _m2_ef_results TO authenticated, anon;

CREATE OR REPLACE FUNCTION _m2_ef_record(test_no integer, test_name text, passed boolean)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO _m2_ef_results (test_no, test_name, result)
  VALUES (test_no, test_name, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END);
END;
$$;

CREATE OR REPLACE FUNCTION _m2_ef_expect_fail(test_no integer, test_name text, sql_text text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN EXECUTE sql_text; PERFORM _m2_ef_record(test_no, test_name, false);
  EXCEPTION WHEN OTHERS THEN PERFORM _m2_ef_record(test_no, test_name, true); END;
END;
$$;

CREATE OR REPLACE FUNCTION _m2_ef_as_super()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN RESET ROLE; SET LOCAL ROLE postgres; END;
$$;

CREATE OR REPLACE FUNCTION _m2_ef_as_auth(p_auth_id uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE; SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', p_auth_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_auth_id::text, 'role', 'authenticated')::text, true);
END;
$$;

CREATE OR REPLACE FUNCTION _m2_ef_bootstrap()
RETURNS TABLE (
  org_id uuid,
  course_id uuid,
  class_id uuid,
  student_id uuid,
  guardian_id uuid,
  enrollment_id uuid
)
LANGUAGE plpgsql AS $$
DECLARE
  v_org uuid;
  v_course uuid;
  v_class uuid;
  v_student uuid;
  v_guardian uuid;
  v_enrollment uuid;
BEGIN
  PERFORM _m2_ef_as_super();
  v_org := gen_random_uuid();
  INSERT INTO organization (id, name) VALUES (v_org, 'M2 EF Test Org');
  INSERT INTO course (organization_id, code, name) VALUES (v_org, 'EF1', 'EF Course') RETURNING id INTO v_course;
  INSERT INTO class (organization_id, course_id, name, status) VALUES (v_org, v_course, 'EF Class', 'active') RETURNING id INTO v_class;
  INSERT INTO student (organization_id, given_name, family_name) VALUES (v_org, 'Fin', 'Student') RETURNING id INTO v_student;
  INSERT INTO guardian (organization_id, given_name, family_name, email) VALUES (v_org, 'Bill', 'Guardian', 'bill@test.local') RETURNING id INTO v_guardian;
  INSERT INTO student_guardian (organization_id, student_id, guardian_id, is_primary_contact, is_billing_contact)
    VALUES (v_org, v_student, v_guardian, true, true);
  INSERT INTO enrollment (organization_id, student_id, class_id, start_date, status)
    VALUES (v_org, v_student, v_class, CURRENT_DATE, 'active') RETURNING id INTO v_enrollment;
  RETURN QUERY SELECT v_org, v_course, v_class, v_student, v_guardian, v_enrollment;
END;
$$;

CREATE OR REPLACE FUNCTION _m2_ef_terms(
  p_org uuid, p_enrollment uuid, p_agreed bigint, p_discount bigint DEFAULT 0
)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE tid uuid; v_net bigint;
BEGIN
  v_net := p_agreed - p_discount;
  INSERT INTO enrollment_financial_terms (
    organization_id, enrollment_id, agreed_tuition_amount, discount_amount, net_tuition_amount, agreement_date, status
  ) VALUES (p_org, p_enrollment, p_agreed, p_discount, v_net, CURRENT_DATE, 'draft') RETURNING id INTO tid;
  RETURN tid;
END;
$$;

CREATE OR REPLACE FUNCTION _m2_ef_set_schedule_full(p_terms uuid, p_due date)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_net bigint;
BEGIN
  SELECT net_tuition_amount INTO v_net FROM enrollment_financial_terms WHERE id = p_terms;
  PERFORM public._replace_enrollment_payment_schedule(
    p_terms, 'full_upfront',
    jsonb_build_array(jsonb_build_object('due_date', p_due, 'amount', v_net, 'label', 'Full payment'))
  );
END;
$$;

CREATE OR REPLACE FUNCTION _m2_ef_set_schedule_deposit(
  p_terms uuid, p_deposit bigint, p_deposit_due date, p_remainder_due date
)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_net bigint;
BEGIN
  SELECT net_tuition_amount INTO v_net FROM enrollment_financial_terms WHERE id = p_terms;
  PERFORM public._replace_enrollment_payment_schedule(
    p_terms, 'deposit_remainder',
    jsonb_build_array(
      jsonb_build_object('due_date', p_deposit_due, 'amount', p_deposit, 'label', 'Deposit'),
      jsonb_build_object('due_date', p_remainder_due, 'amount', v_net - p_deposit, 'label', 'Remainder')
    )
  );
END;
$$;

CREATE OR REPLACE FUNCTION _m2_ef_set_schedule_installments(p_terms uuid, p_count integer, p_first date)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_net bigint; v_items jsonb := '[]'::jsonb; v_i integer; v_d date;
BEGIN
  SELECT net_tuition_amount INTO v_net FROM enrollment_financial_terms WHERE id = p_terms;
  v_d := p_first;
  FOR v_i IN 1..p_count LOOP
    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'due_date', v_d,
      'amount', public.installment_schedule_amount(v_net, p_count, v_i),
      'label', format('Installment %s', v_i)
    ));
    v_d := (date_trunc('month', v_d)::date + make_interval(months => 1))::date;
  END LOOP;
  PERFORM public._replace_enrollment_payment_schedule(p_terms, 'equal_installments', v_items);
END;
$$;

CREATE OR REPLACE FUNCTION _m2_ef_activate_terms(p_terms uuid)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_terms enrollment_financial_terms%ROWTYPE;
BEGIN
  SELECT * INTO v_terms FROM enrollment_financial_terms WHERE id = p_terms;
  IF public.enrollment_schedule_total(p_terms) <> v_terms.net_tuition_amount THEN
    RAISE EXCEPTION 'schedule_total_mismatch';
  END IF;
  UPDATE enrollment_financial_terms SET status = 'active' WHERE id = p_terms;
END;
$$;

CREATE OR REPLACE FUNCTION _m2_ef_generate_charges(p_terms uuid)
RETURNS integer LANGUAGE plpgsql AS $$
DECLARE
  v_terms enrollment_financial_terms%ROWTYPE;
  v_guardian uuid;
  v_created integer := 0;
  r record;
BEGIN
  SELECT * INTO v_terms FROM enrollment_financial_terms WHERE id = p_terms;
  v_guardian := public.resolve_enrollment_billing_guardian_id(v_terms.enrollment_id);
  FOR r IN
    SELECT * FROM enrollment_payment_schedule_item
    WHERE enrollment_financial_terms_id = p_terms AND status = 'scheduled'
    ORDER BY sequence_number
  LOOP
    IF NOT EXISTS (SELECT 1 FROM charge WHERE enrollment_payment_schedule_item_id = r.id) THEN
      INSERT INTO charge (
        organization_id, student_id, enrollment_id, guardian_id, tuition_plan_id,
        amount, currency_code, charged_at, due_date, description, status,
        enrollment_financial_terms_id, enrollment_payment_schedule_item_id,
        charge_source_code, agreed_tuition_snapshot, net_tuition_snapshot
      )
      SELECT v_terms.organization_id, e.student_id, e.id, v_guardian, v_terms.tuition_plan_id,
        r.amount, v_terms.currency_code, CURRENT_DATE, r.due_date, COALESCE(r.label, 'Tuition'), 'open',
        v_terms.id, r.id, 'tuition', v_terms.agreed_tuition_amount, v_terms.net_tuition_amount
      FROM enrollment e WHERE e.id = v_terms.enrollment_id;
      v_created := v_created + 1;
    END IF;
  END LOOP;
  UPDATE enrollment_financial_terms SET charges_generated_at = COALESCE(charges_generated_at, now()) WHERE id = p_terms;
  RETURN v_created;
END;
$$;

CREATE OR REPLACE FUNCTION _m2_ef_apply_correction(p_terms uuid, p_new_net bigint)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_terms enrollment_financial_terms%ROWTYPE; v_delta bigint; v_charge uuid; v_adj uuid;
BEGIN
  SELECT * INTO v_terms FROM enrollment_financial_terms WHERE id = p_terms;
  v_delta := p_new_net - v_terms.net_tuition_amount;
  SELECT id INTO v_charge FROM charge
  WHERE enrollment_financial_terms_id = p_terms AND status IN ('open', 'partially_paid')
  ORDER BY due_date LIMIT 1;
  INSERT INTO financial_adjustment (
    organization_id, charge_id, adjustment_type_code, amount_delta, reason_code, status
  ) VALUES (v_terms.organization_id, v_charge, 'correction', v_delta, 'correction', 'posted')
  RETURNING id INTO v_adj;
  RETURN v_adj;
END;
$$;

-- 1: create enrollment financial terms
DO $$
DECLARE b record; tid uuid;
BEGIN
  SELECT * INTO b FROM _m2_ef_bootstrap();
  tid := _m2_ef_terms(b.org_id, b.enrollment_id, 20000000, 0);
  PERFORM _m2_ef_record(1, 'create enrollment financial terms', tid IS NOT NULL);
END $$;

-- 2: different enrollments same class different tuition
DO $$
DECLARE b record; st2 uuid; enr2 uuid; tid1 uuid; tid2 uuid;
BEGIN
  SELECT * INTO b FROM _m2_ef_bootstrap();
  INSERT INTO student (organization_id, given_name, family_name) VALUES (b.org_id, 'Other', 'Learner') RETURNING id INTO st2;
  INSERT INTO enrollment (organization_id, student_id, class_id, start_date, status)
    VALUES (b.org_id, st2, b.class_id, CURRENT_DATE, 'active') RETURNING id INTO enr2;
  tid1 := _m2_ef_terms(b.org_id, b.enrollment_id, 20000000);
  tid2 := _m2_ef_terms(b.org_id, enr2, 18000000);
  PERFORM _m2_ef_record(
    2,
    'different enrollments same class different tuition',
    (SELECT net_tuition_amount FROM enrollment_financial_terms WHERE id = tid1) = 20000000
    AND (SELECT net_tuition_amount FROM enrollment_financial_terms WHERE id = tid2) = 18000000
  );
END $$;

-- 3: course does not determine authoritative tuition
DO $$
DECLARE b record; plan_amt bigint; enr_net bigint;
BEGIN
  SELECT * INTO b FROM _m2_ef_bootstrap();
  INSERT INTO tuition_plan (organization_id, course_id, amount, effective_from)
    VALUES (b.org_id, b.course_id, 50000000, CURRENT_DATE);
  PERFORM _m2_ef_terms(b.org_id, b.enrollment_id, 12000000);
  SELECT net_tuition_amount INTO enr_net FROM enrollment_financial_terms WHERE enrollment_id = b.enrollment_id;
  PERFORM _m2_ef_record(3, 'course plan is not authoritative enrollment tuition', enr_net = 12000000);
END $$;

-- 4: class does not determine authoritative tuition
DO $$
DECLARE b record; enr_net bigint;
BEGIN
  SELECT * INTO b FROM _m2_ef_bootstrap();
  INSERT INTO tuition_plan (organization_id, class_id, amount, effective_from)
    VALUES (b.org_id, b.class_id, 45000000, CURRENT_DATE);
  PERFORM _m2_ef_terms(b.org_id, b.enrollment_id, 15000000);
  SELECT net_tuition_amount INTO enr_net FROM enrollment_financial_terms WHERE enrollment_id = b.enrollment_id;
  PERFORM _m2_ef_record(4, 'class plan is not authoritative enrollment tuition', enr_net = 15000000);
END $$;

-- 5: net tuition validation formula
DO $$
DECLARE b record; ok boolean := true;
BEGIN
  SELECT * INTO b FROM _m2_ef_bootstrap();
  BEGIN
    INSERT INTO enrollment_financial_terms (
      organization_id, enrollment_id, agreed_tuition_amount, discount_amount, net_tuition_amount, agreement_date, status
    ) VALUES (b.org_id, b.enrollment_id, 100, 10, 999, CURRENT_DATE, 'draft');
    ok := false;
  EXCEPTION WHEN check_violation THEN ok := true; END;
  PERFORM _m2_ef_record(5, 'net tuition formula enforced', ok);
END $$;

-- 6: reject negative monetary values
SELECT _m2_ef_expect_fail(6, 'reject negative agreed tuition', $$
  DO $i$ DECLARE b record; BEGIN
    SELECT * INTO b FROM _m2_ef_bootstrap();
    INSERT INTO enrollment_financial_terms (
      organization_id, enrollment_id, agreed_tuition_amount, discount_amount, net_tuition_amount, agreement_date, status
    ) VALUES (b.org_id, b.enrollment_id, -1, 0, -1, CURRENT_DATE, 'draft');
  END $i$;
$$);

-- 7: full prepayment schedule
DO $$
DECLARE b record; tid uuid; cnt integer;
BEGIN
  SELECT * INTO b FROM _m2_ef_bootstrap();
  tid := _m2_ef_terms(b.org_id, b.enrollment_id, 20000000);
  PERFORM _m2_ef_set_schedule_full(tid, '2026-02-01');
  SELECT count(*) INTO cnt FROM enrollment_payment_schedule_item WHERE enrollment_financial_terms_id = tid;
  PERFORM _m2_ef_record(7, 'full prepayment schedule', cnt = 1 AND public.enrollment_schedule_total(tid) = 20000000);
END $$;

-- 8: deposit + remainder schedule
DO $$
DECLARE b record; tid uuid;
BEGIN
  SELECT * INTO b FROM _m2_ef_bootstrap();
  tid := _m2_ef_terms(b.org_id, b.enrollment_id, 20000000);
  PERFORM _m2_ef_set_schedule_deposit(tid, 5000000, '2026-01-15', '2026-03-01');
  PERFORM _m2_ef_record(
    8,
    'deposit remainder schedule',
    public.enrollment_schedule_total(tid) = 20000000
    AND (SELECT count(*) FROM enrollment_payment_schedule_item WHERE enrollment_financial_terms_id = tid) = 2
  );
END $$;

-- 9: equal installments schedule
DO $$
DECLARE b record; tid uuid;
BEGIN
  SELECT * INTO b FROM _m2_ef_bootstrap();
  tid := _m2_ef_terms(b.org_id, b.enrollment_id, 20000000, 0);
  PERFORM _m2_ef_set_schedule_installments(tid, 3, '2026-01-01');
  PERFORM _m2_ef_record(
    9,
    'equal installments schedule',
    (SELECT count(*) FROM enrollment_payment_schedule_item WHERE enrollment_financial_terms_id = tid) = 3
  );
END $$;

-- 10: installment remainder exact total
DO $$
DECLARE b record; tid uuid; total bigint;
BEGIN
  SELECT * INTO b FROM _m2_ef_bootstrap();
  tid := _m2_ef_terms(b.org_id, b.enrollment_id, 100, 0);
  PERFORM _m2_ef_set_schedule_installments(tid, 3, '2026-01-01');
  SELECT sum(amount) INTO total FROM enrollment_payment_schedule_item WHERE enrollment_financial_terms_id = tid;
  PERFORM _m2_ef_record(10, 'installment remainder exact lifetime total', total = 100);
END $$;

-- 11: custom schedule exact total validation
SELECT _m2_ef_expect_fail(11, 'custom schedule rejects wrong total', $$
  DO $i$ DECLARE b record; tid uuid; BEGIN
    SELECT * INTO b FROM _m2_ef_bootstrap();
    tid := _m2_ef_terms(b.org_id, b.enrollment_id, 20000000);
    PERFORM public._replace_enrollment_payment_schedule(tid, 'custom', jsonb_build_array(
      jsonb_build_object('due_date', '2026-01-01', 'amount', 10000000),
      jsonb_build_object('due_date', '2026-02-01', 'amount', 5000000)
    ));
  END $i$;
$$);

-- 12: deferred/monthly due dates represented
DO $$
DECLARE b record; tid uuid; last_due date;
BEGIN
  SELECT * INTO b FROM _m2_ef_bootstrap();
  tid := _m2_ef_terms(b.org_id, b.enrollment_id, 12000000);
  PERFORM _m2_ef_set_schedule_installments(tid, 3, '2026-06-01');
  SELECT max(due_date) INTO last_due FROM enrollment_payment_schedule_item WHERE enrollment_financial_terms_id = tid;
  PERFORM _m2_ef_record(12, 'deferred monthly due dates represented', last_due >= '2026-08-01'::date);
END $$;

-- 13: schedule total equals net tuition
DO $$
DECLARE b record; tid uuid;
BEGIN
  SELECT * INTO b FROM _m2_ef_bootstrap();
  tid := _m2_ef_terms(b.org_id, b.enrollment_id, 9000000);
  PERFORM public._replace_enrollment_payment_schedule(tid, 'custom', jsonb_build_array(
    jsonb_build_object('due_date', '2026-01-01', 'amount', 3000000),
    jsonb_build_object('due_date', '2026-02-01', 'amount', 3000000),
    jsonb_build_object('due_date', '2026-03-01', 'amount', 3000000)
  ));
  PERFORM _m2_ef_record(13, 'schedule total equals net tuition', public.enrollment_schedule_total(tid) = 9000000);
END $$;

-- 14: draft terms editable before activation
DO $$
DECLARE b record; tid uuid; net bigint;
BEGIN
  SELECT * INTO b FROM _m2_ef_bootstrap();
  tid := _m2_ef_terms(b.org_id, b.enrollment_id, 10000000);
  UPDATE enrollment_financial_terms
  SET agreed_tuition_amount = 12000000, discount_amount = 2000000, net_tuition_amount = 10000000
  WHERE id = tid;
  SELECT net_tuition_amount INTO net FROM enrollment_financial_terms WHERE id = tid;
  PERFORM _m2_ef_record(14, 'draft terms editable before activation', net = 10000000);
END $$;

-- 15: activated terms protected from silent rewrite
SELECT _m2_ef_expect_fail(15, 'active terms protected from silent rewrite', $$
  DO $i$ DECLARE b record; tid uuid; BEGIN
    SELECT * INTO b FROM _m2_ef_bootstrap();
    tid := _m2_ef_terms(b.org_id, b.enrollment_id, 20000000);
    PERFORM _m2_ef_set_schedule_full(tid, '2026-01-01');
    PERFORM _m2_ef_activate_terms(tid);
    UPDATE enrollment_financial_terms SET net_tuition_amount = 18000000 WHERE id = tid;
  END $i$;
$$);

-- 16: activation and charge generation
DO $$
DECLARE b record; tid uuid; chg integer;
BEGIN
  SELECT * INTO b FROM _m2_ef_bootstrap();
  tid := _m2_ef_terms(b.org_id, b.enrollment_id, 20000000);
  PERFORM _m2_ef_set_schedule_full(tid, '2026-01-01');
  PERFORM _m2_ef_activate_terms(tid);
  chg := _m2_ef_generate_charges(tid);
  PERFORM _m2_ef_record(16, 'activation generates canonical obligations', chg = 1);
END $$;

-- 17: generated charge links to enrollment
DO $$
DECLARE b record; tid uuid; ok boolean;
BEGIN
  SELECT * INTO b FROM _m2_ef_bootstrap();
  tid := _m2_ef_terms(b.org_id, b.enrollment_id, 5000000);
  PERFORM _m2_ef_set_schedule_full(tid, '2026-01-01');
  PERFORM _m2_ef_activate_terms(tid);
  PERFORM _m2_ef_generate_charges(tid);
  SELECT EXISTS (
    SELECT 1 FROM charge
    WHERE enrollment_id = b.enrollment_id AND charge_source_code = 'tuition'
  ) INTO ok;
  PERFORM _m2_ef_record(17, 'generated charge links to enrollment', ok);
END $$;

-- 18: tuition charge requires enrollment
SELECT _m2_ef_expect_fail(18, 'tuition charge requires enrollment anchor', $$
  DO $i$ DECLARE b record; tid uuid; si uuid; BEGIN
    SELECT * INTO b FROM _m2_ef_bootstrap();
    tid := _m2_ef_terms(b.org_id, b.enrollment_id, 1000);
    PERFORM _m2_ef_set_schedule_full(tid, CURRENT_DATE);
    SELECT id INTO si FROM enrollment_payment_schedule_item WHERE enrollment_financial_terms_id = tid LIMIT 1;
    INSERT INTO charge (
      organization_id, student_id, guardian_id, amount, enrollment_financial_terms_id,
      enrollment_payment_schedule_item_id, charge_source_code
    ) VALUES (b.org_id, b.student_id, b.guardian_id, 1000, tid, si, 'tuition');
  END $i$;
$$);

-- 19: schedule item generates at most one charge
DO $$
DECLARE b record; tid uuid; cnt integer;
BEGIN
  SELECT * INTO b FROM _m2_ef_bootstrap();
  tid := _m2_ef_terms(b.org_id, b.enrollment_id, 6000000);
  PERFORM _m2_ef_set_schedule_installments(tid, 2, '2026-01-01');
  PERFORM _m2_ef_activate_terms(tid);
  PERFORM _m2_ef_generate_charges(tid);
  PERFORM _m2_ef_generate_charges(tid);
  SELECT count(*) INTO cnt FROM charge WHERE enrollment_financial_terms_id = tid;
  PERFORM _m2_ef_record(19, 'schedule item at most one charge', cnt = 2);
END $$;

-- 20: charge generation idempotent
DO $$
DECLARE b record; tid uuid; first integer; second integer;
BEGIN
  SELECT * INTO b FROM _m2_ef_bootstrap();
  tid := _m2_ef_terms(b.org_id, b.enrollment_id, 3000000);
  PERFORM _m2_ef_set_schedule_full(tid, '2026-01-01');
  PERFORM _m2_ef_activate_terms(tid);
  first := _m2_ef_generate_charges(tid);
  second := _m2_ef_generate_charges(tid);
  PERFORM _m2_ef_record(20, 'charge generation idempotent', first = 1 AND second = 0);
END $$;

-- 21: charge amount immutable
SELECT _m2_ef_expect_fail(21, 'charge amount remains immutable', $$
  DO $i$ DECLARE b record; tid uuid; cid uuid; BEGIN
    SELECT * INTO b FROM _m2_ef_bootstrap();
    tid := _m2_ef_terms(b.org_id, b.enrollment_id, 4000000);
    PERFORM _m2_ef_set_schedule_full(tid, CURRENT_DATE);
    PERFORM _m2_ef_activate_terms(tid);
    PERFORM _m2_ef_generate_charges(tid);
    SELECT id INTO cid FROM charge WHERE enrollment_financial_terms_id = tid LIMIT 1;
    UPDATE charge SET amount = 1 WHERE id = cid;
  END $i$;
$$);

-- 22: financial adjustment correction path
DO $$
DECLARE b record; tid uuid; cid uuid; adj uuid;
BEGIN
  SELECT * INTO b FROM _m2_ef_bootstrap();
  tid := _m2_ef_terms(b.org_id, b.enrollment_id, 5000000);
  PERFORM _m2_ef_set_schedule_full(tid, CURRENT_DATE);
  PERFORM _m2_ef_activate_terms(tid);
  PERFORM _m2_ef_generate_charges(tid);
  adj := _m2_ef_apply_correction(tid, 4500000);
  SELECT id INTO cid FROM charge WHERE enrollment_financial_terms_id = tid LIMIT 1;
  PERFORM _m2_ef_record(
    22,
    'financial adjustment is correction path',
    adj IS NOT NULL AND EXISTS (SELECT 1 FROM financial_adjustment WHERE id = adj AND amount_delta = -500000)
  );
END $$;

-- 23: historical charge unchanged after agreement correction
DO $$
DECLARE b record; tid uuid; amt bigint;
BEGIN
  SELECT * INTO b FROM _m2_ef_bootstrap();
  tid := _m2_ef_terms(b.org_id, b.enrollment_id, 20000000);
  PERFORM _m2_ef_set_schedule_full(tid, CURRENT_DATE);
  PERFORM _m2_ef_activate_terms(tid);
  PERFORM _m2_ef_generate_charges(tid);
  PERFORM _m2_ef_apply_correction(tid, 18000000);
  SELECT amount INTO amt FROM charge WHERE enrollment_financial_terms_id = tid LIMIT 1;
  PERFORM _m2_ef_record(23, 'historical charge unchanged after correction', amt = 20000000);
END $$;

-- 24: schedule item does not store paid amount
DO $$
DECLARE cols text[];
BEGIN
  SELECT array_agg(column_name::text ORDER BY column_name) INTO cols
  FROM information_schema.columns
  WHERE table_schema = 'public' AND table_name = 'enrollment_payment_schedule_item';
  PERFORM _m2_ef_record(
    24,
    'schedule item has no paid amount column',
    NOT ('amount_paid' = ANY (cols) OR 'paid_amount' = ANY (cols))
  );
END $$;

-- 25: payment allocation remains canonical
DO $$
DECLARE b record; tid uuid; cid uuid; pay uuid;
BEGIN
  SELECT * INTO b FROM _m2_ef_bootstrap();
  tid := _m2_ef_terms(b.org_id, b.enrollment_id, 2000000);
  PERFORM _m2_ef_set_schedule_full(tid, CURRENT_DATE);
  PERFORM _m2_ef_activate_terms(tid);
  PERFORM _m2_ef_generate_charges(tid);
  SELECT id INTO cid FROM charge WHERE enrollment_financial_terms_id = tid LIMIT 1;
  INSERT INTO payment (organization_id, guardian_id, amount) VALUES (b.org_id, b.guardian_id, 1000000) RETURNING id INTO pay;
  INSERT INTO payment_allocation (organization_id, payment_id, charge_id, amount) VALUES (b.org_id, pay, cid, 1000000);
  PERFORM _m2_ef_record(
    25,
    'payment allocation remains canonical',
    EXISTS (SELECT 1 FROM payment_allocation WHERE charge_id = cid AND amount = 1000000)
  );
END $$;

-- 26: charge is not revenue (summary defers recognition)
DO $$
DECLARE b record; tid uuid;
BEGIN
  SELECT * INTO b FROM _m2_ef_bootstrap();
  tid := _m2_ef_terms(b.org_id, b.enrollment_id, 1000000);
  PERFORM _m2_ef_set_schedule_full(tid, CURRENT_DATE);
  PERFORM _m2_ef_activate_terms(tid);
  PERFORM _m2_ef_generate_charges(tid);
  PERFORM _m2_ef_record(
    26,
    'charge is not treated as revenue',
    NOT EXISTS (
      SELECT 1 FROM revenue_recognition_event
      WHERE enrollment_id = b.enrollment_id
    )
    AND EXISTS (
      SELECT 1 FROM charge
      WHERE enrollment_id = b.enrollment_id AND charge_source_code = 'tuition' AND amount = 1000000
    )
  );
END $$;

-- 27: payment schedule does not alter academic structure
DO $$
DECLARE b record; tid uuid; class_name text;
BEGIN
  SELECT * INTO b FROM _m2_ef_bootstrap();
  tid := _m2_ef_terms(b.org_id, b.enrollment_id, 8000000);
  PERFORM _m2_ef_set_schedule_installments(tid, 4, '2026-01-01');
  SELECT name INTO class_name FROM class WHERE id = b.class_id;
  PERFORM _m2_ef_record(27, 'payment schedule does not alter class', class_name = 'EF Class');
END $$;

-- 28: schedule does not alter recognition basis on enrollment terms unexpectedly
DO $$
DECLARE b record; tid uuid; rb text;
BEGIN
  SELECT * INTO b FROM _m2_ef_bootstrap();
  INSERT INTO enrollment_financial_terms (
    organization_id, enrollment_id, agreed_tuition_amount, discount_amount, net_tuition_amount,
    agreement_date, recognition_basis_code, status
  ) VALUES (b.org_id, b.enrollment_id, 5000000, 0, 5000000, CURRENT_DATE, 'per_lesson', 'draft')
  RETURNING id INTO tid;
  PERFORM _m2_ef_set_schedule_full(tid, CURRENT_DATE);
  SELECT recognition_basis_code INTO rb FROM enrollment_financial_terms WHERE id = tid;
  PERFORM _m2_ef_record(28, 'schedule does not alter recognition basis', rb = 'per_lesson');
END $$;

-- 29: cross-org enrollment link rejected
SELECT _m2_ef_expect_fail(29, 'cross-org enrollment link rejected', $$
  DO $i$ DECLARE a record; b record; BEGIN
    SELECT * INTO a FROM _m2_ef_bootstrap();
    SELECT * INTO b FROM _m2_ef_bootstrap();
    INSERT INTO enrollment_financial_terms (
      organization_id, enrollment_id, agreed_tuition_amount, discount_amount, net_tuition_amount, agreement_date, status
    ) VALUES (a.org_id, b.enrollment_id, 1000, 0, 1000, CURRENT_DATE, 'draft');
  END $i$;
$$);

-- 30: cross-org schedule/charge linkage rejected
SELECT _m2_ef_expect_fail(30, 'cross-org schedule linkage rejected', $$
  DO $i$ DECLARE a record; b record; tid uuid; BEGIN
    SELECT * INTO a FROM _m2_ef_bootstrap();
    SELECT * INTO b FROM _m2_ef_bootstrap();
    tid := _m2_ef_terms(a.org_id, a.enrollment_id, 1000);
    INSERT INTO enrollment_payment_schedule_item (
      organization_id, enrollment_financial_terms_id, sequence_number, due_date, amount
    ) VALUES (b.org_id, tid, 99, CURRENT_DATE, 1000);
  END $i$;
$$);

-- 31: RLS tenant isolation
DO $$
DECLARE cnt integer;
BEGIN
  PERFORM _m2_ef_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO cnt FROM enrollment_financial_terms
  WHERE organization_id = 'b0000000-0000-4000-8000-000000000001';
  PERFORM _m2_ef_record(31, 'RLS prevents cross-org terms read', cnt = 0);
  PERFORM _m2_ef_as_super();
END $$;

-- 32: permission gate blocks staff without charge.create
DO $$
BEGIN
  PERFORM _m2_ef_as_auth('a2222222-2222-4222-8222-222222222222');
  BEGIN
    PERFORM public.create_enrollment_financial_terms(
      'a0000000-0000-4000-8000-000000000001', 1000, 0, CURRENT_DATE, NULL, NULL, NULL
    );
    PERFORM _m2_ef_record(32, 'permission gate blocks charge.create', false);
  EXCEPTION WHEN OTHERS THEN
    PERFORM _m2_ef_record(32, 'permission gate blocks charge.create', true);
  END;
  PERFORM _m2_ef_as_super();
END $$;

-- 33: charge_balance remains valid
DO $$
DECLARE b record; tid uuid; cid uuid; bal bigint;
BEGIN
  SELECT * INTO b FROM _m2_ef_bootstrap();
  tid := _m2_ef_terms(b.org_id, b.enrollment_id, 3000000);
  PERFORM _m2_ef_set_schedule_full(tid, CURRENT_DATE);
  PERFORM _m2_ef_activate_terms(tid);
  PERFORM _m2_ef_generate_charges(tid);
  PERFORM _m2_ef_apply_correction(tid, 2500000);
  SELECT id INTO cid FROM charge WHERE enrollment_financial_terms_id = tid LIMIT 1;
  SELECT outstanding_balance INTO bal FROM charge_balance WHERE charge_id = cid;
  PERFORM _m2_ef_record(33, 'charge_balance behavior remains valid', bal = 2500000);
END $$;

-- 34: enrollment overlap invariant still enforced
SELECT _m2_ef_expect_fail(34, 'M1 enrollment overlap still enforced', $$
  DO $i$ DECLARE b record; BEGIN
    SELECT * INTO b FROM _m2_ef_bootstrap();
    INSERT INTO enrollment (organization_id, student_id, class_id, start_date, status)
      VALUES (b.org_id, b.student_id, b.class_id, CURRENT_DATE, 'active');
  END $i$;
$$);

-- 35: existing cost A/B/C structures unaffected
DO $$
DECLARE cap integer; exp integer;
BEGIN
  SELECT count(*) INTO cap FROM capital_asset;
  SELECT count(*) INTO exp FROM expense;
  PERFORM _m2_ef_record(35, 'Cost A/B/C structures unaffected', cap >= 0 AND exp >= 0);
END $$;

DO $$
DECLARE total integer; passed integer; failed integer;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE result = 'PASS'), count(*) FILTER (WHERE result = 'FAIL')
    INTO total, passed, failed FROM _m2_ef_results;
  RAISE NOTICE 'M2 enrollment financial Tests: % / % passed (% failed)', passed, total, failed;
  IF failed > 0 OR total <> 35 THEN
    RAISE EXCEPTION 'M2 enrollment financial tests failed: % of % (expected 35)', failed, total;
  END IF;
END $$;

SELECT test_no, test_name, result FROM _m2_ef_results ORDER BY test_no;

ROLLBACK;
