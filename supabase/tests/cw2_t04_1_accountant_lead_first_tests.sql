-- CW2-T04.1: canonical Accountant lead-first confirmation + confirm-scoped convert gate (18 scenarios)

CREATE TEMP TABLE IF NOT EXISTS _cw2_t041_results (
  test_no integer PRIMARY KEY,
  test_name text NOT NULL,
  result text NOT NULL CHECK (result IN ('PASS', 'FAIL'))
);
GRANT ALL ON TABLE _cw2_t041_results TO authenticated, anon;

CREATE OR REPLACE FUNCTION _cw2_t041_record(test_no integer, test_name text, passed boolean)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO _cw2_t041_results (test_no, test_name, result)
  VALUES (test_no, test_name, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END);
END;
$$;

CREATE OR REPLACE FUNCTION _cw2_t041_as_auth(p_auth uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE; SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', p_auth::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_auth::text, 'role', 'authenticated')::text, true);
END;
$$;

CREATE OR REPLACE FUNCTION _cw2_t041_as_postgres()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN RESET ROLE; SET LOCAL ROLE postgres; END;
$$;

-- Org with primary owner (setup only) + consultant + accountant (NOT primary owner)
CREATE OR REPLACE FUNCTION _cw2_t041_org_fixture(
  OUT org_id uuid,
  OUT owner_auth uuid,
  OUT consultant_auth uuid,
  OUT consultant_user uuid,
  OUT accountant_auth uuid,
  OUT accountant_user uuid
)
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM _cw2_t041_as_postgres();
  org_id := gen_random_uuid();
  INSERT INTO organization (id, name) VALUES (org_id, 'CW2 T04.1 Org');
  PERFORM public.initialize_organization_access_foundation(org_id);
  PERFORM public.initialize_organization_cw2_foundation(org_id);

  owner_auth := gen_random_uuid();
  consultant_auth := gen_random_uuid();
  accountant_auth := gen_random_uuid();

  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at, is_sso_user, is_anonymous)
  VALUES
    (owner_auth, (SELECT id FROM auth.instances LIMIT 1), 'authenticated', 'authenticated', 't041-own-' || org_id::text || '@olli.local', '', now(), now(), now(), false, false),
    (consultant_auth, (SELECT id FROM auth.instances LIMIT 1), 'authenticated', 'authenticated', 't041-cons-' || org_id::text || '@olli.local', '', now(), now(), now(), false, false),
    (accountant_auth, (SELECT id FROM auth.instances LIMIT 1), 'authenticated', 'authenticated', 't041-acct-' || org_id::text || '@olli.local', '', now(), now(), now(), false, false);

  PERFORM public.set_primary_owner_for_organization(
    org_id,
    public.test_fixture_insert_app_user(org_id, 't041-own-' || org_id::text || '@olli.local', 'T041 Owner', owner_auth)
  );
  consultant_user := public.test_fixture_insert_app_user(org_id, 't041-cons-' || org_id::text || '@olli.local', 'T041 Cons', consultant_auth);
  accountant_user := public.test_fixture_insert_app_user(org_id, 't041-acct-' || org_id::text || '@olli.local', 'T041 Acct', accountant_auth);

  INSERT INTO user_role (organization_id, user_id, role_id, effective_from, status)
  SELECT org_id, consultant_user, r.id, CURRENT_DATE, 'active'
  FROM role r WHERE r.organization_id = org_id AND r.canonical_code = 'consultant';

  INSERT INTO user_role (organization_id, user_id, role_id, effective_from, status)
  SELECT org_id, accountant_user, r.id, CURRENT_DATE, 'active'
  FROM role r WHERE r.organization_id = org_id AND r.canonical_code = 'accountant';

  PERFORM _cw2_t041_as_auth(owner_auth);
  PERFORM public.assign_consultant_operational_code(consultant_user);
  PERFORM _cw2_t041_as_postgres();
END;
$$;

CREATE OR REPLACE FUNCTION _cw2_t041_student_first_bundle(
  p_org uuid,
  OUT student_id uuid,
  OUT guardian_id uuid,
  OUT enrollment_id uuid,
  OUT terms_id uuid,
  OUT charge_id uuid
)
LANGUAGE plpgsql AS $$
DECLARE v_course uuid; v_class uuid;
BEGIN
  PERFORM _cw2_t041_as_postgres();
  INSERT INTO course (organization_id, code, name) VALUES (p_org, 'T41C', 'T041 Course') RETURNING id INTO v_course;
  INSERT INTO class (organization_id, course_id, name, status) VALUES (p_org, v_course, 'T041 Class', 'active') RETURNING id INTO v_class;
  INSERT INTO student (organization_id, given_name, family_name, date_of_birth, status)
    VALUES (p_org, 'T041', 'Student', '2017-06-01', 'active') RETURNING id INTO student_id;
  INSERT INTO guardian (organization_id, given_name, family_name, email)
    VALUES (p_org, 'T041', 'Guardian', 't041g@test.local') RETURNING id INTO guardian_id;
  INSERT INTO student_guardian (organization_id, student_id, guardian_id, is_primary_contact, is_billing_contact)
    VALUES (p_org, student_id, guardian_id, true, true);
  INSERT INTO enrollment (organization_id, student_id, class_id, start_date, status)
    VALUES (p_org, student_id, v_class, CURRENT_DATE, 'active') RETURNING id INTO enrollment_id;
  INSERT INTO enrollment_financial_terms (
    organization_id, enrollment_id, agreed_tuition_amount, discount_amount, net_tuition_amount, agreement_date, status
  ) VALUES (p_org, enrollment_id, 10000000, 0, 10000000, CURRENT_DATE, 'draft') RETURNING id INTO terms_id;
  INSERT INTO enrollment_payment_schedule_item (organization_id, enrollment_financial_terms_id, sequence_number, due_date, amount)
    VALUES (p_org, terms_id, 1, CURRENT_DATE, 10000000);
  UPDATE enrollment_financial_terms SET status = 'active' WHERE id = terms_id;
  INSERT INTO charge (
    organization_id, student_id, enrollment_id, guardian_id, enrollment_financial_terms_id,
    enrollment_payment_schedule_item_id, charge_source_code, amount, currency_code, charged_at, due_date, status,
    agreed_tuition_snapshot, net_tuition_snapshot
  )
  SELECT p_org, student_id, enrollment_id, guardian_id, terms_id, si.id, 'tuition', si.amount, 'VND', CURRENT_DATE, si.due_date, 'open', 10000000, 10000000
  FROM enrollment_payment_schedule_item si WHERE si.enrollment_financial_terms_id = terms_id
  RETURNING id INTO charge_id;
END;
$$;

CREATE OR REPLACE FUNCTION _cw2_t041_lead_first_bundle(
  p_org uuid,
  p_consultant_auth uuid,
  OUT lead_id uuid,
  OUT prospect_student_id uuid,
  OUT guardian_id uuid,
  OUT enrollment_id uuid,
  OUT terms_id uuid
)
LANGUAGE plpgsql AS $$
DECLARE
  v_course uuid; v_class uuid;
  v_cand uuid; v_contact uuid;
BEGIN
  PERFORM _cw2_t041_as_postgres();
  INSERT INTO student (organization_id, given_name, family_name, date_of_birth, status)
    VALUES (p_org, 'LeadFirst', 'Prospect', '2016-03-15', 'prospect') RETURNING id INTO prospect_student_id;
  INSERT INTO lead (organization_id, status) VALUES (p_org, 'qualified') RETURNING id INTO lead_id;
  INSERT INTO lead_candidate (organization_id, lead_id, given_name, family_name, date_of_birth, is_primary_candidate)
    VALUES (p_org, lead_id, 'LeadFirst', 'Prospect', '2016-03-15', true) RETURNING id INTO v_cand;
  INSERT INTO guardian (organization_id, given_name, family_name, phone, email, status)
    VALUES (p_org, 'LF', 'Guardian', '0900000041', 'lf-guardian@test.local', 'active') RETURNING id INTO guardian_id;
  INSERT INTO lead_contact (organization_id, lead_id, given_name, family_name, phone, is_primary_contact, is_billing_contact)
    VALUES (p_org, lead_id, 'LF', 'Guardian', '0900000041', true, true) RETURNING id INTO v_contact;

  PERFORM _cw2_t041_as_auth(p_consultant_auth);
  PERFORM public.resolve_lead_candidate_identity(v_cand, 'use_existing', prospect_student_id);
  PERFORM public.resolve_lead_contact_identity(v_contact, 'use_existing', guardian_id);

  PERFORM _cw2_t041_as_postgres();
  INSERT INTO course (organization_id, code, name)
    VALUES (p_org, 'T41L' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 4), 'T041 Lead Course') RETURNING id INTO v_course;
  INSERT INTO class (organization_id, course_id, name, status) VALUES (p_org, v_course, 'T041 Lead Class', 'active') RETURNING id INTO v_class;
  INSERT INTO student_guardian (organization_id, student_id, guardian_id, is_primary_contact, is_billing_contact)
    VALUES (p_org, prospect_student_id, guardian_id, true, true);
  INSERT INTO enrollment (organization_id, student_id, class_id, start_date, status)
    VALUES (p_org, prospect_student_id, v_class, CURRENT_DATE, 'active') RETURNING id INTO enrollment_id;
  INSERT INTO enrollment_financial_terms (
    organization_id, enrollment_id, agreed_tuition_amount, discount_amount, net_tuition_amount, agreement_date, status
  ) VALUES (p_org, enrollment_id, 10000000, 0, 10000000, CURRENT_DATE, 'draft') RETURNING id INTO terms_id;
  INSERT INTO enrollment_payment_schedule_item (organization_id, enrollment_financial_terms_id, sequence_number, due_date, amount)
    VALUES (p_org, terms_id, 1, CURRENT_DATE, 10000000);
  UPDATE enrollment_financial_terms SET status = 'active' WHERE id = terms_id;
  INSERT INTO charge (
    organization_id, student_id, enrollment_id, guardian_id, enrollment_financial_terms_id,
    enrollment_payment_schedule_item_id, charge_source_code, amount, currency_code, charged_at, due_date, status,
    agreed_tuition_snapshot, net_tuition_snapshot
  )
  SELECT p_org, prospect_student_id, enrollment_id, guardian_id, terms_id, si.id, 'tuition', si.amount, 'VND', CURRENT_DATE, si.due_date, 'open', 10000000, 10000000
  FROM enrollment_payment_schedule_item si WHERE si.enrollment_financial_terms_id = terms_id;
END;
$$;

-- 1: canonical accountant (non-owner) confirms student-first
DO $$
DECLARE f record; b record; v_decl uuid; r record;
BEGIN
  SELECT * INTO f FROM _cw2_t041_org_fixture();
  SELECT * INTO b FROM _cw2_t041_student_first_bundle(f.org_id);
  PERFORM _cw2_t041_as_auth(f.consultant_auth);
  v_decl := public.save_consultant_payment_declaration_draft(
    NULL, CURRENT_DATE, 3000000, 'deposit', NULL, b.student_id, NULL, NULL,
    b.enrollment_id, b.terms_id, b.guardian_id, 10000000, 't041-sf-1'
  );
  PERFORM public.submit_consultant_payment_declaration(v_decl);
  PERFORM _cw2_t041_as_auth(f.accountant_auth);
  r := public.confirm_consultant_payment_declaration(v_decl);
  PERFORM _cw2_t041_record(1, 'accountant student-first confirm', r.payment_id IS NOT NULL);
END $$;

-- 2: accountant lead-first confirm (M3 convert + payment + code)
DO $$
DECLARE f record; lf record; v_decl uuid; r record;
  v_students integer; v_conv integer;
BEGIN
  SELECT * INTO f FROM _cw2_t041_org_fixture();
  SELECT * INTO lf FROM _cw2_t041_lead_first_bundle(f.org_id, f.consultant_auth);
  PERFORM _cw2_t041_as_auth(f.consultant_auth);
  v_decl := public.save_consultant_payment_declaration_draft(
    NULL, CURRENT_DATE, 3000000, 'lead-first deposit', lf.lead_id, NULL, NULL, NULL,
    lf.enrollment_id, lf.terms_id, lf.guardian_id, 10000000, 't041-lf-1'
  );
  PERFORM public.submit_consultant_payment_declaration(v_decl);
  PERFORM _cw2_t041_as_auth(f.accountant_auth);
  r := public.confirm_consultant_payment_declaration(v_decl);
  PERFORM _cw2_t041_as_postgres();
  SELECT count(*) INTO v_students FROM student s
  WHERE s.organization_id = f.org_id AND s.given_name = 'LeadFirst' AND s.family_name = 'Prospect';
  SELECT count(*) INTO v_conv FROM lead_conversion WHERE lead_id = lf.lead_id AND organization_id = f.org_id;
  PERFORM _cw2_t041_record(2, 'accountant lead-first confirm', r.payment_id IS NOT NULL AND v_conv = 1);
  PERFORM _cw2_t041_record(3, 'lead-first exactly one student', v_students = 1);
  PERFORM _cw2_t041_record(4, 'lead-first official code at confirm', public._cw2_is_official_student_code(r.official_student_code));
  PERFORM _cw2_t041_record(5, 'lead-first declaration approved', (SELECT status FROM consultant_revenue_declaration WHERE id = v_decl) = 'approved');
END $$;

-- 6: accountant lacks general lead.convert
DO $$
DECLARE f record; lf record; ok boolean := false;
BEGIN
  SELECT * INTO f FROM _cw2_t041_org_fixture();
  SELECT * INTO lf FROM _cw2_t041_lead_first_bundle(f.org_id, f.consultant_auth);
  PERFORM _cw2_t041_as_auth(f.accountant_auth);
  PERFORM _cw2_t041_record(6, 'accountant has no lead.convert permission', public.has_permission('lead.convert') = false);
  BEGIN
    PERFORM public.convert_lead(lf.lead_id);
    ok := false;
  EXCEPTION WHEN OTHERS THEN ok := SQLERRM LIKE '%permission_denied%'; END;
  PERFORM _cw2_t041_record(7, 'accountant cannot convert_lead without confirm context', ok);
END $$;

-- 8–9: draft / rejected declaration cannot unlock convert via session
DO $$
DECLARE f record; lf record; v_decl uuid; ok_draft boolean := false; ok_rej boolean := false;
BEGIN
  SELECT * INTO f FROM _cw2_t041_org_fixture();
  SELECT * INTO lf FROM _cw2_t041_lead_first_bundle(f.org_id, f.consultant_auth);
  PERFORM _cw2_t041_as_auth(f.consultant_auth);
  v_decl := public.save_consultant_payment_declaration_draft(
    NULL, CURRENT_DATE, 1000000, 'x', lf.lead_id, NULL, NULL, NULL,
    lf.enrollment_id, lf.terms_id, lf.guardian_id, NULL, 't041-draft-gate'
  );
  PERFORM _cw2_t041_as_auth(f.accountant_auth);
  PERFORM set_config('cw2.declaration_confirm', v_decl::text, true);
  BEGIN
    PERFORM public.convert_lead(lf.lead_id);
    ok_draft := false;
  EXCEPTION WHEN OTHERS THEN ok_draft := SQLERRM LIKE '%permission_denied%'; END;

  PERFORM _cw2_t041_as_auth(f.consultant_auth);
  PERFORM public.submit_consultant_payment_declaration(v_decl);
  PERFORM _cw2_t041_as_auth(f.accountant_auth);
  PERFORM public.review_consultant_revenue_declaration(v_decl, 'reject', 'no');
  PERFORM set_config('cw2.declaration_confirm', v_decl::text, true);
  BEGIN
    PERFORM public.convert_lead(lf.lead_id);
    ok_rej := false;
  EXCEPTION WHEN OTHERS THEN ok_rej := SQLERRM LIKE '%permission_denied%'; END;

  PERFORM _cw2_t041_record(8, 'draft declaration cannot unlock convert', ok_draft);
  PERFORM _cw2_t041_record(9, 'rejected declaration cannot unlock convert', ok_rej);
END $$;

-- 10: wrong lead in confirm session
DO $$
DECLARE f record; lf1 record; lf2 record; v_decl uuid; ok boolean := false;
BEGIN
  SELECT * INTO f FROM _cw2_t041_org_fixture();
  SELECT * INTO lf1 FROM _cw2_t041_lead_first_bundle(f.org_id, f.consultant_auth);
  SELECT * INTO lf2 FROM _cw2_t041_lead_first_bundle(f.org_id, f.consultant_auth);
  PERFORM _cw2_t041_as_auth(f.consultant_auth);
  v_decl := public.save_consultant_payment_declaration_draft(
    NULL, CURRENT_DATE, 1000000, 'x', lf1.lead_id, NULL, NULL, NULL,
    lf1.enrollment_id, lf1.terms_id, lf1.guardian_id, NULL, 't041-wrong-lead'
  );
  PERFORM public.submit_consultant_payment_declaration(v_decl);
  PERFORM _cw2_t041_as_auth(f.accountant_auth);
  PERFORM set_config('cw2.declaration_confirm', v_decl::text, true);
  BEGIN
    PERFORM public.convert_lead(lf2.lead_id);
    ok := false;
  EXCEPTION WHEN OTHERS THEN ok := SQLERRM LIKE '%permission_denied%'; END;
  PERFORM _cw2_t041_record(10, 'confirm scope cannot convert unrelated lead', ok);
END $$;

-- 11: consultant cannot confirm
DO $$
DECLARE f record; b record; v_decl uuid; ok boolean := false;
BEGIN
  SELECT * INTO f FROM _cw2_t041_org_fixture();
  SELECT * INTO b FROM _cw2_t041_student_first_bundle(f.org_id);
  PERFORM _cw2_t041_as_auth(f.consultant_auth);
  v_decl := public.save_consultant_payment_declaration_draft(
    NULL, CURRENT_DATE, 1000000, 'x', NULL, b.student_id, NULL, NULL,
    b.enrollment_id, b.terms_id, b.guardian_id, NULL, 't041-cons-deny'
  );
  PERFORM public.submit_consultant_payment_declaration(v_decl);
  BEGIN
    PERFORM public.confirm_consultant_payment_declaration(v_decl);
    ok := false;
  EXCEPTION WHEN OTHERS THEN ok := SQLERRM LIKE '%permission_denied%'; END;
  PERFORM _cw2_t041_record(11, 'consultant cannot confirm', ok);
END $$;

-- 12: cross-org confirmation denied
DO $$
DECLARE f record; b record; v_decl uuid; ok boolean := false;
BEGIN
  SELECT * INTO f FROM _cw2_t041_org_fixture();
  SELECT * INTO b FROM _cw2_t041_student_first_bundle(f.org_id);
  PERFORM _cw2_t041_as_auth(f.consultant_auth);
  v_decl := public.save_consultant_payment_declaration_draft(
    NULL, CURRENT_DATE, 1000000, 'x', NULL, b.student_id, NULL, NULL,
    b.enrollment_id, b.terms_id, b.guardian_id, NULL, 't041-xorg'
  );
  PERFORM public.submit_consultant_payment_declaration(v_decl);
  IF EXISTS (SELECT 1 FROM app_user WHERE email = 'm5-consultant@olli.local') THEN
    PERFORM _cw2_t041_as_auth('a1111111-1111-4111-8111-111111111111');
    BEGIN
      PERFORM public.confirm_consultant_payment_declaration(v_decl);
      ok := false;
    EXCEPTION WHEN OTHERS THEN ok := true; END;
  ELSE ok := true; END IF;
  PERFORM _cw2_t041_record(12, 'cross-org confirmation denied', ok);
END $$;

-- 13: legacy_m5 cannot use CW2 confirm
DO $$
DECLARE f record; v_legacy uuid; ok boolean := false;
BEGIN
  SELECT * INTO f FROM _cw2_t041_org_fixture();
  PERFORM _cw2_t041_as_auth(f.consultant_auth);
  v_legacy := public.declare_consultant_revenue(CURRENT_DATE, 500000, 'legacy');
  PERFORM _cw2_t041_as_auth(f.accountant_auth);
  BEGIN
    PERFORM public.confirm_consultant_payment_declaration(v_legacy);
    ok := false;
  EXCEPTION WHEN OTHERS THEN ok := true; END;
  PERFORM _cw2_t041_record(13, 'legacy_m5 not CW2 confirm path', ok);
END $$;

-- 14: draft cannot confirm
DO $$
DECLARE f record; b record; v_decl uuid; ok boolean := false;
BEGIN
  SELECT * INTO f FROM _cw2_t041_org_fixture();
  SELECT * INTO b FROM _cw2_t041_student_first_bundle(f.org_id);
  PERFORM _cw2_t041_as_auth(f.consultant_auth);
  v_decl := public.save_consultant_payment_declaration_draft(
    NULL, CURRENT_DATE, 1000000, 'x', NULL, b.student_id, NULL, NULL,
    b.enrollment_id, b.terms_id, b.guardian_id, NULL, 't041-draft-confirm'
  );
  PERFORM _cw2_t041_as_auth(f.accountant_auth);
  BEGIN
    PERFORM public.confirm_consultant_payment_declaration(v_decl);
    ok := false;
  EXCEPTION WHEN OTHERS THEN ok := SQLERRM LIKE '%declaration_not_confirmable%'; END;
  PERFORM _cw2_t041_record(14, 'draft cannot confirm', ok);
END $$;

-- 15–16: lead-first idempotent retry
DO $$
DECLARE f record; lf record; v_decl uuid; r1 record; r2 record; v_pay integer;
BEGIN
  SELECT * INTO f FROM _cw2_t041_org_fixture();
  SELECT * INTO lf FROM _cw2_t041_lead_first_bundle(f.org_id, f.consultant_auth);
  PERFORM _cw2_t041_as_auth(f.consultant_auth);
  v_decl := public.save_consultant_payment_declaration_draft(
    NULL, CURRENT_DATE, 2500000, 'retry', lf.lead_id, NULL, NULL, NULL,
    lf.enrollment_id, lf.terms_id, lf.guardian_id, NULL, 't041-retry-lf'
  );
  PERFORM public.submit_consultant_payment_declaration(v_decl);
  PERFORM _cw2_t041_as_auth(f.accountant_auth);
  r1 := public.confirm_consultant_payment_declaration(v_decl);
  r2 := public.confirm_consultant_payment_declaration(v_decl);
  SELECT count(*) INTO v_pay FROM payment p
  JOIN consultant_revenue_declaration d ON d.approved_payment_id = p.id
  WHERE d.id = v_decl;
  PERFORM _cw2_t041_record(15, 'lead-first retry idempotent replay', r2.idempotent_replay);
  PERFORM _cw2_t041_record(16, 'lead-first retry one payment', v_pay = 1);
  PERFORM _cw2_t041_record(17, 'lead-first retry same official code', r1.official_student_code = r2.official_student_code);
END $$;

-- 18: invalid lead substitution on pending declaration fails atomically
DO $$
DECLARE f record; lf_ready record; v_bad_lead uuid; v_decl uuid;
  v_pay_before integer; v_pay_after integer; ok boolean := false;
BEGIN
  SELECT * INTO f FROM _cw2_t041_org_fixture();
  SELECT * INTO lf_ready FROM _cw2_t041_lead_first_bundle(f.org_id, f.consultant_auth);
  PERFORM _cw2_t041_as_postgres();
  INSERT INTO lead (organization_id, status) VALUES (f.org_id, 'qualified') RETURNING id INTO v_bad_lead;
  PERFORM _cw2_t041_as_auth(f.consultant_auth);
  v_decl := public.save_consultant_payment_declaration_draft(
    NULL, CURRENT_DATE, 1000000, 'tamper', lf_ready.lead_id, NULL, NULL, NULL,
    lf_ready.enrollment_id, lf_ready.terms_id, lf_ready.guardian_id, NULL, 't041-bad-lead'
  );
  PERFORM public.submit_consultant_payment_declaration(v_decl);
  PERFORM _cw2_t041_as_postgres();
  UPDATE consultant_revenue_declaration SET lead_id = v_bad_lead WHERE id = v_decl;
  SELECT count(*) INTO v_pay_before FROM payment WHERE organization_id = f.org_id;
  PERFORM _cw2_t041_as_auth(f.accountant_auth);
  BEGIN
    PERFORM public.confirm_consultant_payment_declaration(v_decl);
    ok := false;
  EXCEPTION WHEN OTHERS THEN ok := true; END;
  SELECT count(*) INTO v_pay_after FROM payment WHERE organization_id = f.org_id;
  PERFORM _cw2_t041_record(18, 'invalid lead substitution rolls back', ok AND v_pay_after = v_pay_before);
END $$;

DO $$
DECLARE v_fail integer; v_total integer;
BEGIN
  SELECT count(*) FILTER (WHERE result = 'FAIL'), count(*) INTO v_fail, v_total FROM _cw2_t041_results;
  IF v_fail > 0 THEN
    RAISE EXCEPTION 'CW2-T04.1 tests failed: % / % (%',
      v_fail, v_total,
      (SELECT string_agg(test_no::text || ':' || test_name, '; ') FROM _cw2_t041_results WHERE result = 'FAIL');
  END IF;
  RAISE NOTICE 'CW2-T04.1: all % tests passed', v_total;
END $$;
