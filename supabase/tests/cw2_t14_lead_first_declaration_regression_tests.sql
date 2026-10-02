-- CW2-T14: lead-first tuition declaration regression (18 scenarios)
-- Requires helpers from cw2_t05_consultant_workspace_read_model_tests.sql and
-- cw2_t11_tuition_declaration_v2_tests.sql. Payloads mirror the Consultant drawer:
-- guardian id comes from the portfolio read model and the obligation may be 0.

CREATE TEMP TABLE IF NOT EXISTS _cw2_t14_results (
  test_no integer PRIMARY KEY,
  test_name text NOT NULL,
  result text NOT NULL CHECK (result IN ('PASS', 'FAIL'))
);
GRANT ALL ON TABLE _cw2_t14_results TO authenticated, anon;

CREATE TEMP TABLE IF NOT EXISTS _cw2_t14_flags (k text PRIMARY KEY, v boolean);
GRANT ALL ON TABLE _cw2_t14_flags TO authenticated, anon;

CREATE OR REPLACE FUNCTION _cw2_t14_record(test_no integer, test_name text, passed boolean)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO _cw2_t14_results (test_no, test_name, result)
  VALUES (test_no, test_name, CASE WHEN COALESCE(passed, false) THEN 'PASS' ELSE 'FAIL' END);
END;
$$;

CREATE OR REPLACE FUNCTION _cw2_t14_row(p_portfolio_entry_id uuid)
RETURNS jsonb LANGUAGE sql AS $$
  SELECT r
  FROM jsonb_array_elements(public.list_consultant_workspace_portfolio(p_limit => 200)->'rows') r
  WHERE r->>'portfolio_entry_id' = p_portfolio_entry_id::text
  LIMIT 1;
$$;

-- 1–13, 15b, 16: new lead intake through Accounting confirmation
DO $$
DECLARE
  f record; acct record; other record;
  j jsonb; r jsonb; v_ctx jsonb;
  v_entry uuid; v_lead uuid;
  v_decl uuid; v_decl_row public.consultant_revenue_declaration;
  v_pay uuid; v_err text; v_ok boolean;
  v_student uuid; v_enrollment uuid; v_terms uuid; v_guardian uuid;
  v_foreign_guardian uuid; v_ctx_text text;
BEGIN
  SELECT * INTO f FROM _cw2_t05_org();
  SELECT * INTO acct FROM _cw2_t05_accountant_for_org(f.org_id);
  SELECT * INTO other FROM _cw2_t05_org();
  PERFORM _cw2_t05_as_postgres();
  INSERT INTO guardian (organization_id, given_name, family_name, phone)
    VALUES (other.org_id, 'Foreign', 'Guardian', '0907000000') RETURNING id INTO v_foreign_guardian;
  WITH c AS (
    INSERT INTO course (organization_id, code, name)
    VALUES (f.org_id, 'T14' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 4), 'T14 Course')
    RETURNING id
  )
  INSERT INTO class (organization_id, course_id, name, status)
  SELECT f.org_id, c.id, 'T14 Class', 'active' FROM c;

  PERFORM _cw2_t11_as_auth(f.consultant_a_auth);
  j := public.create_consultant_workspace_portfolio_intake(
    'PHUNG VAN', 'DOAN', DATE '2008-08-28', 'PHUNG VAN', 'B', '0912345678', NULL, '[]'::jsonb
  );
  v_entry := (j->>'portfolio_entry_id')::uuid;
  v_lead := (j->>'lead_id')::uuid;
  r := _cw2_t14_row(v_entry);

  v_ctx := public.get_cw2_tuition_declaration_context_for_portfolio(v_entry);
  PERFORM _cw2_t14_record(1, 'new lead without plan fetches declaration context',
    v_ctx IS NOT NULL
    AND (v_ctx->>'lead_id')::uuid = v_lead
    AND v_ctx->>'enrollment_id' IS NULL
    AND v_ctx->>'enrollment_financial_terms_id' IS NULL);
  PERFORM _cw2_t14_record(2, 'context reports plan not established (not completed)',
    (v_ctx->>'tuition_established')::boolean = false
    AND (v_ctx->'finance'->>'tuition_established')::boolean = false
    AND (v_ctx->>'can_change_billing_mode')::boolean = true
    AND r->>'tuition_payment_state' = 'chua_nop_phi');

  -- Drawer payload: read-model primary_guardian_id (lead contact) and obligation 0.
  BEGIN
    v_decl := public.save_consultant_payment_declaration_draft(
      p_declaration_date => CURRENT_DATE,
      p_declared_amount => 2500000,
      p_description => 'oK',
      p_lead_id => v_lead,
      p_guardian_id => (r->>'primary_guardian_id')::uuid,
      p_total_obligation_amount => 0,
      p_idempotency_key => 't14-lead-lump-' || v_entry::text,
      p_promotion_context => '12%',
      p_tuition_billing_mode => 'course_lump_sum',
      p_proposed_net_tuition_amount => 10000000,
      p_payment_method_code => 'cash',
      p_declaration_kind => 'initial_tuition_setup'
    );
  EXCEPTION WHEN OTHERS THEN
    v_decl := NULL;
    RAISE NOTICE 'T14 save failed: % %', SQLSTATE, SQLERRM;
  END;
  PERFORM _cw2_t05_as_postgres();
  SELECT * INTO v_decl_row FROM consultant_revenue_declaration WHERE id = v_decl;
  PERFORM _cw2_t14_record(3, 'new lead saves first declaration draft with drawer payload',
    v_decl IS NOT NULL AND v_decl_row.status = 'draft'
    AND v_decl_row.guardian_id IS NOT NULL
    AND v_decl_row.guardian_id IS DISTINCT FROM (r->>'primary_guardian_id')::uuid
    AND EXISTS (SELECT 1 FROM guardian g WHERE g.id = v_decl_row.guardian_id AND g.organization_id = f.org_id));
  PERFORM _cw2_t11_as_auth(f.consultant_a_auth);

  BEGIN
    PERFORM public.submit_consultant_payment_declaration(v_decl);
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'T14 submit failed: % %', SQLSTATE, SQLERRM;
  END;
  SELECT * INTO v_decl_row FROM consultant_revenue_declaration WHERE id = v_decl;
  PERFORM _cw2_t14_record(4, 'new lead submits first declaration for accounting',
    v_decl_row.status = 'pending' AND v_decl_row.submitted_at IS NOT NULL);
  PERFORM _cw2_t14_record(5, 'positive first payment allowed without established plan',
    v_decl_row.declared_amount = 2500000
    AND v_decl_row.total_obligation_amount = 10000000
    AND v_decl_row.proposed_net_tuition_amount = 10000000
    AND v_decl_row.declaration_kind = 'initial_tuition_setup');
  PERFORM _cw2_t14_record(6, 'no enrollment required at consultant submit',
    v_decl_row.enrollment_id IS NULL AND v_decl_row.enrollment_financial_terms_id IS NULL
    AND v_decl_row.student_id IS NULL);

  r := _cw2_t14_row(v_entry);
  PERFORM _cw2_t14_record(7, 'no official code required at consultant submit',
    r->>'student_code_official' IS NULL
    AND (r->>'student_code_is_provisional')::boolean
    AND r->>'student_code_display' LIKE '__080000');
  PERFORM _cw2_t14_record(8, 'declaration pending before accounting confirmation',
    v_decl_row.approved_payment_id IS NULL
    AND r->>'tuition_payment_state' = 'coc_cho_xac_nhan'
    AND r->>'declaration_status' = 'pending'
    AND (r->>'declaration_id')::uuid = v_decl);

  PERFORM _cw2_t05_as_postgres();
  PERFORM _cw2_t14_record(9, 'pending declaration posts no payment or allocation',
    NOT EXISTS (SELECT 1 FROM payment p WHERE p.organization_id = f.org_id AND p.guardian_id = v_decl_row.guardian_id)
    AND NOT EXISTS (SELECT 1 FROM payment_consultant_attribution a WHERE a.consultant_revenue_declaration_id = v_decl));
  PERFORM _cw2_t11_as_auth(f.consultant_a_auth);

  -- 15b: a second first-plan declaration for the same lead is rejected while pending.
  BEGIN
    PERFORM public.save_consultant_payment_declaration_draft(
      p_declaration_date => CURRENT_DATE, p_declared_amount => 1000000, p_lead_id => v_lead,
      p_guardian_id => (r->>'primary_guardian_id')::uuid, p_total_obligation_amount => 0,
      p_idempotency_key => 't14-lead-dup-' || v_entry::text,
      p_tuition_billing_mode => 'course_lump_sum', p_proposed_net_tuition_amount => 10000000,
      p_payment_method_code => 'cash', p_declaration_kind => 'initial_tuition_setup');
    v_err := NULL;
  EXCEPTION WHEN OTHERS THEN v_err := SQLERRM;
  END;
  INSERT INTO _cw2_t14_flags VALUES ('dup_initial_rejected', v_err LIKE '%initial_tuition_plan_already_pending%')
    ON CONFLICT (k) DO UPDATE SET v = EXCLUDED.v;

  -- 16: guardian id from another organization is never stored.
  PERFORM _cw2_t11_as_auth(f.consultant_a_auth);
  j := public.create_consultant_workspace_portfolio_intake(
    'TRAN THI', 'HOA', DATE '2010-02-02', 'TRAN', 'C', '0912000111', NULL, '[]'::jsonb
  );
  BEGIN
    v_pay := public.save_consultant_payment_declaration_draft(
      p_declaration_date => CURRENT_DATE, p_declared_amount => 2500000,
      p_lead_id => (j->>'lead_id')::uuid, p_guardian_id => v_foreign_guardian,
      p_idempotency_key => 't14-foreign-' || (j->>'portfolio_entry_id'),
      p_tuition_billing_mode => 'periodic', p_periodic_period_unit => 'month',
      p_periodic_period_quantity => 1, p_periodic_amount_per_period => 2500000,
      p_payment_method_code => 'cash', p_declaration_kind => 'initial_tuition_setup');
  EXCEPTION WHEN OTHERS THEN v_pay := NULL;
  END;
  PERFORM _cw2_t05_as_postgres();
  PERFORM _cw2_t14_record(16, 'foreign-org guardian id is replaced by own lead guardian',
    v_pay IS NOT NULL AND EXISTS (
      SELECT 1 FROM consultant_revenue_declaration d
      JOIN guardian g ON g.id = d.guardian_id AND g.organization_id = f.org_id
      WHERE d.id = v_pay AND d.guardian_id <> v_foreign_guardian));

  -- Accounting confirmation of the first lead declaration (no prior CRM identity step).
  v_err := NULL;
  BEGIN
    PERFORM _cw2_t11_confirm(f.org_id, acct.accountant_auth, v_decl, f.consultant_a_auth);
  EXCEPTION WHEN OTHERS THEN
    v_err := SQLERRM;
    GET STACKED DIAGNOSTICS v_ctx_text = PG_EXCEPTION_CONTEXT;
    RAISE NOTICE 'T14 confirm failed: % (%)', SQLERRM, v_ctx_text;
  END;
  PERFORM _cw2_t05_as_postgres();
  SELECT * INTO v_decl_row FROM consultant_revenue_declaration WHERE id = v_decl;
  v_student := v_decl_row.student_id;
  v_enrollment := v_decl_row.enrollment_id;
  v_terms := v_decl_row.enrollment_financial_terms_id;
  v_guardian := v_decl_row.guardian_id;

  PERFORM _cw2_t14_record(10, 'accounting confirmation establishes canonical financial terms',
    v_err IS NULL AND v_terms IS NOT NULL AND EXISTS (
      SELECT 1 FROM enrollment_financial_terms t
      WHERE t.id = v_terms AND t.tuition_plan_established_at IS NOT NULL
        AND t.net_tuition_amount = 10000000));
  PERFORM _cw2_t14_record(11, 'accounting confirmation posts canonical payment',
    v_decl_row.status = 'approved'
    AND EXISTS (SELECT 1 FROM payment p WHERE p.id = v_decl_row.approved_payment_id AND p.amount = 2500000)
    AND (SELECT COALESCE(sum(pa.amount), 0) FROM payment_allocation pa
         WHERE pa.payment_id = v_decl_row.approved_payment_id AND pa.status = 'posted') = 2500000);
  PERFORM _cw2_t14_record(12, 'official conversion and linking happen at confirmation',
    v_student IS NOT NULL
    AND EXISTS (SELECT 1 FROM student s WHERE s.id = v_student AND public._cw2_is_official_student_code(s.student_code))
    AND EXISTS (SELECT 1 FROM consultant_portfolio_entry e WHERE e.id = v_entry AND e.student_id = v_student)
    AND EXISTS (SELECT 1 FROM lead l WHERE l.id = v_lead AND l.status = 'converted')
    AND EXISTS (
      SELECT 1 FROM lead_contact lc
      WHERE lc.lead_id = v_lead AND lc.is_primary_contact AND lc.converted_guardian_id = v_guardian)
    AND EXISTS (
      SELECT 1 FROM lead_identity_resolution_event ev
      JOIN lead_candidate lc ON lc.id = ev.subject_id
      WHERE ev.subject_type = 'candidate' AND lc.lead_id = v_lead
        AND ev.new_resolution_mode = 'create_new' AND ev.changed_by = acct.accountant_user));

  -- 13: pay the remaining balance, then a further normal declaration is blocked.
  PERFORM _cw2_t11_as_auth(f.consultant_a_auth);
  v_ok := false;
  BEGIN
    v_pay := public.save_consultant_payment_declaration_draft(
      p_declaration_date => CURRENT_DATE, p_declared_amount => 7500000,
      p_student_id => v_student, p_enrollment_id => v_enrollment,
      p_enrollment_financial_terms_id => v_terms, p_guardian_id => v_guardian,
      p_idempotency_key => 't14-remaining-' || v_entry::text,
      p_payment_method_code => 'cash', p_declaration_kind => 'payment_only');
    PERFORM public.submit_consultant_payment_declaration(v_pay);
    PERFORM _cw2_t11_confirm(f.org_id, acct.accountant_auth, v_pay, f.consultant_a_auth);
    v_ok := true;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'T14 remaining payment failed: %', SQLERRM;
  END;
  v_err := NULL;
  BEGIN
    PERFORM public.save_consultant_payment_declaration_draft(
      p_declaration_date => CURRENT_DATE, p_declared_amount => 100000,
      p_student_id => v_student, p_enrollment_id => v_enrollment,
      p_enrollment_financial_terms_id => v_terms, p_guardian_id => v_guardian,
      p_idempotency_key => 't14-overpay-' || v_entry::text,
      p_payment_method_code => 'cash', p_declaration_kind => 'payment_only');
  EXCEPTION WHEN OTHERS THEN v_err := SQLERRM;
  END;
  PERFORM _cw2_t14_record(13, 'fully paid established plan blocks further normal declaration',
    v_ok AND (v_err LIKE '%no_outstanding_obligation%' OR v_err LIKE '%payment_exceeds_outstanding%'));
  PERFORM _cw2_t05_as_postgres();
END $$;

-- 14, 15, 17: provisional-code student with enrollment but no established plan
DO $$
DECLARE
  f record; s record; r jsonb;
  v_entry uuid; v_init uuid; v_follow uuid; v_err text;
  v_init_row public.consultant_revenue_declaration;
  v_follow_row public.consultant_revenue_declaration;
BEGIN
  SELECT * INTO f FROM _cw2_t05_org();
  SELECT * INTO s FROM _cw2_t11_bare_student(f.org_id, f.consultant_a_auth);
  v_entry := _cw2_t05_add_portfolio_entry(f.org_id, f.consultant_a_user, 1, NULL, s.student_id);
  PERFORM _cw2_t11_as_auth(f.consultant_a_auth);
  r := _cw2_t14_row(v_entry);

  BEGIN
    v_init := public.save_consultant_payment_declaration_draft(
      p_declaration_date => CURRENT_DATE, p_declared_amount => 2500000, p_description => 'oK',
      p_student_id => s.student_id, p_course_id => (r->>'course_id')::uuid, p_class_id => (r->>'class_id')::uuid,
      p_enrollment_id => (r->>'enrollment_id')::uuid,
      p_enrollment_financial_terms_id => (r->>'enrollment_financial_terms_id')::uuid,
      p_guardian_id => (r->>'primary_guardian_id')::uuid,
      p_total_obligation_amount => 0,
      p_idempotency_key => 't14-prov-' || v_entry::text,
      p_tuition_billing_mode => 'periodic', p_periodic_period_unit => 'month',
      p_periodic_period_quantity => 1, p_periodic_amount_per_period => 2500000,
      p_payment_method_code => 'cash', p_declaration_kind => 'initial_tuition_setup');
    PERFORM public.submit_consultant_payment_declaration(v_init);
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'T14 provisional student failed: % %', SQLSTATE, SQLERRM;
  END;
  SELECT * INTO v_init_row FROM consultant_revenue_declaration WHERE id = v_init;
  PERFORM _cw2_t14_record(14, 'provisional-code student submits first declaration',
    (r->>'student_code_is_provisional')::boolean
    AND r->>'student_code_official' IS NULL
    AND v_init_row.status = 'pending'
    AND v_init_row.guardian_id = s.guardian_id
    AND v_init_row.total_obligation_amount IS NULL);

  BEGIN
    v_follow := public.save_consultant_payment_declaration_draft(
      p_declaration_date => CURRENT_DATE, p_declared_amount => 500000,
      p_student_id => s.student_id, p_enrollment_id => (r->>'enrollment_id')::uuid,
      p_enrollment_financial_terms_id => (r->>'enrollment_financial_terms_id')::uuid,
      p_guardian_id => (r->>'primary_guardian_id')::uuid,
      p_idempotency_key => 't14-prov-follow-' || v_entry::text,
      p_payment_method_code => 'cash', p_declaration_kind => 'payment_only');
    PERFORM public.submit_consultant_payment_declaration(v_follow);
  EXCEPTION WHEN OTHERS THEN
    v_err := SQLERRM;
    RAISE NOTICE 'T14 follow-up failed: %', SQLERRM;
  END;
  SELECT * INTO v_follow_row FROM consultant_revenue_declaration WHERE id = v_follow;
  PERFORM _cw2_t14_record(15, 'multiple pending declarations keep T11 dependency semantics',
    v_follow_row.status = 'pending'
    AND v_follow_row.depends_on_declaration_id = v_init
    AND (SELECT v FROM _cw2_t14_flags WHERE k = 'dup_initial_rejected'));

  r := _cw2_t14_row(v_entry);
  PERFORM _cw2_t14_record(17, 'pending declaration visible on portfolio row',
    r->>'declaration_status' = 'pending'
    AND r->>'tuition_payment_state' IN ('coc_cho_xac_nhan', 'cho_xac_nhan'));
  PERFORM _cw2_t05_as_postgres();
END $$;

-- 18: a strong duplicate student still blocks automatic conversion at confirmation
DO $$
DECLARE
  f record; acct record; j jsonb; r jsonb;
  v_decl uuid; v_err text; v_row public.consultant_revenue_declaration;
BEGIN
  SELECT * INTO f FROM _cw2_t05_org();
  SELECT * INTO acct FROM _cw2_t05_accountant_for_org(f.org_id);
  PERFORM _cw2_t05_as_postgres();
  INSERT INTO student (organization_id, given_name, family_name, date_of_birth, status)
    VALUES (f.org_id, 'TRUNG', 'LE VAN', DATE '2012-05-05', 'active');

  PERFORM _cw2_t11_as_auth(f.consultant_a_auth);
  j := public.create_consultant_workspace_portfolio_intake(
    'LE VAN', 'TRUNG', DATE '2012-05-05', 'LE VAN', 'D', '0913999888', NULL, '[]'::jsonb
  );
  r := _cw2_t14_row((j->>'portfolio_entry_id')::uuid);
  v_decl := public.save_consultant_payment_declaration_draft(
    p_declaration_date => CURRENT_DATE, p_declared_amount => 2500000,
    p_lead_id => (j->>'lead_id')::uuid, p_guardian_id => (r->>'primary_guardian_id')::uuid,
    p_total_obligation_amount => 0, p_idempotency_key => 't14-dup-' || (j->>'portfolio_entry_id'),
    p_tuition_billing_mode => 'course_lump_sum', p_proposed_net_tuition_amount => 10000000,
    p_payment_method_code => 'cash', p_declaration_kind => 'initial_tuition_setup');
  PERFORM public.submit_consultant_payment_declaration(v_decl);

  BEGIN
    PERFORM _cw2_t11_confirm(f.org_id, acct.accountant_auth, v_decl, f.consultant_a_auth);
  EXCEPTION WHEN OTHERS THEN v_err := SQLERRM;
  END;
  PERFORM _cw2_t05_as_postgres();
  SELECT * INTO v_row FROM consultant_revenue_declaration WHERE id = v_decl;
  PERFORM _cw2_t14_record(18, 'strong duplicate blocks automatic conversion at confirmation',
    v_err LIKE '%identity_not_ready%'
    AND v_row.status = 'pending' AND v_row.student_id IS NULL
    AND NOT EXISTS (
      SELECT 1 FROM lead_candidate_identity_resolution res
      JOIN lead_candidate lc ON lc.id = res.lead_candidate_id
      WHERE lc.lead_id = (j->>'lead_id')::uuid));
END $$;

DO $$
DECLARE v_fail integer; v_total integer;
BEGIN
  SELECT count(*) FILTER (WHERE result = 'FAIL'), count(*) INTO v_fail, v_total FROM _cw2_t14_results;
  IF v_fail > 0 THEN
    RAISE EXCEPTION 'CW2-T14 tests failed: % / % (%)',
      v_fail, v_total,
      (SELECT string_agg(test_no::text || ':' || test_name, '; ' ORDER BY test_no) FROM _cw2_t14_results WHERE result = 'FAIL');
  END IF;
  IF v_total <> 18 THEN
    RAISE EXCEPTION 'CW2-T14 expected 18 scenarios, recorded %', v_total;
  END IF;
  RAISE NOTICE 'CW2-T14: all % tests passed', v_total;
END $$;
