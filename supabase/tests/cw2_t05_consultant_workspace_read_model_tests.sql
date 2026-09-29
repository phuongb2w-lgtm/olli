-- CW2-T05: consultant workspace portfolio read model (42 scenarios)

CREATE TEMP TABLE IF NOT EXISTS _cw2_t05_results (
  test_no integer PRIMARY KEY,
  test_name text NOT NULL,
  result text NOT NULL CHECK (result IN ('PASS', 'FAIL'))
);
GRANT ALL ON TABLE _cw2_t05_results TO authenticated, anon;

CREATE OR REPLACE FUNCTION _cw2_t05_record(test_no integer, test_name text, passed boolean)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO _cw2_t05_results (test_no, test_name, result)
  VALUES (test_no, test_name, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END);
END;
$$;

CREATE OR REPLACE FUNCTION _cw2_t05_as_auth(p_auth uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE; SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', p_auth::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_auth::text, 'role', 'authenticated')::text, true);
END;
$$;

CREATE OR REPLACE FUNCTION _cw2_t05_as_postgres()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN RESET ROLE; SET LOCAL ROLE postgres; END;
$$;

CREATE OR REPLACE FUNCTION _cw2_t05_seed_auth_user(p_auth uuid, p_email text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at, is_sso_user, is_anonymous
  )
  VALUES (
    p_auth,
    (SELECT id FROM auth.instances LIMIT 1),
    'authenticated',
    'authenticated',
    p_email,
    '',
    now(),
    now(),
    now(),
    false,
    false
  )
  ON CONFLICT (id) DO NOTHING;
END;
$$;

CREATE OR REPLACE FUNCTION _cw2_t05_org(
  OUT org_id uuid,
  OUT owner_auth uuid,
  OUT consultant_a_auth uuid,
  OUT consultant_a_user uuid,
  OUT consultant_b_auth uuid,
  OUT consultant_b_user uuid
)
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM _cw2_t05_as_postgres();
  org_id := gen_random_uuid();
  INSERT INTO organization (id, name) VALUES (org_id, 'CW2 T05 Org');
  PERFORM public.initialize_organization_access_foundation(org_id);
  PERFORM public.initialize_organization_cw2_foundation(org_id);

  owner_auth := gen_random_uuid();
  consultant_a_auth := gen_random_uuid();
  consultant_b_auth := gen_random_uuid();

  PERFORM _cw2_t05_seed_auth_user(owner_auth, 't05-own-' || org_id::text || '@olli.local');
  PERFORM _cw2_t05_seed_auth_user(consultant_a_auth, 't05-cons-a-' || org_id::text || '@olli.local');
  PERFORM _cw2_t05_seed_auth_user(consultant_b_auth, 't05-cons-b-' || org_id::text || '@olli.local');

  PERFORM public.set_primary_owner_for_organization(
    org_id,
    public.test_fixture_insert_app_user(org_id, 't05-own-' || org_id::text || '@olli.local', 'T05 Owner', owner_auth)
  );
  consultant_a_user := public.test_fixture_insert_app_user(
    org_id, 't05-cons-a-' || org_id::text || '@olli.local', 'T05 Cons A', consultant_a_auth
  );
  consultant_b_user := public.test_fixture_insert_app_user(
    org_id, 't05-cons-b-' || org_id::text || '@olli.local', 'T05 Cons B', consultant_b_auth
  );

  INSERT INTO user_role (organization_id, user_id, role_id, effective_from, status)
  SELECT org_id, consultant_a_user, r.id, CURRENT_DATE, 'active'
  FROM role r WHERE r.organization_id = org_id AND r.canonical_code = 'consultant';

  INSERT INTO user_role (organization_id, user_id, role_id, effective_from, status)
  SELECT org_id, consultant_b_user, r.id, CURRENT_DATE, 'active'
  FROM role r WHERE r.organization_id = org_id AND r.canonical_code = 'consultant';

  PERFORM _cw2_t05_as_auth(owner_auth);
  PERFORM public.assign_consultant_operational_code(consultant_a_user);
  PERFORM public.assign_consultant_operational_code(consultant_b_user);
  PERFORM _cw2_t05_as_postgres();
END;
$$;

CREATE OR REPLACE FUNCTION _cw2_t05_accountant_for_org(
  p_org uuid,
  OUT accountant_auth uuid,
  OUT accountant_user uuid
)
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM _cw2_t05_as_postgres();
  accountant_auth := gen_random_uuid();
  PERFORM _cw2_t05_seed_auth_user(accountant_auth, 't05-acct-' || p_org::text || '@olli.local');
  accountant_user := public.test_fixture_insert_app_user(
    p_org, 't05-acct-' || p_org::text || '@olli.local', 'T05 Acct', accountant_auth
  );
  INSERT INTO user_role (organization_id, user_id, role_id, effective_from, status)
  SELECT p_org, accountant_user, r.id, CURRENT_DATE, 'active'
  FROM role r WHERE r.organization_id = p_org AND r.canonical_code = 'accountant';
END;
$$;

CREATE OR REPLACE FUNCTION _cw2_t05_add_portfolio_entry(
  p_org uuid,
  p_consultant_user uuid,
  p_seq bigint,
  p_lead_id uuid DEFAULT NULL,
  p_student_id uuid DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE v_id uuid;
BEGIN
  PERFORM _cw2_t05_as_postgres();
  INSERT INTO consultant_portfolio_sequence (organization_id, consultant_user_id, last_workspace_sequence)
  VALUES (p_org, p_consultant_user, p_seq)
  ON CONFLICT (organization_id, consultant_user_id)
  DO UPDATE SET last_workspace_sequence = GREATEST(consultant_portfolio_sequence.last_workspace_sequence, p_seq);

  INSERT INTO consultant_portfolio_entry (
    organization_id, consultant_user_id, workspace_sequence, lead_id, student_id
  ) VALUES (p_org, p_consultant_user, p_seq, p_lead_id, p_student_id)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION _cw2_t05_student_with_finance(
  p_org uuid,
  p_consultant_auth uuid,
  OUT student_id uuid,
  OUT guardian_id uuid,
  OUT enrollment_id uuid,
  OUT terms_id uuid,
  OUT charge_id uuid,
  OUT course_id uuid,
  OUT class_id uuid
)
LANGUAGE plpgsql AS $$
DECLARE v_course uuid; v_class uuid;
BEGIN
  PERFORM _cw2_t05_as_postgres();
  INSERT INTO course (organization_id, code, name)
    VALUES (p_org, 'T5C' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 4), 'T05 Course')
    RETURNING id INTO v_course;
  course_id := v_course;
  INSERT INTO class (organization_id, course_id, name, status)
    VALUES (p_org, v_course, 'T05 Class', 'active') RETURNING id INTO v_class;
  class_id := v_class;
  INSERT INTO student (organization_id, given_name, family_name, date_of_birth, status)
    VALUES (p_org, 'Fin', 'Student', '2015-08-08', 'active') RETURNING id INTO student_id;
  INSERT INTO guardian (organization_id, given_name, family_name, email, phone)
    VALUES (p_org, 'Fin', 'Guardian', 't05-fin@test.local', '0905005005') RETURNING id INTO guardian_id;
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
  SELECT p_org, student_id, enrollment_id, guardian_id, terms_id, si.id, 'tuition', si.amount, 'VND',
    CURRENT_DATE, si.due_date, 'open', 10000000, 10000000
  FROM enrollment_payment_schedule_item si WHERE si.enrollment_financial_terms_id = terms_id
  RETURNING id INTO charge_id;
  PERFORM _cw2_t05_as_auth(p_consultant_auth);
END;
$$;

CREATE OR REPLACE FUNCTION _cw2_t05_confirm_partial(
  p_org uuid,
  p_consultant_auth uuid,
  p_student_id uuid,
  p_enrollment_id uuid,
  p_terms_id uuid,
  p_guardian_id uuid,
  p_amount numeric
)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_acct record; v_decl uuid;
BEGIN
  SELECT * INTO v_acct FROM _cw2_t05_accountant_for_org(p_org);
  PERFORM _cw2_t05_as_auth(p_consultant_auth);
  v_decl := public.save_consultant_payment_declaration_draft(
    NULL, CURRENT_DATE, p_amount, 't05 pay', NULL, p_student_id, NULL, NULL,
    p_enrollment_id, p_terms_id, p_guardian_id, 10000000, 't05-pay-' || gen_random_uuid()::text
  );
  PERFORM public.submit_consultant_payment_declaration(v_decl);
  PERFORM _cw2_t05_as_auth(v_acct.accountant_auth);
  PERFORM public.confirm_consultant_payment_declaration(v_decl);
END;
$$;

-- 1: own lead appears once
DO $$
DECLARE f record; v_lead uuid; v_cand uuid; r jsonb;
BEGIN
  SELECT * INTO f FROM _cw2_t05_org();
  PERFORM _cw2_t05_as_postgres();
  INSERT INTO lead (organization_id, status) VALUES (f.org_id, 'qualified') RETURNING id INTO v_lead;
  INSERT INTO lead_candidate (organization_id, lead_id, given_name, family_name, date_of_birth, is_primary_candidate)
    VALUES (f.org_id, v_lead, 'Lead', 'Once', '2016-01-01', true) RETURNING id INTO v_cand;
  PERFORM _cw2_t05_add_portfolio_entry(f.org_id, f.consultant_a_user, 1, v_lead, NULL);
  PERFORM _cw2_t05_as_auth(f.consultant_a_auth);
  r := public.list_consultant_workspace_portfolio();
  PERFORM _cw2_t05_record(
    1, 'own lead once',
    jsonb_array_length(r->'rows') = 1
    AND (r->'rows'->0->>'subject_type') = 'lead'
    AND (r->'rows'->0->>'lead_id')::uuid = v_lead
  );
END $$;

-- 2: lead converted keeps single portfolio row (same STT)
DO $$
DECLARE f record; v_lead uuid; v_student uuid; v_entry uuid; v_seq bigint := 7; r jsonb;
BEGIN
  SELECT * INTO f FROM _cw2_t05_org();
  PERFORM _cw2_t05_as_postgres();
  INSERT INTO lead (organization_id, status) VALUES (f.org_id, 'qualified') RETURNING id INTO v_lead;
  INSERT INTO student (organization_id, given_name, family_name, date_of_birth, status)
    VALUES (f.org_id, 'Conv', 'Single', '2014-04-04', 'active') RETURNING id INTO v_student;
  v_entry := _cw2_t05_add_portfolio_entry(f.org_id, f.consultant_a_user, v_seq, v_lead, NULL);
  UPDATE consultant_portfolio_entry
  SET student_id = v_student, lead_id = NULL
  WHERE id = v_entry;
  PERFORM _cw2_t05_as_auth(f.consultant_a_auth);
  r := public.list_consultant_workspace_portfolio();
  PERFORM _cw2_t05_record(
    2, 'converted single row',
    jsonb_array_length(r->'rows') = 1
    AND (r->'rows'->0->>'portfolio_entry_id')::uuid = v_entry
    AND (r->'rows'->0->>'workspace_sequence')::bigint = v_seq
    AND (r->'rows'->0->>'student_id')::uuid = v_student
  );
END $$;

-- 3: other consultant portfolio not listed
DO $$
DECLARE f record; b record; r jsonb;
BEGIN
  SELECT * INTO f FROM _cw2_t05_org();
  SELECT * INTO b FROM _cw2_t05_student_with_finance(f.org_id, f.consultant_b_auth);
  PERFORM _cw2_t05_add_portfolio_entry(f.org_id, f.consultant_b_user, 3, NULL, b.student_id);
  PERFORM _cw2_t05_as_auth(f.consultant_a_auth);
  r := public.list_consultant_workspace_portfolio();
  PERFORM _cw2_t05_record(3, 'other consultant hidden', jsonb_array_length(r->'rows') = 0);
END $$;

-- 4: cross org isolation
DO $$
DECLARE f record; f2 record; b record; r jsonb;
BEGIN
  SELECT * INTO f FROM _cw2_t05_org();
  SELECT * INTO f2 FROM _cw2_t05_org();
  SELECT * INTO b FROM _cw2_t05_student_with_finance(f2.org_id, f2.consultant_a_auth);
  PERFORM _cw2_t05_add_portfolio_entry(f2.org_id, f2.consultant_a_user, 4, NULL, b.student_id);
  PERFORM _cw2_t05_as_auth(f.consultant_a_auth);
  r := public.list_consultant_workspace_portfolio();
  PERFORM _cw2_t05_record(4, 'cross org', jsonb_array_length(r->'rows') = 0);
END $$;

-- 5: STT from workspace_sequence
DO $$
DECLARE f record; b record; r jsonb; v_seq bigint := 42;
BEGIN
  SELECT * INTO f FROM _cw2_t05_org();
  SELECT * INTO b FROM _cw2_t05_student_with_finance(f.org_id, f.consultant_a_auth);
  PERFORM _cw2_t05_add_portfolio_entry(f.org_id, f.consultant_a_user, v_seq, NULL, b.student_id);
  PERFORM _cw2_t05_as_auth(f.consultant_a_auth);
  r := public.list_consultant_workspace_portfolio();
  PERFORM _cw2_t05_record(
    5, 'STT',
    (r->'rows'->0->>'workspace_sequence')::bigint = v_seq
  );
END $$;

-- 6: default sort workspace_sequence desc
DO $$
DECLARE f record; r jsonb; s1 uuid; s2 uuid; s3 uuid;
BEGIN
  SELECT * INTO f FROM _cw2_t05_org();
  PERFORM _cw2_t05_as_postgres();
  INSERT INTO student (organization_id, given_name, family_name, date_of_birth, status)
    VALUES (f.org_id, 'S', 'One', '2010-01-01', 'active') RETURNING id INTO s1;
  INSERT INTO student (organization_id, given_name, family_name, date_of_birth, status)
    VALUES (f.org_id, 'S', 'Two', '2010-02-02', 'active') RETURNING id INTO s2;
  INSERT INTO student (organization_id, given_name, family_name, date_of_birth, status)
    VALUES (f.org_id, 'S', 'Three', '2010-03-03', 'active') RETURNING id INTO s3;
  PERFORM _cw2_t05_add_portfolio_entry(f.org_id, f.consultant_a_user, 1, NULL, s1);
  PERFORM _cw2_t05_add_portfolio_entry(f.org_id, f.consultant_a_user, 2, NULL, s2);
  PERFORM _cw2_t05_add_portfolio_entry(f.org_id, f.consultant_a_user, 3, NULL, s3);
  PERFORM _cw2_t05_as_auth(f.consultant_a_auth);
  r := public.list_consultant_workspace_portfolio();
  PERFORM _cw2_t05_record(
    6, 'default order desc',
    (r->'rows'->0->>'workspace_sequence')::bigint = 3
    AND (r->'rows'->1->>'workspace_sequence')::bigint = 2
    AND (r->'rows'->2->>'workspace_sequence')::bigint = 1
  );
END $$;

-- 7: STT stable after filter (not renumbered)
DO $$
DECLARE f record; r jsonb; s_active uuid; s_prospect uuid;
BEGIN
  SELECT * INTO f FROM _cw2_t05_org();
  PERFORM _cw2_t05_as_postgres();
  INSERT INTO student (organization_id, given_name, family_name, date_of_birth, status)
    VALUES (f.org_id, 'Pros', 'Pect', '2011-11-11', 'prospect') RETURNING id INTO s_prospect;
  SELECT student_id INTO s_active FROM _cw2_t05_student_with_finance(f.org_id, f.consultant_a_auth);
  PERFORM _cw2_t05_add_portfolio_entry(f.org_id, f.consultant_a_user, 11, NULL, s_prospect);
  PERFORM _cw2_t05_add_portfolio_entry(f.org_id, f.consultant_a_user, 22, NULL, s_active);
  PERFORM _cw2_t05_as_auth(f.consultant_a_auth);
  r := public.list_consultant_workspace_portfolio(
    jsonb_build_object('lifecycle_status', 'dang_hoc')
  );
  PERFORM _cw2_t05_record(
    7, 'STT stable after filter',
    jsonb_array_length(r->'rows') = 1
    AND (r->'rows'->0->>'workspace_sequence')::bigint = 22
  );
END $$;

-- 8: official student code
DO $$
DECLARE f record; b record; r jsonb; v_code text; v_cc char(2);
BEGIN
  SELECT * INTO f FROM _cw2_t05_org();
  SELECT * INTO b FROM _cw2_t05_student_with_finance(f.org_id, f.consultant_a_auth);
  PERFORM _cw2_t05_as_postgres();
  SELECT consultant_operational_code INTO v_cc FROM app_user WHERE id = f.consultant_a_user;
  v_code := v_cc || '15' || '0042';
  UPDATE student SET student_code = v_code WHERE id = b.student_id;
  PERFORM _cw2_t05_add_portfolio_entry(f.org_id, f.consultant_a_user, 8, NULL, b.student_id);
  PERFORM _cw2_t05_as_auth(f.consultant_a_auth);
  r := public.list_consultant_workspace_portfolio();
  PERFORM _cw2_t05_record(
    8, 'official code',
    (r->'rows'->0->>'student_code_official') = v_code
    AND (r->'rows'->0->>'student_code_display') = v_code
    AND (r->'rows'->0->>'student_code_is_provisional')::boolean = false
  );
END $$;

-- 9: provisional marked
DO $$
DECLARE f record; b record; r jsonb;
BEGIN
  SELECT * INTO f FROM _cw2_t05_org();
  SELECT * INTO b FROM _cw2_t05_student_with_finance(f.org_id, f.consultant_a_auth);
  PERFORM _cw2_t05_add_portfolio_entry(f.org_id, f.consultant_a_user, 9, NULL, b.student_id);
  PERFORM _cw2_t05_as_auth(f.consultant_a_auth);
  r := public.list_consultant_workspace_portfolio();
  PERFORM _cw2_t05_record(
    9, 'provisional marked',
    (r->'rows'->0->>'student_code_is_provisional')::boolean = true
    AND (r->'rows'->0->>'student_code_official') IS NULL
    AND (r->'rows'->0->>'student_code_display') IS NOT NULL
  );
END $$;

-- 10: provisional display not persisted on student row
DO $$
DECLARE f record; b record; r jsonb; v_persisted text;
BEGIN
  SELECT * INTO f FROM _cw2_t05_org();
  SELECT * INTO b FROM _cw2_t05_student_with_finance(f.org_id, f.consultant_a_auth);
  PERFORM _cw2_t05_add_portfolio_entry(f.org_id, f.consultant_a_user, 10, NULL, b.student_id);
  PERFORM _cw2_t05_as_auth(f.consultant_a_auth);
  r := public.list_consultant_workspace_portfolio();
  SELECT student_code INTO v_persisted FROM student WHERE id = b.student_id;
  PERFORM _cw2_t05_record(
    10, 'provisional not persisted',
    v_persisted IS NULL
    AND (r->'rows'->0->>'student_code_display') IS NOT NULL
  );
END $$;

-- 11: primary guardian surfaced
DO $$
DECLARE f record; b record; r jsonb;
BEGIN
  SELECT * INTO f FROM _cw2_t05_org();
  SELECT * INTO b FROM _cw2_t05_student_with_finance(f.org_id, f.consultant_a_auth);
  PERFORM _cw2_t05_add_portfolio_entry(f.org_id, f.consultant_a_user, 11, NULL, b.student_id);
  PERFORM _cw2_t05_as_auth(f.consultant_a_auth);
  r := public.list_consultant_workspace_portfolio();
  PERFORM _cw2_t05_record(
    11, 'primary guardian',
    (r->'rows'->0->>'primary_guardian_id')::uuid = b.guardian_id
    AND (r->'rows'->0->>'primary_guardian_phone') = '0905005005'
  );
END $$;

-- 12: no guardian
DO $$
DECLARE f record; r jsonb; v_student uuid;
BEGIN
  SELECT * INTO f FROM _cw2_t05_org();
  PERFORM _cw2_t05_as_postgres();
  INSERT INTO student (organization_id, given_name, family_name, date_of_birth, status)
    VALUES (f.org_id, 'No', 'Guardian', '2012-12-12', 'active') RETURNING id INTO v_student;
  PERFORM _cw2_t05_add_portfolio_entry(f.org_id, f.consultant_a_user, 12, NULL, v_student);
  PERFORM _cw2_t05_as_auth(f.consultant_a_auth);
  r := public.list_consultant_workspace_portfolio();
  PERFORM _cw2_t05_record(
    12, 'no guardian',
    (r->'rows'->0->>'primary_guardian_id') IS NULL
    AND (r->'rows'->0->>'primary_guardian_name') IS NULL
  );
END $$;

-- 13: tuition total net
DO $$
DECLARE f record; b record; r jsonb;
BEGIN
  SELECT * INTO f FROM _cw2_t05_org();
  SELECT * INTO b FROM _cw2_t05_student_with_finance(f.org_id, f.consultant_a_auth);
  PERFORM _cw2_t05_add_portfolio_entry(f.org_id, f.consultant_a_user, 13, NULL, b.student_id);
  PERFORM _cw2_t05_as_auth(f.consultant_a_auth);
  r := public.list_consultant_workspace_portfolio();
  PERFORM _cw2_t05_record(13, 'finance total net', (r->'rows'->0->>'tuition_total_net')::bigint = 10000000);
END $$;

-- 14: tuition paid after partial confirm
DO $$
DECLARE f record; b record; r jsonb;
BEGIN
  SELECT * INTO f FROM _cw2_t05_org();
  SELECT * INTO b FROM _cw2_t05_student_with_finance(f.org_id, f.consultant_a_auth);
  PERFORM _cw2_t05_add_portfolio_entry(f.org_id, f.consultant_a_user, 14, NULL, b.student_id);
  PERFORM _cw2_t05_confirm_partial(f.org_id, f.consultant_a_auth, b.student_id, b.enrollment_id, b.terms_id, b.guardian_id, 3000000);
  PERFORM _cw2_t05_as_auth(f.consultant_a_auth);
  r := public.list_consultant_workspace_portfolio();
  PERFORM _cw2_t05_record(14, 'finance paid partial', (r->'rows'->0->>'tuition_paid')::bigint = 3000000);
END $$;

-- 15: tuition outstanding
DO $$
DECLARE f record; b record; r jsonb;
BEGIN
  SELECT * INTO f FROM _cw2_t05_org();
  SELECT * INTO b FROM _cw2_t05_student_with_finance(f.org_id, f.consultant_a_auth);
  PERFORM _cw2_t05_add_portfolio_entry(f.org_id, f.consultant_a_user, 15, NULL, b.student_id);
  PERFORM _cw2_t05_confirm_partial(f.org_id, f.consultant_a_auth, b.student_id, b.enrollment_id, b.terms_id, b.guardian_id, 3000000);
  PERFORM _cw2_t05_as_auth(f.consultant_a_auth);
  r := public.list_consultant_workspace_portfolio();
  PERFORM _cw2_t05_record(15, 'finance outstanding', (r->'rows'->0->>'tuition_outstanding')::bigint = 7000000);
END $$;

-- 16: pending cw2 declaration => cho_xac_nhan
DO $$
DECLARE f record; b record; r jsonb; v_decl uuid;
BEGIN
  SELECT * INTO f FROM _cw2_t05_org();
  SELECT * INTO b FROM _cw2_t05_student_with_finance(f.org_id, f.consultant_a_auth);
  PERFORM _cw2_t05_add_portfolio_entry(f.org_id, f.consultant_a_user, 16, NULL, b.student_id);
  PERFORM _cw2_t05_as_auth(f.consultant_a_auth);
  v_decl := public.save_consultant_payment_declaration_draft(
    NULL, CURRENT_DATE, 2000000, 'pending', NULL, b.student_id, NULL, NULL,
    b.enrollment_id, b.terms_id, b.guardian_id, 10000000, 't05-pend-16'
  );
  PERFORM public.submit_consultant_payment_declaration(v_decl);
  r := public.list_consultant_workspace_portfolio();
  PERFORM _cw2_t05_record(
    16, 'pending cw2 cho_xac_nhan',
    (r->'rows'->0->>'tuition_payment_state') = 'cho_xac_nhan'
    AND (r->'rows'->0->>'declaration_status') = 'pending'
  );
END $$;

-- 17: legacy m5 pending does not force cho_xac_nhan
DO $$
DECLARE f record; b record; r jsonb;
BEGIN
  SELECT * INTO f FROM _cw2_t05_org();
  SELECT * INTO b FROM _cw2_t05_student_with_finance(f.org_id, f.consultant_a_auth);
  PERFORM _cw2_t05_add_portfolio_entry(f.org_id, f.consultant_a_user, 17, NULL, b.student_id);
  PERFORM _cw2_t05_as_auth(f.consultant_a_auth);
  PERFORM public.declare_consultant_revenue(CURRENT_DATE, 500000, 'legacy m5 pending');
  r := public.list_consultant_workspace_portfolio();
  PERFORM _cw2_t05_record(
    17, 'legacy m5 not cho_xac_nhan',
    (r->'rows'->0->>'tuition_payment_state') = 'dong_phi'
    AND (r->'rows'->0->>'declaration_status') IS NULL
  );
END $$;

-- 18: partial payment state mot_phan
DO $$
DECLARE f record; b record; r jsonb;
BEGIN
  SELECT * INTO f FROM _cw2_t05_org();
  SELECT * INTO b FROM _cw2_t05_student_with_finance(f.org_id, f.consultant_a_auth);
  PERFORM _cw2_t05_add_portfolio_entry(f.org_id, f.consultant_a_user, 18, NULL, b.student_id);
  PERFORM _cw2_t05_confirm_partial(f.org_id, f.consultant_a_auth, b.student_id, b.enrollment_id, b.terms_id, b.guardian_id, 4000000);
  PERFORM _cw2_t05_as_auth(f.consultant_a_auth);
  r := public.list_consultant_workspace_portfolio();
  PERFORM _cw2_t05_record(18, 'partial mot_phan', (r->'rows'->0->>'tuition_payment_state') = 'mot_phan');
END $$;

-- 19: full payment state full_phi
DO $$
DECLARE f record; b record; r jsonb;
BEGIN
  SELECT * INTO f FROM _cw2_t05_org();
  SELECT * INTO b FROM _cw2_t05_student_with_finance(f.org_id, f.consultant_a_auth);
  PERFORM _cw2_t05_add_portfolio_entry(f.org_id, f.consultant_a_user, 19, NULL, b.student_id);
  PERFORM _cw2_t05_confirm_partial(f.org_id, f.consultant_a_auth, b.student_id, b.enrollment_id, b.terms_id, b.guardian_id, 10000000);
  PERFORM _cw2_t05_as_auth(f.consultant_a_auth);
  r := public.list_consultant_workspace_portfolio();
  PERFORM _cw2_t05_record(
    19, 'full full_phi',
    (r->'rows'->0->>'tuition_payment_state') = 'full_phi'
    AND (r->'rows'->0->>'tuition_outstanding')::bigint = 0
  );
END $$;

-- 20: deposit_remainder with partial pay => coc_phi
DO $$
DECLARE
  f record; r jsonb;
  v_student uuid; v_guardian uuid; v_enrollment uuid; v_terms uuid;
  v_course uuid; v_class uuid;
BEGIN
  SELECT * INTO f FROM _cw2_t05_org();
  PERFORM _cw2_t05_as_postgres();
  INSERT INTO course (organization_id, code, name) VALUES (f.org_id, 'T5DEP', 'Deposit Course') RETURNING id INTO v_course;
  INSERT INTO class (organization_id, course_id, name, status) VALUES (f.org_id, v_course, 'Deposit Class', 'active') RETURNING id INTO v_class;
  INSERT INTO student (organization_id, given_name, family_name, date_of_birth, status)
    VALUES (f.org_id, 'Dep', 'Student', '2015-08-08', 'active') RETURNING id INTO v_student;
  INSERT INTO guardian (organization_id, given_name, family_name, email, phone)
    VALUES (f.org_id, 'Dep', 'Guardian', 't05-dep@test.local', '0905005020') RETURNING id INTO v_guardian;
  INSERT INTO student_guardian (organization_id, student_id, guardian_id, is_primary_contact, is_billing_contact)
    VALUES (f.org_id, v_student, v_guardian, true, true);
  INSERT INTO enrollment (organization_id, student_id, class_id, start_date, status)
    VALUES (f.org_id, v_student, v_class, CURRENT_DATE, 'active') RETURNING id INTO v_enrollment;
  INSERT INTO enrollment_financial_terms (
    organization_id, enrollment_id, agreed_tuition_amount, discount_amount, net_tuition_amount,
    agreement_date, status, payment_plan_mode
  ) VALUES (f.org_id, v_enrollment, 10000000, 0, 10000000, CURRENT_DATE, 'draft', 'deposit_remainder')
  RETURNING id INTO v_terms;
  INSERT INTO enrollment_payment_schedule_item (organization_id, enrollment_financial_terms_id, sequence_number, due_date, amount)
    VALUES
      (f.org_id, v_terms, 1, CURRENT_DATE, 2000000),
      (f.org_id, v_terms, 2, CURRENT_DATE + 30, 8000000);
  UPDATE enrollment_financial_terms SET status = 'active' WHERE id = v_terms;
  INSERT INTO charge (
    organization_id, student_id, enrollment_id, guardian_id, enrollment_financial_terms_id,
    enrollment_payment_schedule_item_id, charge_source_code, amount, currency_code, charged_at, due_date, status,
    agreed_tuition_snapshot, net_tuition_snapshot
  )
  SELECT f.org_id, v_student, v_enrollment, v_guardian, v_terms, si.id, 'tuition', si.amount, 'VND',
    CURRENT_DATE, si.due_date, 'open', 10000000, 10000000
  FROM enrollment_payment_schedule_item si WHERE si.enrollment_financial_terms_id = v_terms;
  PERFORM _cw2_t05_add_portfolio_entry(f.org_id, f.consultant_a_user, 20, NULL, v_student);
  PERFORM _cw2_t05_confirm_partial(f.org_id, f.consultant_a_auth, v_student, v_enrollment, v_terms, v_guardian, 2000000);
  PERFORM _cw2_t05_as_auth(f.consultant_a_auth);
  r := public.list_consultant_workspace_portfolio();
  PERFORM _cw2_t05_record(20, 'deposit coc_phi', (r->'rows'->0->>'tuition_payment_state') = 'coc_phi');
END $$;

-- 21: multi enrollment picks latest active
DO $$
DECLARE f record; b record; r jsonb; v_course2 uuid; v_class2 uuid; v_terms2 uuid;
BEGIN
  SELECT * INTO f FROM _cw2_t05_org();
  SELECT * INTO b FROM _cw2_t05_student_with_finance(f.org_id, f.consultant_a_auth);
  PERFORM _cw2_t05_as_postgres();
  INSERT INTO course (organization_id, code, name) VALUES (f.org_id, 'T5LATE', 'Later Course') RETURNING id INTO v_course2;
  INSERT INTO class (organization_id, course_id, name, status) VALUES (f.org_id, v_course2, 'Later Class', 'active') RETURNING id INTO v_class2;
  INSERT INTO enrollment (organization_id, student_id, class_id, start_date, status)
    VALUES (f.org_id, b.student_id, v_class2, CURRENT_DATE + 30, 'active');
  INSERT INTO enrollment_financial_terms (
    organization_id, enrollment_id, agreed_tuition_amount, discount_amount, net_tuition_amount, agreement_date, status
  )
  SELECT f.org_id, e.id, 5000000, 0, 5000000, CURRENT_DATE, 'draft'
  FROM enrollment e
  WHERE e.student_id = b.student_id AND e.class_id = v_class2
  RETURNING id INTO v_terms2;
  INSERT INTO enrollment_payment_schedule_item (organization_id, enrollment_financial_terms_id, sequence_number, due_date, amount)
    VALUES (f.org_id, v_terms2, 1, CURRENT_DATE + 30, 5000000);
  UPDATE enrollment_financial_terms SET status = 'active' WHERE id = v_terms2;
  PERFORM _cw2_t05_add_portfolio_entry(f.org_id, f.consultant_a_user, 21, NULL, b.student_id);
  PERFORM _cw2_t05_as_auth(f.consultant_a_auth);
  r := public.list_consultant_workspace_portfolio();
  PERFORM _cw2_t05_record(
    21, 'multi enrollment latest active',
    (r->'rows'->0->>'course_id')::uuid = v_course2
    AND (r->'rows'->0->>'enrollment_financial_terms_id')::uuid = v_terms2
  );
END $$;

-- 22: enrollment financial terms id returned
DO $$
DECLARE f record; b record; r jsonb;
BEGIN
  SELECT * INTO f FROM _cw2_t05_org();
  SELECT * INTO b FROM _cw2_t05_student_with_finance(f.org_id, f.consultant_a_auth);
  PERFORM _cw2_t05_add_portfolio_entry(f.org_id, f.consultant_a_user, 22, NULL, b.student_id);
  PERFORM _cw2_t05_as_auth(f.consultant_a_auth);
  r := public.list_consultant_workspace_portfolio();
  PERFORM _cw2_t05_record(
    22, 'terms id returned',
    (r->'rows'->0->>'enrollment_financial_terms_id')::uuid = b.terms_id
  );
END $$;

-- 23–25: declaration states draft / pending / approved
DO $$
DECLARE f record; b record; r jsonb; v_decl uuid; v_acct record;
BEGIN
  SELECT * INTO f FROM _cw2_t05_org();
  SELECT * INTO b FROM _cw2_t05_student_with_finance(f.org_id, f.consultant_a_auth);
  PERFORM _cw2_t05_add_portfolio_entry(f.org_id, f.consultant_a_user, 23, NULL, b.student_id);
  PERFORM _cw2_t05_as_auth(f.consultant_a_auth);
  v_decl := public.save_consultant_payment_declaration_draft(
    NULL, CURRENT_DATE, 1500000, 'draft', NULL, b.student_id, NULL, NULL,
    b.enrollment_id, b.terms_id, b.guardian_id, 10000000, 't05-draft-23'
  );
  r := public.list_consultant_workspace_portfolio();
  PERFORM _cw2_t05_record(23, 'declaration draft', (r->'rows'->0->>'declaration_status') = 'draft');

  PERFORM public.submit_consultant_payment_declaration(v_decl);
  r := public.list_consultant_workspace_portfolio();
  PERFORM _cw2_t05_record(24, 'declaration pending', (r->'rows'->0->>'declaration_status') = 'pending');

  SELECT * INTO v_acct FROM _cw2_t05_accountant_for_org(f.org_id);
  PERFORM _cw2_t05_as_auth(v_acct.accountant_auth);
  PERFORM public.confirm_consultant_payment_declaration(v_decl);
  PERFORM _cw2_t05_as_auth(f.consultant_a_auth);
  r := public.list_consultant_workspace_portfolio();
  PERFORM _cw2_t05_record(25, 'declaration approved', (r->'rows'->0->>'declaration_status') = 'approved');
END $$;

-- 26: can_add_payment false when full
DO $$
DECLARE f record; b record; r jsonb;
BEGIN
  SELECT * INTO f FROM _cw2_t05_org();
  SELECT * INTO b FROM _cw2_t05_student_with_finance(f.org_id, f.consultant_a_auth);
  PERFORM _cw2_t05_add_portfolio_entry(f.org_id, f.consultant_a_user, 26, NULL, b.student_id);
  PERFORM _cw2_t05_confirm_partial(f.org_id, f.consultant_a_auth, b.student_id, b.enrollment_id, b.terms_id, b.guardian_id, 10000000);
  PERFORM _cw2_t05_as_auth(f.consultant_a_auth);
  r := public.list_consultant_workspace_portfolio();
  PERFORM _cw2_t05_record(
    26, 'can_add_payment false when full',
    (r->'rows'->0->>'tuition_payment_state') = 'full_phi'
    AND (r->'rows'->0->'capabilities'->>'can_add_payment')::boolean = false
  );
END $$;

-- 27: hidden row omitted by default
DO $$
DECLARE f record; b record; r jsonb;
BEGIN
  SELECT * INTO f FROM _cw2_t05_org();
  SELECT * INTO b FROM _cw2_t05_student_with_finance(f.org_id, f.consultant_a_auth);
  PERFORM _cw2_t05_add_portfolio_entry(f.org_id, f.consultant_a_user, 27, NULL, b.student_id);
  PERFORM _cw2_t05_as_auth(f.consultant_a_auth);
  INSERT INTO consultant_grid_hidden_row (organization_id, app_user_id, subject_type, subject_id)
    VALUES (f.org_id, f.consultant_a_user, 'student', b.student_id)
  ON CONFLICT DO NOTHING;
  r := public.list_consultant_workspace_portfolio();
  PERFORM _cw2_t05_record(27, 'hidden omitted', jsonb_array_length(r->'rows') = 0);
END $$;

-- 28: include hidden surfaces row
DO $$
DECLARE f record; b record; r jsonb;
BEGIN
  SELECT * INTO f FROM _cw2_t05_org();
  SELECT * INTO b FROM _cw2_t05_student_with_finance(f.org_id, f.consultant_a_auth);
  PERFORM _cw2_t05_add_portfolio_entry(f.org_id, f.consultant_a_user, 28, NULL, b.student_id);
  PERFORM _cw2_t05_as_auth(f.consultant_a_auth);
  INSERT INTO consultant_grid_hidden_row (organization_id, app_user_id, subject_type, subject_id)
    VALUES (f.org_id, f.consultant_a_user, 'student', b.student_id)
  ON CONFLICT DO NOTHING;
  r := public.list_consultant_workspace_portfolio('{}'::jsonb, 'workspace_sequence', 'desc', 50, NULL, NULL, true);
  PERFORM _cw2_t05_record(
    28, 'include hidden',
    jsonb_array_length(r->'rows') = 1 AND (r->'rows'->0->>'is_hidden')::boolean = true
  );
END $$;

-- 29: other user hidden preference does not hide peer consultant row
DO $$
DECLARE f record; b record; r jsonb;
BEGIN
  SELECT * INTO f FROM _cw2_t05_org();
  SELECT * INTO b FROM _cw2_t05_student_with_finance(f.org_id, f.consultant_a_auth);
  PERFORM _cw2_t05_add_portfolio_entry(f.org_id, f.consultant_a_user, 29, NULL, b.student_id);
  PERFORM _cw2_t05_add_portfolio_entry(f.org_id, f.consultant_b_user, 30, NULL, b.student_id);
  PERFORM _cw2_t05_as_auth(f.consultant_a_auth);
  INSERT INTO consultant_grid_hidden_row (organization_id, app_user_id, subject_type, subject_id)
    VALUES (f.org_id, f.consultant_a_user, 'student', b.student_id)
  ON CONFLICT DO NOTHING;
  PERFORM _cw2_t05_as_auth(f.consultant_b_auth);
  r := public.list_consultant_workspace_portfolio();
  PERFORM _cw2_t05_record(
    29, 'other user hidden pref',
    jsonb_array_length(r->'rows') = 1 AND (r->'rows'->0->>'is_hidden')::boolean = false
  );
END $$;

-- 30: custom fields owner scoped in read model
DO $$
DECLARE f record; b record; r_a jsonb; r_b jsonb; v_def uuid;
BEGIN
  SELECT * INTO f FROM _cw2_t05_org();
  SELECT * INTO b FROM _cw2_t05_student_with_finance(f.org_id, f.consultant_a_auth);
  PERFORM _cw2_t05_add_portfolio_entry(f.org_id, f.consultant_a_user, 31, NULL, b.student_id);
  PERFORM _cw2_t05_add_portfolio_entry(f.org_id, f.consultant_b_user, 32, NULL, b.student_id);
  PERFORM _cw2_t05_as_auth(f.consultant_a_auth);
  INSERT INTO consultant_custom_field_definition (organization_id, owner_app_user_id, field_key, label, data_type)
    VALUES (f.org_id, f.consultant_a_user, 't05_note', 'Note', 'text')
    RETURNING id INTO v_def;
  INSERT INTO consultant_custom_field_value (organization_id, field_definition_id, subject_type, subject_id, value_text)
    VALUES (f.org_id, v_def, 'student', b.student_id, 'owner-only');
  r_a := public.list_consultant_workspace_portfolio();
  PERFORM _cw2_t05_as_auth(f.consultant_b_auth);
  r_b := public.list_consultant_workspace_portfolio();
  PERFORM _cw2_t05_record(
    30, 'custom fields owner scoped',
    jsonb_array_length(r_a->'rows'->0->'custom_fields') = 1
    AND jsonb_array_length(r_b->'rows'->0->'custom_fields') = 0
  );
END $$;

-- 31–36: filters
DO $$
DECLARE f record; b record; r jsonb; v_lead uuid;
BEGIN
  SELECT * INTO f FROM _cw2_t05_org();
  PERFORM _cw2_t05_as_postgres();
  INSERT INTO lead (organization_id, status) VALUES (f.org_id, 'qualified') RETURNING id INTO v_lead;
  INSERT INTO lead_candidate (organization_id, lead_id, given_name, family_name, date_of_birth, is_primary_candidate)
    VALUES (f.org_id, v_lead, 'Filter', 'Lead', '2013-03-03', true);
  PERFORM _cw2_t05_add_portfolio_entry(f.org_id, f.consultant_a_user, 40, v_lead, NULL);
  SELECT * INTO b FROM _cw2_t05_student_with_finance(f.org_id, f.consultant_a_auth);
  PERFORM _cw2_t05_add_portfolio_entry(f.org_id, f.consultant_a_user, 41, NULL, b.student_id);
  PERFORM _cw2_t05_as_auth(f.consultant_a_auth);

  r := public.list_consultant_workspace_portfolio(jsonb_build_object('lifecycle_status', 'tiem_nang'));
  PERFORM _cw2_t05_record(31, 'filter lifecycle_status', jsonb_array_length(r->'rows') = 1 AND (r->'rows'->0->>'subject_type') = 'lead');

  PERFORM _cw2_t05_confirm_partial(f.org_id, f.consultant_a_auth, b.student_id, b.enrollment_id, b.terms_id, b.guardian_id, 5000000);
  PERFORM _cw2_t05_as_auth(f.consultant_a_auth);
  r := public.list_consultant_workspace_portfolio(jsonb_build_object('tuition_payment_state', 'mot_phan'));
  PERFORM _cw2_t05_record(32, 'filter tuition_payment_state', jsonb_array_length(r->'rows') = 1);

  v_lead := public.save_consultant_payment_declaration_draft(
    NULL, CURRENT_DATE, 1000000, 'f', NULL, b.student_id, NULL, NULL,
    b.enrollment_id, b.terms_id, b.guardian_id, 10000000, 't05-filt-decl'
  );
  PERFORM public.submit_consultant_payment_declaration(v_lead);
  r := public.list_consultant_workspace_portfolio(jsonb_build_object('declaration_status', 'pending'));
  PERFORM _cw2_t05_record(33, 'filter declaration_status', jsonb_array_length(r->'rows') = 1);

  r := public.list_consultant_workspace_portfolio(jsonb_build_object('course_id', b.course_id::text));
  PERFORM _cw2_t05_record(34, 'filter course_id', jsonb_array_length(r->'rows') = 1);

  r := public.list_consultant_workspace_portfolio(jsonb_build_object('name_search', 'Student Fin'));
  PERFORM _cw2_t05_record(35, 'filter name_search', jsonb_array_length(r->'rows') = 1);

  r := public.list_consultant_workspace_portfolio(jsonb_build_object('guardian_phone', '0905005005'));
  PERFORM _cw2_t05_record(36, 'filter guardian_phone', jsonb_array_length(r->'rows') = 1);
END $$;

-- 37: invalid sort field
DO $$
DECLARE f record; ok boolean := false;
BEGIN
  SELECT * INTO f FROM _cw2_t05_org();
  PERFORM _cw2_t05_as_auth(f.consultant_a_auth);
  BEGIN
    PERFORM public.list_consultant_workspace_portfolio('{}'::jsonb, 'not_a_sort', 'desc');
    ok := false;
  EXCEPTION WHEN OTHERS THEN
    ok := SQLERRM LIKE '%invalid_sort_field%';
  END;
  PERFORM _cw2_t05_record(37, 'invalid sort', ok);
END $$;

-- 38: keyset pagination
DO $$
DECLARE f record; r1 jsonb; r2 jsonb; s1 uuid; s2 uuid; s3 uuid;
BEGIN
  SELECT * INTO f FROM _cw2_t05_org();
  PERFORM _cw2_t05_as_postgres();
  INSERT INTO student (organization_id, given_name, family_name, date_of_birth, status)
    VALUES (f.org_id, 'P', 'One', '2009-01-01', 'active') RETURNING id INTO s1;
  INSERT INTO student (organization_id, given_name, family_name, date_of_birth, status)
    VALUES (f.org_id, 'P', 'Two', '2009-02-02', 'active') RETURNING id INTO s2;
  INSERT INTO student (organization_id, given_name, family_name, date_of_birth, status)
    VALUES (f.org_id, 'P', 'Three', '2009-03-03', 'active') RETURNING id INTO s3;
  PERFORM _cw2_t05_add_portfolio_entry(f.org_id, f.consultant_a_user, 1, NULL, s1);
  PERFORM _cw2_t05_add_portfolio_entry(f.org_id, f.consultant_a_user, 2, NULL, s2);
  PERFORM _cw2_t05_add_portfolio_entry(f.org_id, f.consultant_a_user, 3, NULL, s3);
  PERFORM _cw2_t05_as_auth(f.consultant_a_auth);
  r1 := public.list_consultant_workspace_portfolio('{}'::jsonb, 'workspace_sequence', 'desc', 2);
  r2 := public.list_consultant_workspace_portfolio(
    '{}'::jsonb, 'workspace_sequence', 'desc', 2,
    (r1->'rows'->1->>'workspace_sequence')::bigint,
    (r1->'rows'->1->>'portfolio_entry_id')::uuid
  );
  PERFORM _cw2_t05_record(
    38, 'pagination',
    jsonb_array_length(r1->'rows') = 2
    AND (r1->>'has_more')::boolean = true
    AND r1->'next_cursor' IS NOT NULL
    AND jsonb_array_length(r2->'rows') = 1
    AND (r2->'rows'->0->>'workspace_sequence')::bigint = 1
  );
END $$;

-- 39: no duplicate rows (grid alias)
DO $$
DECLARE f record; b record; r jsonb; v_decl uuid; ids text[];
BEGIN
  SELECT * INTO f FROM _cw2_t05_org();
  SELECT * INTO b FROM _cw2_t05_student_with_finance(f.org_id, f.consultant_a_auth);
  PERFORM _cw2_t05_add_portfolio_entry(f.org_id, f.consultant_a_user, 39, NULL, b.student_id);
  PERFORM _cw2_t05_as_auth(f.consultant_a_auth);
  v_decl := public.save_consultant_payment_declaration_draft(
    NULL, CURRENT_DATE, 1000000, 'dup', NULL, b.student_id, NULL, NULL,
    b.enrollment_id, b.terms_id, b.guardian_id, 10000000, 't05-dup-39'
  );
  r := public.list_consultant_workspace_grid();
  SELECT array_agg(x.id ORDER BY x.id) INTO ids
  FROM (
    SELECT (elem->>'portfolio_entry_id') AS id
    FROM jsonb_array_elements(r->'rows') elem
  ) x;
  PERFORM _cw2_t05_record(
    39, 'no duplicate rows',
    jsonb_array_length(r->'rows') = 1
    AND ids[1] = ids[array_length(ids, 1)]
  );
END $$;

-- 40: unauthenticated denied
DO $$
DECLARE ok boolean := false;
BEGIN
  RESET ROLE;
  SET LOCAL ROLE anon;
  BEGIN
    PERFORM public.list_consultant_workspace_portfolio();
    ok := false;
  EXCEPTION WHEN OTHERS THEN
    ok := SQLERRM LIKE '%permission_denied%';
  END;
  PERFORM _cw2_t05_record(40, 'unauthenticated', ok);
END $$;

-- 41: arbitrary consultant scope denied
DO $$
DECLARE f record; ok boolean := false;
BEGIN
  SELECT * INTO f FROM _cw2_t05_org();
  PERFORM _cw2_t05_as_auth(f.consultant_b_auth);
  BEGIN
    PERFORM public.list_consultant_workspace_portfolio(
      jsonb_build_object('consultant_user_id', f.consultant_a_user::text)
    );
    ok := false;
  EXCEPTION WHEN OTHERS THEN
    ok := SQLERRM LIKE '%permission_denied%';
  END;
  PERFORM _cw2_t05_record(41, 'arbitrary consultant denied', ok);
END $$;

-- 42: read path has no mutations
DO $$
DECLARE
  f record; b record; r jsonb;
  c_portfolio integer; c_hidden integer; c_decl integer; c_pay integer; c_student integer;
  a_portfolio integer; a_hidden integer; a_decl integer; a_pay integer; a_student integer;
BEGIN
  SELECT * INTO f FROM _cw2_t05_org();
  SELECT * INTO b FROM _cw2_t05_student_with_finance(f.org_id, f.consultant_a_auth);
  PERFORM _cw2_t05_add_portfolio_entry(f.org_id, f.consultant_a_user, 42, NULL, b.student_id);
  PERFORM _cw2_t05_as_postgres();
  SELECT count(*) INTO c_portfolio FROM consultant_portfolio_entry WHERE organization_id = f.org_id;
  SELECT count(*) INTO c_hidden FROM consultant_grid_hidden_row WHERE organization_id = f.org_id;
  SELECT count(*) INTO c_decl FROM consultant_revenue_declaration WHERE organization_id = f.org_id;
  SELECT count(*) INTO c_pay FROM payment WHERE organization_id = f.org_id;
  SELECT count(*) INTO c_student FROM student WHERE organization_id = f.org_id;
  PERFORM _cw2_t05_as_auth(f.consultant_a_auth);
  r := public.list_consultant_workspace_portfolio();
  PERFORM _cw2_t05_as_postgres();
  SELECT count(*) INTO a_portfolio FROM consultant_portfolio_entry WHERE organization_id = f.org_id;
  SELECT count(*) INTO a_hidden FROM consultant_grid_hidden_row WHERE organization_id = f.org_id;
  SELECT count(*) INTO a_decl FROM consultant_revenue_declaration WHERE organization_id = f.org_id;
  SELECT count(*) INTO a_pay FROM payment WHERE organization_id = f.org_id;
  SELECT count(*) INTO a_student FROM student WHERE organization_id = f.org_id;
  PERFORM _cw2_t05_record(
    42, 'no mutations on read',
    jsonb_array_length(r->'rows') = 1
    AND c_portfolio = a_portfolio
    AND c_hidden = a_hidden
    AND c_decl = a_decl
    AND c_pay = a_pay
    AND c_student = a_student
  );
END $$;

DO $$
DECLARE v_fail integer; v_total integer;
BEGIN
  SELECT count(*) FILTER (WHERE result = 'FAIL'), count(*) INTO v_fail, v_total FROM _cw2_t05_results;
  IF v_fail > 0 THEN
    RAISE EXCEPTION 'CW2-T05 tests failed: % / % (%',
      v_fail, v_total,
      (SELECT string_agg(test_no::text || ':' || test_name, '; ') FROM _cw2_t05_results WHERE result = 'FAIL');
  END IF;
  RAISE NOTICE 'CW2-T05: all % tests passed', v_total;
END $$;
