-- M0-T03 integrity verification: 25 scenarios
-- Run after migrations + seed on a disposable database.

BEGIN;

CREATE TEMP TABLE _m0_test_results (
  test_no   integer PRIMARY KEY,
  test_name text NOT NULL,
  result    text NOT NULL CHECK (result IN ('PASS', 'FAIL'))
);

CREATE OR REPLACE FUNCTION _m0_record(test_no integer, test_name text, passed boolean)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  INSERT INTO _m0_test_results (test_no, test_name, result)
  VALUES (test_no, test_name, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END);
END;
$$;

CREATE OR REPLACE FUNCTION _m0_expect_fail(test_no integer, test_name text, sql_text text)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  BEGIN
    EXECUTE sql_text;
    PERFORM _m0_record(test_no, test_name, false);
  EXCEPTION WHEN OTHERS THEN
    PERFORM _m0_record(test_no, test_name, true);
  END;
END;
$$;

-- =============================================================================
DO $$
DECLARE
  org_a uuid := gen_random_uuid();
  org_b uuid := gen_random_uuid();
  g1 uuid; s1 uuid; s2 uuid;
  sg1 uuid; sg2 uuid;
BEGIN
  INSERT INTO organization (id, name) VALUES (org_a, 'Test Org A'), (org_b, 'Test Org B');
  INSERT INTO guardian (organization_id, given_name, family_name) VALUES (org_a, 'Lan', 'Nguyen') RETURNING id INTO g1;
  INSERT INTO student (organization_id, given_name, family_name) VALUES (org_a, 'An', 'Nguyen') RETURNING id INTO s1;
  INSERT INTO student (organization_id, given_name, family_name) VALUES (org_a, 'Binh', 'Nguyen') RETURNING id INTO s2;
  INSERT INTO student_guardian (organization_id, student_id, guardian_id, relationship_type, is_billing_contact)
    VALUES (org_a, s1, g1, 'mother', true), (org_a, s2, g1, 'mother', true);
  PERFORM _m0_record(1, 'one guardian two students', (SELECT count(*) = 2 FROM student_guardian WHERE guardian_id = g1));
END $$;

DO $$
DECLARE
  org uuid := gen_random_uuid();
  s uuid; gm uuid; gf uuid;
BEGIN
  INSERT INTO organization (id, name) VALUES (org, 'Test Org');
  INSERT INTO student (organization_id, given_name, family_name) VALUES (org, 'Child', 'Test') RETURNING id INTO s;
  INSERT INTO guardian (organization_id, given_name, family_name) VALUES (org, 'Mother', 'Test') RETURNING id INTO gm;
  INSERT INTO guardian (organization_id, given_name, family_name) VALUES (org, 'Father', 'Test') RETURNING id INTO gf;
  INSERT INTO student_guardian (organization_id, student_id, guardian_id, relationship_type)
    VALUES (org, s, gm, 'mother'), (org, s, gf, 'father');
  PERFORM _m0_record(2, 'one student two guardians', (SELECT count(*) = 2 FROM student_guardian WHERE student_id = s));
END $$;

DO $$
DECLARE
  org uuid := gen_random_uuid();
  course_id uuid; class_a uuid; class_b uuid; st uuid;
  enr_a uuid; enr_b uuid;
BEGIN
  INSERT INTO organization (id, name) VALUES (org, 'Transfer Test');
  INSERT INTO course (organization_id, code, name) VALUES (org, 'E1', 'English 1') RETURNING id INTO course_id;
  INSERT INTO class (organization_id, course_id, name) VALUES (org, course_id, 'Class A') RETURNING id INTO class_a;
  INSERT INTO class (organization_id, course_id, name) VALUES (org, course_id, 'Class B') RETURNING id INTO class_b;
  INSERT INTO student (organization_id, given_name, family_name) VALUES (org, 'Tran', 'Student') RETURNING id INTO st;
  INSERT INTO enrollment (organization_id, student_id, class_id, start_date, end_date, status)
    VALUES (org, st, class_a, '2026-01-01', '2026-02-28', 'transferred') RETURNING id INTO enr_a;
  INSERT INTO enrollment (organization_id, student_id, class_id, start_date, status)
    VALUES (org, st, class_b, '2026-03-01', 'active') RETURNING id INTO enr_b;
  PERFORM _m0_record(3, 'student transfer A to B', enr_a IS NOT NULL AND enr_b IS NOT NULL);
END $$;

DO $$
DECLARE
  org uuid := gen_random_uuid();
  course_id uuid; class_a uuid; st uuid;
  enr1 uuid; enr2 uuid;
BEGIN
  INSERT INTO organization (id, name) VALUES (org, 'Rejoin Test');
  INSERT INTO course (organization_id, code, name) VALUES (org, 'E1', 'English 1') RETURNING id INTO course_id;
  INSERT INTO class (organization_id, course_id, name) VALUES (org, course_id, 'Class A') RETURNING id INTO class_a;
  INSERT INTO student (organization_id, given_name, family_name) VALUES (org, 'Re', 'Join') RETURNING id INTO st;
  INSERT INTO enrollment (organization_id, student_id, class_id, start_date, end_date, status)
    VALUES (org, st, class_a, '2026-01-01', '2026-03-01', 'completed') RETURNING id INTO enr1;
  INSERT INTO enrollment (organization_id, student_id, class_id, start_date, status)
    VALUES (org, st, class_a, '2026-05-01', 'active') RETURNING id INTO enr2;
  PERFORM _m0_record(4, 'student rejoin same class', enr1 <> enr2);
END $$;

SELECT _m0_expect_fail(
  5,
  'overlapping enrollment rejected',
  $$
    DO $inner$
    DECLARE org uuid := gen_random_uuid(); c uuid; cl uuid; st uuid;
    BEGIN
      INSERT INTO organization (id, name) VALUES (org, 'Overlap');
      INSERT INTO course (organization_id, code, name) VALUES (org, 'E1', 'E1') RETURNING id INTO c;
      INSERT INTO class (organization_id, course_id, name) VALUES (org, c, 'C1') RETURNING id INTO cl;
      INSERT INTO student (organization_id, given_name, family_name) VALUES (org, 'Ov', 'Lap') RETURNING id INTO st;
      INSERT INTO enrollment (organization_id, student_id, class_id, start_date, end_date, status)
        VALUES (org, st, cl, '2026-01-01', '2026-06-01', 'active');
      INSERT INTO enrollment (organization_id, student_id, class_id, start_date, end_date, status)
        VALUES (org, st, cl, '2026-03-01', '2026-08-01', 'active');
    END $inner$;
  $$
);

DO $$
DECLARE
  org uuid := gen_random_uuid();
  course_id uuid; cl uuid; t1 uuid; t2 uuid;
  ses1 uuid; ses2 uuid;
BEGIN
  INSERT INTO organization (id, name) VALUES (org, 'Teacher History');
  INSERT INTO course (organization_id, code, name) VALUES (org, 'E1', 'E1') RETURNING id INTO course_id;
  INSERT INTO class (organization_id, course_id, name) VALUES (org, course_id, 'C1') RETURNING id INTO cl;
  INSERT INTO teacher (organization_id, given_name, family_name) VALUES (org, 'Teach', 'A') RETURNING id INTO t1;
  INSERT INTO teacher (organization_id, given_name, family_name) VALUES (org, 'Teach', 'B') RETURNING id INTO t2;
  INSERT INTO teaching_session (organization_id, class_id, teacher_id, scheduled_start_at, scheduled_end_at, status)
    VALUES (org, cl, t1, '2026-01-10 18:00+07', '2026-01-10 20:00+07', 'completed') RETURNING id INTO ses1;
  INSERT INTO teaching_session (organization_id, class_id, teacher_id, scheduled_start_at, scheduled_end_at, status)
    VALUES (org, cl, t2, '2026-03-10 18:00+07', '2026-03-10 20:00+07', 'completed') RETURNING id INTO ses2;
  PERFORM _m0_record(6, 'teacher change preserves old session', (
    (SELECT teacher_id FROM teaching_session WHERE id = ses1) = t1
    AND (SELECT teacher_id FROM teaching_session WHERE id = ses2) = t2
  ));
END $$;

SELECT _m0_expect_fail(
  7,
  'completed session teacher immutable',
  $$
    DO $inner$
    DECLARE org uuid := gen_random_uuid(); c uuid; cl uuid; t1 uuid; t2 uuid; ses uuid;
    BEGIN
      INSERT INTO organization (id, name) VALUES (org, 'SessLock');
      INSERT INTO course (organization_id, code, name) VALUES (org, 'E1', 'E1') RETURNING id INTO c;
      INSERT INTO class (organization_id, course_id, name) VALUES (org, c, 'C1') RETURNING id INTO cl;
      INSERT INTO teacher (organization_id, given_name, family_name) VALUES (org, 'A', 'T') RETURNING id INTO t1;
      INSERT INTO teacher (organization_id, given_name, family_name) VALUES (org, 'B', 'T') RETURNING id INTO t2;
      INSERT INTO teaching_session (organization_id, class_id, teacher_id, scheduled_start_at, scheduled_end_at, status)
        VALUES (org, cl, t1, '2026-01-10 18:00+07', '2026-01-10 20:00+07', 'completed') RETURNING id INTO ses;
      UPDATE teaching_session SET teacher_id = t2 WHERE id = ses;
    END $inner$;
  $$
);

SELECT _m0_expect_fail(
  8,
  'duplicate attendance rejected',
  $$
    DO $inner$
    DECLARE org uuid := gen_random_uuid(); c uuid; cl uuid; st uuid; t uuid; enr uuid; ses uuid;
    BEGIN
      INSERT INTO organization (id, name) VALUES (org, 'DupAtt');
      INSERT INTO course (organization_id, code, name) VALUES (org, 'E1', 'E1') RETURNING id INTO c;
      INSERT INTO class (organization_id, course_id, name) VALUES (org, c, 'C1') RETURNING id INTO cl;
      INSERT INTO student (organization_id, given_name, family_name) VALUES (org, 'St', 'U') RETURNING id INTO st;
      INSERT INTO teacher (organization_id, given_name, family_name) VALUES (org, 'Te', 'Ac') RETURNING id INTO t;
      INSERT INTO enrollment (organization_id, student_id, class_id, start_date, status)
        VALUES (org, st, cl, '2026-01-01', 'active') RETURNING id INTO enr;
      INSERT INTO teaching_session (organization_id, class_id, teacher_id, scheduled_start_at, scheduled_end_at, status)
        VALUES (org, cl, t, '2026-02-01 18:00+07', '2026-02-01 20:00+07', 'completed') RETURNING id INTO ses;
      INSERT INTO attendance (organization_id, teaching_session_id, enrollment_id, status) VALUES (org, ses, enr, 'present');
      INSERT INTO attendance (organization_id, teaching_session_id, enrollment_id, status) VALUES (org, ses, enr, 'absent');
    END $inner$;
  $$
);

SELECT _m0_expect_fail(
  9,
  'attendance wrong class context rejected',
  $$
    DO $inner$
    DECLARE org uuid := gen_random_uuid(); c uuid; cl1 uuid; cl2 uuid; st uuid; t uuid; enr uuid; ses uuid;
    BEGIN
      INSERT INTO organization (id, name) VALUES (org, 'AttCtx');
      INSERT INTO course (organization_id, code, name) VALUES (org, 'E1', 'E1') RETURNING id INTO c;
      INSERT INTO class (organization_id, course_id, name) VALUES (org, c, 'C1') RETURNING id INTO cl1;
      INSERT INTO class (organization_id, course_id, name) VALUES (org, c, 'C2') RETURNING id INTO cl2;
      INSERT INTO student (organization_id, given_name, family_name) VALUES (org, 'St', 'U') RETURNING id INTO st;
      INSERT INTO teacher (organization_id, given_name, family_name) VALUES (org, 'Te', 'Ac') RETURNING id INTO t;
      INSERT INTO enrollment (organization_id, student_id, class_id, start_date, status)
        VALUES (org, st, cl1, '2026-01-01', 'active') RETURNING id INTO enr;
      INSERT INTO teaching_session (organization_id, class_id, teacher_id, scheduled_start_at, scheduled_end_at, status)
        VALUES (org, cl2, t, '2026-02-01 18:00+07', '2026-02-01 20:00+07', 'completed') RETURNING id INTO ses;
      INSERT INTO attendance (organization_id, teaching_session_id, enrollment_id, status) VALUES (org, ses, enr, 'present');
    END $inner$;
  $$
);

DO $$
DECLARE
  org uuid := gen_random_uuid();
  c uuid; cl uuid; st uuid; t uuid; enr uuid;
  obs1 uuid; obs2 uuid;
BEGIN
  INSERT INTO organization (id, name) VALUES (org, 'ObsHistory');
  INSERT INTO course (organization_id, code, name) VALUES (org, 'E1', 'E1') RETURNING id INTO c;
  INSERT INTO class (organization_id, course_id, name) VALUES (org, c, 'C1') RETURNING id INTO cl;
  INSERT INTO student (organization_id, given_name, family_name) VALUES (org, 'St', 'U') RETURNING id INTO st;
  INSERT INTO teacher (organization_id, given_name, family_name) VALUES (org, 'Te', 'Ac') RETURNING id INTO t;
  INSERT INTO enrollment (organization_id, student_id, class_id, start_date, status)
    VALUES (org, st, cl, '2026-01-01', 'active') RETURNING id INTO enr;
  INSERT INTO teacher_observation (organization_id, enrollment_id, class_id, teacher_id, observed_at, status)
    VALUES (org, enr, cl, t, '2026-03-01', 'recorded') RETURNING id INTO obs1;
  INSERT INTO teacher_observation (organization_id, enrollment_id, class_id, teacher_id, observed_at, status)
    VALUES (org, enr, cl, t, '2026-04-01', 'recorded') RETURNING id INTO obs2;
  PERFORM _m0_record(10, 'multiple observations preserved', obs1 <> obs2);
END $$;

SELECT _m0_expect_fail(
  11,
  'duplicate observation indicator rejected',
  $$
    DO $inner$
    DECLARE org uuid := gen_random_uuid(); c uuid; cl uuid; st uuid; t uuid; enr uuid; obs uuid;
    BEGIN
      INSERT INTO organization (id, name) VALUES (org, 'DupInd');
      INSERT INTO course (organization_id, code, name) VALUES (org, 'E1', 'E1') RETURNING id INTO c;
      INSERT INTO class (organization_id, course_id, name) VALUES (org, c, 'C1') RETURNING id INTO cl;
      INSERT INTO student (organization_id, given_name, family_name) VALUES (org, 'St', 'U') RETURNING id INTO st;
      INSERT INTO teacher (organization_id, given_name, family_name) VALUES (org, 'Te', 'Ac') RETURNING id INTO t;
      INSERT INTO enrollment (organization_id, student_id, class_id, start_date, status)
        VALUES (org, st, cl, '2026-01-01', 'active') RETURNING id INTO enr;
      INSERT INTO teacher_observation (organization_id, enrollment_id, class_id, teacher_id, observed_at, status)
        VALUES (org, enr, cl, t, now(), 'recorded') RETURNING id INTO obs;
      INSERT INTO observation_rating (organization_id, teacher_observation_id, indicator_code, rating_code)
        VALUES (org, obs, 'concentration', 'low');
      INSERT INTO observation_rating (organization_id, teacher_observation_id, indicator_code, rating_code)
        VALUES (org, obs, 'concentration', 'high');
    END $inner$;
  $$
);

SELECT _m0_expect_fail(
  12,
  'finalized assessment result score immutable',
  $$
    DO $inner$
    DECLARE org uuid := gen_random_uuid(); c uuid; cl uuid; st uuid; enr uuid; a uuid; ar uuid;
    BEGIN
      INSERT INTO organization (id, name) VALUES (org, 'FinAR');
      INSERT INTO course (organization_id, code, name) VALUES (org, 'E1', 'E1') RETURNING id INTO c;
      INSERT INTO class (organization_id, course_id, name) VALUES (org, c, 'C1') RETURNING id INTO cl;
      INSERT INTO student (organization_id, given_name, family_name) VALUES (org, 'St', 'U') RETURNING id INTO st;
      INSERT INTO enrollment (organization_id, student_id, class_id, start_date, status)
        VALUES (org, st, cl, '2026-01-01', 'active') RETURNING id INTO enr;
      INSERT INTO assessment (organization_id, class_id, assessment_type_code, title, max_score, assessed_on, status)
        VALUES (org, cl, 'quiz', 'Q1', 20, '2026-02-01', 'open') RETURNING id INTO a;
      INSERT INTO assessment_result (organization_id, assessment_id, enrollment_id, raw_score, max_score, status, finalized_at)
        VALUES (org, a, enr, 16, 20, 'finalized', now()) RETURNING id INTO ar;
      UPDATE assessment_result SET raw_score = 18 WHERE id = ar;
    END $inner$;
  $$
);

DO $$
DECLARE
  org uuid := gen_random_uuid();
  st uuid; g uuid; enr uuid; ch uuid; pay uuid; bal bigint;
BEGIN
  INSERT INTO organization (id, name) VALUES (org, 'PartialPay');
  INSERT INTO student (organization_id, given_name, family_name) VALUES (org, 'St', 'U') RETURNING id INTO st;
  INSERT INTO guardian (organization_id, given_name, family_name) VALUES (org, 'Pa', 'Y') RETURNING id INTO g;
  INSERT INTO charge (organization_id, student_id, guardian_id, amount, due_date, status)
    VALUES (org, st, g, 200000, '2026-02-01', 'open') RETURNING id INTO ch;
  INSERT INTO payment (organization_id, guardian_id, amount) VALUES (org, g, 100000) RETURNING id INTO pay;
  INSERT INTO payment_allocation (organization_id, payment_id, charge_id, amount) VALUES (org, pay, ch, 100000);
  SELECT outstanding_balance INTO bal FROM charge_balance WHERE charge_id = ch;
  PERFORM _m0_record(13, 'partial payment works', bal = 100000);
END $$;

DO $$
DECLARE
  org uuid := gen_random_uuid();
  st uuid; g uuid; ch1 uuid; ch2 uuid; pay uuid;
  bal1 bigint; bal2 bigint;
BEGIN
  INSERT INTO organization (id, name) VALUES (org, 'MultiCh');
  INSERT INTO student (organization_id, given_name, family_name) VALUES (org, 'St', 'U') RETURNING id INTO st;
  INSERT INTO guardian (organization_id, given_name, family_name) VALUES (org, 'Pa', 'Y') RETURNING id INTO g;
  INSERT INTO charge (organization_id, student_id, guardian_id, amount) VALUES (org, st, g, 100000) RETURNING id INTO ch1;
  INSERT INTO charge (organization_id, student_id, guardian_id, amount) VALUES (org, st, g, 150000) RETURNING id INTO ch2;
  INSERT INTO payment (organization_id, guardian_id, amount) VALUES (org, g, 250000) RETURNING id INTO pay;
  INSERT INTO payment_allocation (organization_id, payment_id, charge_id, amount) VALUES (org, pay, ch1, 100000);
  INSERT INTO payment_allocation (organization_id, payment_id, charge_id, amount) VALUES (org, pay, ch2, 150000);
  SELECT outstanding_balance INTO bal1 FROM charge_balance WHERE charge_id = ch1;
  SELECT outstanding_balance INTO bal2 FROM charge_balance WHERE charge_id = ch2;
  PERFORM _m0_record(14, 'one payment multiple charges', bal1 = 0 AND bal2 = 0);
END $$;

DO $$
DECLARE
  org uuid := gen_random_uuid();
  st uuid; g uuid; ch uuid; pay1 uuid; pay2 uuid; bal bigint;
BEGIN
  INSERT INTO organization (id, name) VALUES (org, 'MultiPay');
  INSERT INTO student (organization_id, given_name, family_name) VALUES (org, 'St', 'U') RETURNING id INTO st;
  INSERT INTO guardian (organization_id, given_name, family_name) VALUES (org, 'Pa', 'Y') RETURNING id INTO g;
  INSERT INTO charge (organization_id, student_id, guardian_id, amount) VALUES (org, st, g, 200000) RETURNING id INTO ch;
  INSERT INTO payment (organization_id, guardian_id, amount) VALUES (org, g, 80000) RETURNING id INTO pay1;
  INSERT INTO payment (organization_id, guardian_id, amount) VALUES (org, g, 120000) RETURNING id INTO pay2;
  INSERT INTO payment_allocation (organization_id, payment_id, charge_id, amount) VALUES (org, pay1, ch, 80000);
  INSERT INTO payment_allocation (organization_id, payment_id, charge_id, amount) VALUES (org, pay2, ch, 120000);
  SELECT outstanding_balance INTO bal FROM charge_balance WHERE charge_id = ch;
  PERFORM _m0_record(15, 'multiple payments one charge', bal = 0);
END $$;

DO $$
DECLARE
  org uuid := gen_random_uuid();
  st uuid; g uuid; ch uuid; bal bigint;
BEGIN
  INSERT INTO organization (id, name) VALUES (org, 'Discount');
  INSERT INTO student (organization_id, given_name, family_name) VALUES (org, 'St', 'U') RETURNING id INTO st;
  INSERT INTO guardian (organization_id, given_name, family_name) VALUES (org, 'Pa', 'Y') RETURNING id INTO g;
  INSERT INTO charge (organization_id, student_id, guardian_id, amount) VALUES (org, st, g, 200000) RETURNING id INTO ch;
  INSERT INTO financial_adjustment (organization_id, charge_id, adjustment_type_code, amount_delta)
    VALUES (org, ch, 'discount', -100000);
  SELECT outstanding_balance INTO bal FROM charge_balance WHERE charge_id = ch;
  PERFORM _m0_record(16, 'negative discount reduces debt', bal = 100000);
END $$;

DO $$
DECLARE
  org uuid := gen_random_uuid();
  st uuid; g uuid; ch uuid; bal bigint;
BEGIN
  INSERT INTO organization (id, name) VALUES (org, 'Correction');
  INSERT INTO student (organization_id, given_name, family_name) VALUES (org, 'St', 'U') RETURNING id INTO st;
  INSERT INTO guardian (organization_id, given_name, family_name) VALUES (org, 'Pa', 'Y') RETURNING id INTO g;
  INSERT INTO charge (organization_id, student_id, guardian_id, amount) VALUES (org, st, g, 200000) RETURNING id INTO ch;
  INSERT INTO financial_adjustment (organization_id, charge_id, adjustment_type_code, amount_delta)
    VALUES (org, ch, 'correction', 50000);
  SELECT outstanding_balance INTO bal FROM charge_balance WHERE charge_id = ch;
  PERFORM _m0_record(17, 'positive correction increases debt', bal = 250000);
END $$;

SELECT _m0_expect_fail(
  18,
  'zero allocation rejected',
  $$
    DO $inner$
    DECLARE org uuid := gen_random_uuid(); st uuid; g uuid; ch uuid; pay uuid;
    BEGIN
      INSERT INTO organization (id, name) VALUES (org, 'ZeroAlloc');
      INSERT INTO student (organization_id, given_name, family_name) VALUES (org, 'St', 'U') RETURNING id INTO st;
      INSERT INTO guardian (organization_id, given_name, family_name) VALUES (org, 'Pa', 'Y') RETURNING id INTO g;
      INSERT INTO charge (organization_id, student_id, guardian_id, amount) VALUES (org, st, g, 100000) RETURNING id INTO ch;
      INSERT INTO payment (organization_id, guardian_id, amount) VALUES (org, g, 100000) RETURNING id INTO pay;
      INSERT INTO payment_allocation (organization_id, payment_id, charge_id, amount) VALUES (org, pay, ch, 0);
    END $inner$;
  $$
);

DO $$
DECLARE
  org uuid := gen_random_uuid();
  slots integer;
BEGIN
  INSERT INTO organization (id, name) VALUES (org, 'CostB');
  SELECT count(*) INTO slots FROM cost_group WHERE organization_id = org;
  PERFORM _m0_record(19, 'org has only group slots 1 and 2', slots = 2);
END $$;

SELECT _m0_expect_fail(
  20,
  'duplicate group slot rejected',
  $$
    INSERT INTO cost_group (organization_id, group_slot)
    SELECT id, 1 FROM organization LIMIT 1;
  $$
);

DO $$
DECLARE
  org uuid := gen_random_uuid();
  s1 smallint; s2 smallint;
BEGIN
  INSERT INTO organization (id, name) VALUES (org, 'BothSlots');
  SELECT group_slot INTO s1 FROM cost_group WHERE organization_id = org ORDER BY group_slot LIMIT 1;
  SELECT group_slot INTO s2 FROM cost_group WHERE organization_id = org ORDER BY group_slot DESC LIMIT 1;
  PERFORM _m0_record(21, 'initialized org has both slots', s1 = 1 AND s2 = 2);
END $$;

SELECT _m0_expect_fail(
  22,
  'used expense category cannot reparent',
  $$
    DO $inner$
    DECLARE org uuid := gen_random_uuid(); g1 uuid; g2 uuid; cat uuid;
    BEGIN
      INSERT INTO organization (id, name) VALUES (org, 'CatReparent');
      SELECT id INTO g1 FROM cost_group WHERE organization_id = org AND group_slot = 1;
      SELECT id INTO g2 FROM cost_group WHERE organization_id = org AND group_slot = 2;
      INSERT INTO expense_category (organization_id, cost_group_id, display_name)
        VALUES (org, g1, 'Supplies') RETURNING id INTO cat;
      INSERT INTO expense (organization_id, expense_category_id, cost_group_id, amount, incurred_date)
        VALUES (org, cat, g1, 50000, CURRENT_DATE);
      UPDATE expense_category SET cost_group_id = g2 WHERE id = cat;
    END $inner$;
  $$
);

SELECT _m0_expect_fail(
  23,
  'expense group category mismatch rejected',
  $$
    DO $inner$
    DECLARE org uuid := gen_random_uuid(); g1 uuid; g2 uuid; cat uuid;
    BEGIN
      INSERT INTO organization (id, name) VALUES (org, 'ExpMismatch');
      SELECT id INTO g1 FROM cost_group WHERE organization_id = org AND group_slot = 1;
      SELECT id INTO g2 FROM cost_group WHERE organization_id = org AND group_slot = 2;
      INSERT INTO expense_category (organization_id, cost_group_id, display_name)
        VALUES (org, g1, 'Supplies') RETURNING id INTO cat;
      INSERT INTO expense (organization_id, expense_category_id, cost_group_id, amount, incurred_date)
        VALUES (org, cat, g2, 50000, CURRENT_DATE);
    END $inner$;
  $$
);

SELECT _m0_expect_fail(
  24,
  'cross-organization enrollment rejected',
  $$
    DO $inner$
    DECLARE org_a uuid := gen_random_uuid(); org_b uuid := gen_random_uuid();
      st uuid; c uuid; cl uuid;
    BEGIN
      INSERT INTO organization (id, name) VALUES (org_a, 'A'), (org_b, 'B');
      INSERT INTO student (organization_id, given_name, family_name) VALUES (org_a, 'St', 'A') RETURNING id INTO st;
      INSERT INTO course (organization_id, code, name) VALUES (org_b, 'E1', 'E1') RETURNING id INTO c;
      INSERT INTO class (organization_id, course_id, name) VALUES (org_b, c, 'C1') RETURNING id INTO cl;
      INSERT INTO enrollment (organization_id, student_id, class_id, start_date, status)
        VALUES (org_a, st, cl, '2026-01-01', 'active');
    END $inner$;
  $$
);

SELECT _m0_expect_fail(
  25,
  'cross-organization finance rejected',
  $$
    DO $inner$
    DECLARE org_a uuid := gen_random_uuid(); org_b uuid := gen_random_uuid();
      st uuid; g uuid; ch uuid;
    BEGIN
      INSERT INTO organization (id, name) VALUES (org_a, 'A'), (org_b, 'B');
      INSERT INTO student (organization_id, given_name, family_name) VALUES (org_a, 'St', 'A') RETURNING id INTO st;
      INSERT INTO guardian (organization_id, given_name, family_name) VALUES (org_b, 'G', 'B') RETURNING id INTO g;
      INSERT INTO charge (organization_id, student_id, guardian_id, amount)
        VALUES (org_a, st, g, 100000) RETURNING id INTO ch;
    END $inner$;
  $$
);

-- =============================================================================
-- SUMMARY
-- =============================================================================
DO $$
DECLARE
  total integer;
  passed integer;
  failed integer;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE result = 'PASS'), count(*) FILTER (WHERE result = 'FAIL')
    INTO total, passed, failed
  FROM _m0_test_results;

  RAISE NOTICE 'M0 Integrity Tests: % / % passed (% failed)', passed, total, failed;

  IF failed > 0 THEN
    RAISE EXCEPTION 'M0 integrity tests failed: % of %', failed, total;
  END IF;

  IF total <> 25 THEN
    RAISE EXCEPTION 'Expected 25 tests, ran %', total;
  END IF;
END $$;

SELECT test_no, test_name, result FROM _m0_test_results ORDER BY test_no;

ROLLBACK;
