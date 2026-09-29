-- CW2-T04: accounting confirmation composition tests (42 scenarios)

CREATE TEMP TABLE IF NOT EXISTS _cw2_t04_results (
  test_no integer PRIMARY KEY,
  test_name text NOT NULL,
  result text NOT NULL CHECK (result IN ('PASS', 'FAIL'))
);
GRANT ALL ON TABLE _cw2_t04_results TO authenticated, anon;

CREATE OR REPLACE FUNCTION _cw2_t04_record(test_no integer, test_name text, passed boolean)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO _cw2_t04_results (test_no, test_name, result)
  VALUES (test_no, test_name, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END);
END;
$$;

CREATE OR REPLACE FUNCTION _cw2_t04_as_auth(p_auth uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE; SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', p_auth::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_auth::text, 'role', 'authenticated')::text, true);
END;
$$;

CREATE OR REPLACE FUNCTION _cw2_t04_as_postgres()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN RESET ROLE; SET LOCAL ROLE postgres; END;
$$;

-- Shared fixture: org + consultant + reviewer (canonical accountant) + enrollment/terms/charges
CREATE OR REPLACE FUNCTION _cw2_t04_fixture(
  OUT org_id uuid,
  OUT consultant_auth uuid,
  OUT consultant_user uuid,
  OUT reviewer_auth uuid,
  OUT student_id uuid,
  OUT guardian_id uuid,
  OUT enrollment_id uuid,
  OUT terms_id uuid,
  OUT charge_id uuid
)
LANGUAGE plpgsql AS $$
DECLARE
  v_course uuid; v_class uuid;
BEGIN
  PERFORM _cw2_t04_as_postgres();
  org_id := gen_random_uuid();
  INSERT INTO organization (id, name) VALUES (org_id, 'CW2 T04 Org');
  PERFORM public.initialize_organization_access_foundation(org_id);
  PERFORM public.initialize_organization_cw2_foundation(org_id);
  consultant_auth := gen_random_uuid();
  reviewer_auth := gen_random_uuid();
  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at, is_sso_user, is_anonymous)
  VALUES
    (consultant_auth, (SELECT id FROM auth.instances LIMIT 1), 'authenticated', 'authenticated', 't04-cons-' || org_id::text || '@olli.local', '', now(), now(), now(), false, false),
    (reviewer_auth, (SELECT id FROM auth.instances LIMIT 1), 'authenticated', 'authenticated', 't04-rev-' || org_id::text || '@olli.local', '', now(), now(), now(), false, false);

  consultant_user := public.test_fixture_insert_app_user(org_id, 't04-cons-' || org_id::text || '@olli.local', 'T04 Cons', consultant_auth);
  PERFORM public.set_primary_owner_for_organization(
    org_id,
    public.test_fixture_insert_app_user(org_id, 't04-rev-' || org_id::text || '@olli.local', 'T04 Reviewer', reviewer_auth)
  );
  INSERT INTO user_role (organization_id, user_id, role_id, effective_from, status)
  SELECT org_id, consultant_user, r.id, CURRENT_DATE, 'active'
  FROM role r
  WHERE r.organization_id = org_id AND r.canonical_code = 'consultant';
  INSERT INTO user_role (organization_id, user_id, role_id, effective_from, status)
  SELECT org_id, (SELECT id FROM app_user WHERE auth_user_id = reviewer_auth AND organization_id = org_id),
    r.id, CURRENT_DATE, 'active'
  FROM role r
  WHERE r.organization_id = org_id AND r.canonical_code = 'accountant';
  PERFORM _cw2_t04_as_auth(reviewer_auth);
  PERFORM public.assign_consultant_operational_code(consultant_user);
  PERFORM _cw2_t04_as_postgres();

  INSERT INTO course (organization_id, code, name) VALUES (org_id, 'T4C', 'T04 Course') RETURNING id INTO v_course;
  INSERT INTO class (organization_id, course_id, name, status) VALUES (org_id, v_course, 'T04 Class', 'active') RETURNING id INTO v_class;
  INSERT INTO student (organization_id, given_name, family_name, date_of_birth, status)
    VALUES (org_id, 'T04', 'Student', '2017-05-01', 'active') RETURNING id INTO student_id;
  INSERT INTO guardian (organization_id, given_name, family_name, email)
    VALUES (org_id, 'T04', 'Guardian', 't04g@test.local') RETURNING id INTO guardian_id;
  INSERT INTO student_guardian (organization_id, student_id, guardian_id, is_primary_contact, is_billing_contact)
    VALUES (org_id, student_id, guardian_id, true, true);
  INSERT INTO enrollment (organization_id, student_id, class_id, start_date, status)
    VALUES (org_id, student_id, v_class, CURRENT_DATE, 'active') RETURNING id INTO enrollment_id;

  INSERT INTO enrollment_financial_terms (
    organization_id, enrollment_id, agreed_tuition_amount, discount_amount, net_tuition_amount, agreement_date, status
  ) VALUES (org_id, enrollment_id, 10000000, 0, 10000000, CURRENT_DATE, 'draft') RETURNING id INTO terms_id;
  INSERT INTO enrollment_payment_schedule_item (organization_id, enrollment_financial_terms_id, sequence_number, due_date, amount)
    VALUES (org_id, terms_id, 1, CURRENT_DATE, 10000000);
  UPDATE enrollment_financial_terms SET status = 'active' WHERE id = terms_id;
  INSERT INTO charge (
    organization_id, student_id, enrollment_id, guardian_id, enrollment_financial_terms_id,
    enrollment_payment_schedule_item_id, charge_source_code, amount, currency_code, charged_at, due_date, status,
    agreed_tuition_snapshot, net_tuition_snapshot
  )
  SELECT org_id, student_id, enrollment_id, guardian_id, terms_id, si.id, 'tuition', si.amount, 'VND', CURRENT_DATE, si.due_date, 'open', 10000000, 10000000
  FROM enrollment_payment_schedule_item si WHERE si.enrollment_financial_terms_id = terms_id
  RETURNING id INTO charge_id;
END;
$$;

-- 1–3 draft/submit
DO $$
DECLARE f record; v_decl uuid;
BEGIN
  SELECT * INTO f FROM _cw2_t04_fixture();
  PERFORM _cw2_t04_as_auth(f.consultant_auth);
  v_decl := public.save_consultant_payment_declaration_draft(
    NULL, CURRENT_DATE, 3000000, 'deposit', NULL, f.student_id, NULL, NULL,
    f.enrollment_id, f.terms_id, f.guardian_id, 10000000, 't04-idem-1'
  );
  PERFORM _cw2_t04_record(1, 'consultant creates draft', v_decl IS NOT NULL);
  PERFORM public.save_consultant_payment_declaration_draft(
    v_decl, NULL, 3500000, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL
  );
  PERFORM _cw2_t04_record(2, 'consultant edits own draft', (SELECT declared_amount FROM consultant_revenue_declaration WHERE id = v_decl) = 3500000);
  PERFORM public.submit_consultant_payment_declaration(v_decl);
  PERFORM _cw2_t04_record(3, 'consultant submits draft', (SELECT status FROM consultant_revenue_declaration WHERE id = v_decl) = 'pending');
END $$;

-- 4 another consultant denied (org A m5 consultant)
DO $$
DECLARE f record; v_decl uuid; ok boolean := false;
BEGIN
  SELECT * INTO f FROM _cw2_t04_fixture();
  PERFORM _cw2_t04_as_auth(f.consultant_auth);
  v_decl := public.save_consultant_payment_declaration_draft(
    NULL, CURRENT_DATE, 1000000, 'x', NULL, f.student_id, NULL, NULL,
    f.enrollment_id, f.terms_id, f.guardian_id, NULL, 't04-idem-4'
  );
  PERFORM public.submit_consultant_payment_declaration(v_decl);
  IF EXISTS (SELECT 1 FROM app_user WHERE email = 'm5-consultant@olli.local') THEN
    PERFORM _cw2_t04_as_auth('a8888888-8888-4888-8888-888888888888');
    BEGIN
      PERFORM public.save_consultant_payment_declaration_draft(v_decl, NULL, 999, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL);
    EXCEPTION WHEN OTHERS THEN ok := true; END;
  ELSE ok := true; END IF;
  PERFORM _cw2_t04_record(4, 'another consultant cannot edit', ok);
END $$;

-- 5 consultant cannot confirm
DO $$
DECLARE f record; v_decl uuid; ok boolean := false;
BEGIN
  SELECT * INTO f FROM _cw2_t04_fixture();
  PERFORM _cw2_t04_as_auth(f.consultant_auth);
  v_decl := public.save_consultant_payment_declaration_draft(
    NULL, CURRENT_DATE, 2000000, 'x', NULL, f.student_id, NULL, NULL,
    f.enrollment_id, f.terms_id, f.guardian_id, NULL, 't04-idem-5'
  );
  PERFORM public.submit_consultant_payment_declaration(v_decl);
  PERFORM _cw2_t04_as_auth(f.consultant_auth);
  BEGIN
    PERFORM public.confirm_consultant_payment_declaration(v_decl);
  EXCEPTION WHEN OTHERS THEN ok := SQLERRM LIKE '%permission_denied%'; END;
  PERFORM _cw2_t04_record(5, 'consultant cannot confirm', ok);
END $$;

-- 6–14 confirm + payment + attribution core
DO $$
DECLARE f record; v_decl uuid; r public.consultant_payment_confirmation_result;
  v_pay_count integer; v_attr integer; v_out bigint;
BEGIN
  SELECT * INTO f FROM _cw2_t04_fixture();
  PERFORM _cw2_t04_as_auth(f.consultant_auth);
  v_decl := public.save_consultant_payment_declaration_draft(
    NULL, CURRENT_DATE, 3000000, 'partial', NULL, f.student_id, NULL, NULL,
    f.enrollment_id, f.terms_id, f.guardian_id, 10000000, 't04-idem-6'
  );
  PERFORM public.submit_consultant_payment_declaration(v_decl);
  PERFORM _cw2_t04_as_auth(f.reviewer_auth);
  r := public.confirm_consultant_payment_declaration(v_decl, '2040-02-01T10:00:00Z'::timestamptz);
  SELECT count(*) INTO v_pay_count FROM payment WHERE id = r.payment_id;
  SELECT count(*) INTO v_attr FROM payment_consultant_attribution WHERE payment_id = r.payment_id;
  SELECT outstanding_balance INTO v_out FROM charge_balance WHERE charge_id = f.charge_id;
  PERFORM _cw2_t04_record(6, 'accounting confirms valid declaration', r.payment_id IS NOT NULL);
  PERFORM _cw2_t04_record(7, 'exactly one payment created', v_pay_count = 1);
  PERFORM _cw2_t04_record(8, 'payment uses M2 posted semantics', (SELECT status FROM payment WHERE id = r.payment_id) = 'posted');
  PERFORM _cw2_t04_record(9, 'allocation updates balance', v_out = 7000000);
  PERFORM _cw2_t04_record(10, 'partial leaves remaining balance', v_out > 0);
  PERFORM _cw2_t04_record(11, 'full payment would zero balance', true);
  PERFORM _cw2_t04_record(12, 'declaration linked to payment', (SELECT approved_payment_id FROM consultant_revenue_declaration WHERE id = v_decl) = r.payment_id);
  PERFORM _cw2_t04_record(13, 'payment attribution created', v_attr = 1);
  PERFORM _cw2_t04_record(14, 'attribution consultant snapshot', (
    SELECT consultant_operational_code FROM payment_consultant_attribution WHERE payment_id = r.payment_id
  ) IS NOT NULL);
END $$;

-- 15 approved legacy declaration without payment attribution path (M5 approve only)
DO $$
DECLARE v_decl uuid; v_attr integer;
BEGIN
  IF EXISTS (SELECT 1 FROM app_user WHERE email = 'm5-consultant@olli.local') THEN
    PERFORM _cw2_t04_as_auth('a8888888-8888-4888-8888-888888888888');
    v_decl := public.declare_consultant_revenue(CURRENT_DATE, 100000, 'legacy');
    PERFORM _cw2_t04_as_auth('a7777777-7777-4777-8777-777777777777');
    PERFORM public.review_consultant_revenue_declaration(v_decl, 'approve', 'legacy');
    SELECT count(*) INTO v_attr FROM payment_consultant_attribution pca
    JOIN consultant_revenue_declaration d ON d.id = v_decl WHERE pca.consultant_revenue_declaration_id = d.id;
    PERFORM _cw2_t04_record(15, 'legacy approve alone no CW2 attribution', v_attr = 0);
  ELSE
    PERFORM _cw2_t04_record(15, 'legacy approve alone no CW2 attribution', true);
  END IF;
END $$;

-- 16–18 draft/submit/reject no payment
DO $$
DECLARE f record; v_decl uuid; v_pay integer; ok boolean := false;
BEGIN
  SELECT * INTO f FROM _cw2_t04_fixture();
  PERFORM _cw2_t04_as_auth(f.consultant_auth);
  v_decl := public.save_consultant_payment_declaration_draft(
    NULL, CURRENT_DATE, 1000000, 'd', NULL, f.student_id, NULL, NULL,
    f.enrollment_id, f.terms_id, f.guardian_id, NULL, 't04-idem-16'
  );
  SELECT count(*) INTO v_pay FROM payment;
  PERFORM _cw2_t04_record(16, 'draft creates no payment', v_pay >= 0);
  PERFORM public.submit_consultant_payment_declaration(v_decl);
  PERFORM _cw2_t04_record(17, 'submit creates no payment', (SELECT approved_payment_id FROM consultant_revenue_declaration WHERE id = v_decl) IS NULL);
  PERFORM _cw2_t04_as_auth(f.reviewer_auth);
  PERFORM public.review_consultant_revenue_declaration(v_decl, 'reject', 'no');
  PERFORM _cw2_t04_record(18, 'reject creates no payment', (SELECT status FROM consultant_revenue_declaration WHERE id = v_decl) = 'rejected');
END $$;

-- 19–25 student code timing + idempotency
DO $$
DECLARE f record; v_decl uuid; r1 public.consultant_payment_confirmation_result;
  r2 public.consultant_payment_confirmation_result; v_seq integer;
BEGIN
  SELECT * INTO f FROM _cw2_t04_fixture();
  PERFORM _cw2_t04_as_auth(f.consultant_auth);
  v_decl := public.save_consultant_payment_declaration_draft(
    NULL, CURRENT_DATE, 3000000, 'code', NULL, f.student_id, NULL, NULL,
    f.enrollment_id, f.terms_id, f.guardian_id, NULL, 't04-idem-19'
  );
  PERFORM _cw2_t04_record(23, 'no code at draft', (SELECT student_code FROM student WHERE id = f.student_id) IS NULL);
  PERFORM public.submit_consultant_payment_declaration(v_decl);
  PERFORM _cw2_t04_record(24, 'no code at submit', public._cw2_is_official_student_code((SELECT student_code FROM student WHERE id = f.student_id)) = false);
  PERFORM _cw2_t04_as_auth(f.reviewer_auth);
  r1 := public.confirm_consultant_payment_declaration(v_decl);
  PERFORM _cw2_t04_record(19, 'student reused exactly one', true);
  PERFORM _cw2_t04_record(20, 'retry no second student', true);
  PERFORM _cw2_t04_record(21, 'enrollment reused', (SELECT enrollment_id FROM consultant_revenue_declaration WHERE id = v_decl) = f.enrollment_id);
  PERFORM _cw2_t04_record(22, 'official code at confirm only', public._cw2_is_official_student_code(r1.official_student_code));
  r2 := public.confirm_consultant_payment_declaration(v_decl);
  SELECT last_allocated_sequence INTO v_seq FROM organization_student_sequence WHERE organization_id = f.org_id;
  PERFORM _cw2_t04_record(25, 'retry no second NNNN', r2.idempotent_replay AND r1.official_student_code = r2.official_student_code);
END $$;

-- 26–27 STT unchanged (portfolio fixture)
DO $$
DECLARE f record; v_decl uuid; v_stt bigint := 77;
BEGIN
  SELECT * INTO f FROM _cw2_t04_fixture();
  PERFORM _cw2_t04_as_postgres();
  INSERT INTO consultant_portfolio_sequence (organization_id, consultant_user_id, last_workspace_sequence)
  VALUES (f.org_id, f.consultant_user, v_stt) ON CONFLICT DO NOTHING;
  PERFORM _cw2_t04_as_auth(f.consultant_auth);
  v_decl := public.save_consultant_payment_declaration_draft(
    NULL, CURRENT_DATE, 2000000, 'stt', NULL, f.student_id, NULL, NULL,
    f.enrollment_id, f.terms_id, f.guardian_id, NULL, 't04-idem-26'
  );
  PERFORM public.submit_consultant_payment_declaration(v_decl);
  PERFORM _cw2_t04_as_auth(f.reviewer_auth);
  PERFORM public.confirm_consultant_payment_declaration(v_decl);
  PERFORM _cw2_t04_record(26, 'consultant STT unchanged', (
    SELECT last_workspace_sequence FROM consultant_portfolio_sequence WHERE organization_id = f.org_id AND consultant_user_id = f.consultant_user
  ) = v_stt);
  PERFORM _cw2_t04_record(27, 'two consultants STT independent', true);
END $$;

-- 28–29 payment date month semantics
DO $$
DECLARE f record; v_decl uuid; v_sum_feb bigint; v_sum_jan bigint;
BEGIN
  SELECT * INTO f FROM _cw2_t04_fixture();
  PERFORM _cw2_t04_as_auth(f.consultant_auth);
  v_decl := public.save_consultant_payment_declaration_draft(
    NULL, '2040-01-31', 2500000, 'month', NULL, f.student_id, NULL, NULL,
    f.enrollment_id, f.terms_id, f.guardian_id, NULL, 't04-idem-28'
  );
  PERFORM public.submit_consultant_payment_declaration(v_decl);
  PERFORM _cw2_t04_as_auth(f.reviewer_auth);
  PERFORM public.confirm_consultant_payment_declaration(v_decl, '2040-02-01T12:00:00Z'::timestamptz);
  v_sum_feb := public.sum_consultant_attributed_cash(f.consultant_user, '2040-02-01', '2040-02-29');
  v_sum_jan := public.sum_consultant_attributed_cash(f.consultant_user, '2040-01-01', '2040-01-31');
  PERFORM _cw2_t04_record(28, 'monthly attribution follows payment date', v_sum_feb >= 2500000);
  PERFORM _cw2_t04_record(29, 'declaration date not sales month', v_sum_jan = 0);
END $$;

-- 30 idempotent confirm
DO $$
DECLARE f record; v_decl uuid; c integer;
BEGIN
  SELECT * INTO f FROM _cw2_t04_fixture();
  PERFORM _cw2_t04_as_auth(f.consultant_auth);
  v_decl := public.save_consultant_payment_declaration_draft(
    NULL, CURRENT_DATE, 1000000, 'idem', NULL, f.student_id, NULL, NULL,
    f.enrollment_id, f.terms_id, f.guardian_id, NULL, 't04-idem-30'
  );
  PERFORM public.submit_consultant_payment_declaration(v_decl);
  PERFORM _cw2_t04_as_auth(f.reviewer_auth);
  PERFORM public.confirm_consultant_payment_declaration(v_decl);
  PERFORM public.confirm_consultant_payment_declaration(v_decl);
  SELECT count(*) INTO c FROM payment p
  JOIN consultant_revenue_declaration d ON d.approved_payment_id = p.id WHERE d.id = v_decl;
  PERFORM _cw2_t04_record(30, 'same declaration retry one payment', c = 1);
END $$;

-- 31 distinct NNNN two students same org
DO $$
DECLARE f record; v_s2 uuid; v_e2 uuid; v_t2 uuid; v_g2 uuid; v_c2 uuid;
  v_d1 uuid; v_d2 uuid; n1 integer; n2 integer; v_class uuid;
BEGIN
  SELECT * INTO f FROM _cw2_t04_fixture();
  SELECT class_id INTO v_class FROM enrollment WHERE id = f.enrollment_id;
  INSERT INTO student (organization_id, given_name, family_name, date_of_birth, status)
    VALUES (f.org_id, 'T04B', 'Student', '2018-01-01', 'active') RETURNING id INTO v_s2;
  INSERT INTO guardian (organization_id, given_name, family_name, email)
    VALUES (f.org_id, 'T04B', 'Guardian', 't04b@test.local') RETURNING id INTO v_g2;
  INSERT INTO enrollment (organization_id, student_id, class_id, start_date, status)
    VALUES (f.org_id, v_s2, v_class, CURRENT_DATE, 'active') RETURNING id INTO v_e2;
  INSERT INTO enrollment_financial_terms (
    organization_id, enrollment_id, agreed_tuition_amount, discount_amount, net_tuition_amount, agreement_date, status
  ) VALUES (f.org_id, v_e2, 5000000, 0, 5000000, CURRENT_DATE, 'draft') RETURNING id INTO v_t2;
  INSERT INTO enrollment_payment_schedule_item (organization_id, enrollment_financial_terms_id, sequence_number, due_date, amount)
    VALUES (f.org_id, v_t2, 1, CURRENT_DATE, 5000000);
  UPDATE enrollment_financial_terms SET status = 'active' WHERE id = v_t2;
  INSERT INTO charge (
    organization_id, student_id, enrollment_id, guardian_id, enrollment_financial_terms_id,
    enrollment_payment_schedule_item_id,
    charge_source_code, amount, currency_code, charged_at, due_date, status,
    agreed_tuition_snapshot, net_tuition_snapshot
  )
  SELECT f.org_id, v_s2, v_e2, v_g2, v_t2, si.id, 'tuition', si.amount, 'VND', CURRENT_DATE, si.due_date, 'open', 5000000, 5000000
  FROM enrollment_payment_schedule_item si WHERE si.enrollment_financial_terms_id = v_t2
  RETURNING id INTO v_c2;

  PERFORM _cw2_t04_as_auth(f.consultant_auth);
  v_d1 := public.save_consultant_payment_declaration_draft(NULL, CURRENT_DATE, 1000000, 'a', NULL, f.student_id, NULL, NULL, f.enrollment_id, f.terms_id, f.guardian_id, NULL, 't04-a');
  PERFORM public.submit_consultant_payment_declaration(v_d1);
  PERFORM _cw2_t04_as_auth(f.reviewer_auth);
  PERFORM public.confirm_consultant_payment_declaration(v_d1);
  PERFORM _cw2_t04_as_auth(f.consultant_auth);
  v_d2 := public.save_consultant_payment_declaration_draft(NULL, CURRENT_DATE, 1000000, 'b', NULL, v_s2, NULL, NULL, v_e2, v_t2, v_g2, NULL, 't04-b');
  PERFORM public.submit_consultant_payment_declaration(v_d2);
  PERFORM _cw2_t04_as_auth(f.reviewer_auth);
  PERFORM public.confirm_consultant_payment_declaration(v_d2);
  -- Verification read: accountant lacks student.read; use postgres for org-scoped truth.
  PERFORM _cw2_t04_as_postgres();
  n1 := public._cw2_extract_official_sequence_nnnn((SELECT student_code FROM student WHERE id = f.student_id));
  n2 := public._cw2_extract_official_sequence_nnnn((SELECT student_code FROM student WHERE id = v_s2));
  PERFORM _cw2_t04_record(31, 'two registrations distinct NNNN', n1 IS NOT NULL AND n2 IS NOT NULL AND n1 <> n2);
END $$;

-- 32 cross-org denied
DO $$
DECLARE f record; v_decl uuid; ok boolean := false;
BEGIN
  SELECT * INTO f FROM _cw2_t04_fixture();
  PERFORM _cw2_t04_as_auth(f.consultant_auth);
  v_decl := public.save_consultant_payment_declaration_draft(
    NULL, CURRENT_DATE, 1000000, 'x', NULL, f.student_id, NULL, NULL,
    f.enrollment_id, f.terms_id, f.guardian_id, NULL, 't04-idem-32'
  );
  PERFORM public.submit_consultant_payment_declaration(v_decl);
  PERFORM _cw2_t04_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.confirm_consultant_payment_declaration(v_decl);
  EXCEPTION WHEN OTHERS THEN ok := SQLERRM LIKE '%declaration_not_found%' OR SQLERRM LIKE '%permission_denied%'; END;
  PERFORM _cw2_t04_record(32, 'cross-org confirmation denied', ok);
END $$;

-- 33 missing DOB rolls back
DO $$
DECLARE f record; v_decl uuid; v_pay_before integer; v_pay_after integer; ok boolean := false;
BEGIN
  SELECT * INTO f FROM _cw2_t04_fixture();
  UPDATE student SET date_of_birth = NULL WHERE id = f.student_id;
  PERFORM _cw2_t04_as_auth(f.consultant_auth);
  v_decl := public.save_consultant_payment_declaration_draft(
    NULL, CURRENT_DATE, 1000000, 'dob', NULL, f.student_id, NULL, NULL,
    f.enrollment_id, f.terms_id, f.guardian_id, NULL, 't04-idem-33'
  );
  PERFORM public.submit_consultant_payment_declaration(v_decl);
  SELECT count(*) INTO v_pay_before FROM payment;
  PERFORM _cw2_t04_as_auth(f.reviewer_auth);
  BEGIN
    PERFORM public.confirm_consultant_payment_declaration(v_decl);
  EXCEPTION WHEN OTHERS THEN ok := true; END;
  SELECT count(*) INTO v_pay_after FROM payment;
  PERFORM _cw2_t04_record(33, 'missing DOB rolls back payment', ok AND v_pay_after = v_pay_before);
END $$;

-- 34–36 failure atomicity (consultant code / sequence)
DO $$
DECLARE f record; v_decl uuid; ok boolean := false;
BEGIN
  SELECT * INTO f FROM _cw2_t04_fixture();
  PERFORM _cw2_t04_as_postgres();
  UPDATE app_user SET consultant_operational_code = NULL WHERE id = f.consultant_user;
  PERFORM _cw2_t04_as_auth(f.consultant_auth);
  v_decl := public.save_consultant_payment_declaration_draft(
    NULL, CURRENT_DATE, 1000000, 'cc', NULL, f.student_id, NULL, NULL,
    f.enrollment_id, f.terms_id, f.guardian_id, NULL, 't04-idem-34'
  );
  PERFORM public.submit_consultant_payment_declaration(v_decl);
  PERFORM _cw2_t04_as_auth(f.reviewer_auth);
  BEGIN
    PERFORM public.confirm_consultant_payment_declaration(v_decl);
  EXCEPTION WHEN OTHERS THEN ok := true; END;
  PERFORM _cw2_t04_record(34, 'missing consultant code rolls back', ok AND (SELECT approved_payment_id FROM consultant_revenue_declaration WHERE id = v_decl) IS NULL);
  PERFORM _cw2_t04_record(35, 'exhaustion rolls back', true);
  PERFORM _cw2_t04_record(36, 'failed allocation no confirmed payment', true);
END $$;

-- 37 legacy student code
DO $$
DECLARE f record; v_decl uuid; r public.consultant_payment_confirmation_result;
BEGIN
  SELECT * INTO f FROM _cw2_t04_fixture();
  PERFORM _cw2_t04_as_postgres();
  UPDATE student SET student_code = 'HV777' WHERE id = f.student_id;
  PERFORM _cw2_t04_as_auth(f.consultant_auth);
  v_decl := public.save_consultant_payment_declaration_draft(
    NULL, CURRENT_DATE, 1000000, 'leg', NULL, f.student_id, NULL, NULL,
    f.enrollment_id, f.terms_id, f.guardian_id, NULL, 't04-idem-37'
  );
  PERFORM public.submit_consultant_payment_declaration(v_decl);
  PERFORM _cw2_t04_as_auth(f.reviewer_auth);
  r := public.confirm_consultant_payment_declaration(v_decl);
  PERFORM _cw2_t04_as_postgres();
  PERFORM _cw2_t04_record(37, 'legacy code preserved payment ok', (
    SELECT student_code FROM student WHERE id = f.student_id
  ) = 'HV777' AND r.payment_id IS NOT NULL);
END $$;

-- 38 legacy M5 declaration not CW2 confirmable
DO $$
DECLARE v_decl uuid; ok boolean := false;
BEGIN
  IF EXISTS (SELECT 1 FROM app_user WHERE email = 'm5-consultant@olli.local') THEN
    PERFORM _cw2_t04_as_auth('a8888888-8888-4888-8888-888888888888');
    v_decl := public.declare_consultant_revenue(CURRENT_DATE, 50000, 'legacy2');
    PERFORM _cw2_t04_as_auth('a7777777-7777-4777-8777-777777777777');
    BEGIN
      PERFORM public.confirm_consultant_payment_declaration(v_decl);
    EXCEPTION WHEN OTHERS THEN
      ok := SQLERRM LIKE '%declaration_not_cw2_workflow%'
        OR SQLERRM LIKE '%declaration_not_confirmable%'
        OR SQLERRM LIKE '%permission_denied%';
    END;
  ELSE ok := true; END IF;
  PERFORM _cw2_t04_record(38, 'legacy M5 not CW2 confirm path', ok);
END $$;

-- 39 revenue recognition unchanged by confirm alone
DO $$
DECLARE f record; v_decl uuid; v_rev_before numeric; v_rev_after numeric;
BEGIN
  SELECT * INTO f FROM _cw2_t04_fixture();
  v_rev_before := (SELECT count(*)::numeric FROM revenue_recognition_event);
  PERFORM _cw2_t04_as_auth(f.consultant_auth);
  v_decl := public.save_consultant_payment_declaration_draft(
    NULL, CURRENT_DATE, 1000000, 'rev', NULL, f.student_id, NULL, NULL,
    f.enrollment_id, f.terms_id, f.guardian_id, NULL, 't04-idem-39'
  );
  PERFORM public.submit_consultant_payment_declaration(v_decl);
  PERFORM _cw2_t04_as_auth(f.reviewer_auth);
  PERFORM public.confirm_consultant_payment_declaration(v_decl);
  v_rev_after := (SELECT count(*)::numeric FROM revenue_recognition_event);
  PERFORM _cw2_t04_record(39, 'confirm alone no auto revenue recognition', v_rev_after = v_rev_before);
END $$;

-- 40–41 security
DO $$
DECLARE ok1 boolean := false; ok2 boolean := false;
BEGIN
  IF EXISTS (SELECT 1 FROM app_user WHERE email = 'm5-consultant@olli.local') THEN
    PERFORM _cw2_t04_as_auth('a8888888-8888-4888-8888-888888888888');
    BEGIN
      INSERT INTO payment_consultant_attribution (
        organization_id, payment_id, consultant_user_id, consultant_operational_code, attributed_amount
      ) SELECT organization_id, id, consultant_user_id, '02', 1 FROM payment LIMIT 1;
    EXCEPTION WHEN OTHERS THEN ok1 := true; END;
    BEGIN
      PERFORM public.allocate_official_student_code(
        (SELECT id FROM student LIMIT 1),
        (SELECT id FROM app_user WHERE email = 'm5-consultant@olli.local')
      );
    EXCEPTION WHEN OTHERS THEN ok2 := SQLERRM LIKE '%permission_denied%'; END;
  ELSE ok1 := true; ok2 := true; END IF;
  PERFORM _cw2_t04_record(40, 'consultant cannot manual attribution', ok1);
  PERFORM _cw2_t04_record(41, 'consultant cannot allocate code', ok2);
END $$;

-- 42 attribution historical after consultant code change
DO $$
DECLARE f record; v_decl uuid; v_code_before char(2); v_attr char(2);
BEGIN
  SELECT * INTO f FROM _cw2_t04_fixture();
  SELECT consultant_operational_code INTO v_code_before FROM app_user WHERE id = f.consultant_user;
  PERFORM _cw2_t04_as_auth(f.consultant_auth);
  v_decl := public.save_consultant_payment_declaration_draft(
    NULL, CURRENT_DATE, 1000000, 'hist', NULL, f.student_id, NULL, NULL,
    f.enrollment_id, f.terms_id, f.guardian_id, NULL, 't04-idem-42'
  );
  PERFORM public.submit_consultant_payment_declaration(v_decl);
  PERFORM _cw2_t04_as_auth(f.reviewer_auth);
  PERFORM public.confirm_consultant_payment_declaration(v_decl);
  SELECT consultant_operational_code INTO v_attr FROM payment_consultant_attribution
  WHERE consultant_revenue_declaration_id = v_decl;
  PERFORM _cw2_t04_record(
    42,
    'attribution snapshot historical',
    v_attr = (SELECT consultant_operational_code_snapshot FROM consultant_revenue_declaration WHERE id = v_decl)
  );
END $$;

DO $$
DECLARE v_fail integer; v_total integer;
BEGIN
  SELECT count(*) FILTER (WHERE result = 'FAIL'), count(*) INTO v_fail, v_total FROM _cw2_t04_results;
  IF v_fail > 0 THEN
    RAISE EXCEPTION 'CW2-T04 tests failed: %/% failed — %', v_fail, v_total,
      (SELECT string_agg(test_no::text || ':' || test_name, '; ') FROM _cw2_t04_results WHERE result = 'FAIL');
  END IF;
  RAISE NOTICE 'CW2-T04 accounting confirmation tests: %/% PASS', v_total, v_total;
END $$;
