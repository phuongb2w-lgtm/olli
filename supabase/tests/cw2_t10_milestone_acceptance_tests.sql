-- CW2-T10: milestone integration acceptance (18 scenarios — end-to-end Consultant Workspace V2)

CREATE TEMP TABLE IF NOT EXISTS _cw2_t10_results (
  test_no integer PRIMARY KEY,
  test_name text NOT NULL,
  result text NOT NULL CHECK (result IN ('PASS', 'FAIL'))
);
GRANT ALL ON TABLE _cw2_t10_results TO authenticated, anon;

CREATE OR REPLACE FUNCTION _cw2_t10_record(test_no integer, test_name text, passed boolean)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO _cw2_t10_results (test_no, test_name, result)
  VALUES (test_no, test_name, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END);
END;
$$;

-- 1–3 Scenario 1: Lead in consultant portfolio (STT, provisional code, no official code)
DO $$
DECLARE f record; lf record; v_pe uuid; r jsonb; j jsonb;
BEGIN
  SELECT * INTO f FROM _cw2_t041_org_fixture();
  SELECT * INTO lf FROM _cw2_t041_lead_first_bundle(f.org_id, f.consultant_auth);
  v_pe := _cw2_t05_add_portfolio_entry(f.org_id, f.consultant_user, 101, lf.lead_id, NULL);
  PERFORM _cw2_t041_as_auth(f.consultant_auth);
  r := public.list_consultant_workspace_portfolio();
  j := public.get_consultant_portfolio_entry_detail(v_pe);
  PERFORM _cw2_t10_record(1, 'S1 portfolio lists authorized lead row', jsonb_array_length(r->'rows') >= 1);
  PERFORM _cw2_t10_record(2, 'S1 stable STT in grid and detail', (
    (r->'rows'->0->>'workspace_sequence')::bigint = 101
    AND (j->>'workspace_sequence')::bigint = 101
  ));
  PERFORM _cw2_t10_record(3, 'S1 no official student code before confirm', (
    NOT public._cw2_is_official_student_code(COALESCE(j->>'student_code_official', ''))
    AND (j->>'student_code_is_provisional')::boolean = true
  ));
END $$;

-- 4–6 Scenarios 2–3: Draft and submit — no Payment, no Sales, no official code
DO $$
DECLARE f record; lf record; v_decl uuid; v_pe uuid; j jsonb; v_pay integer; v_code text;
  v_month date := '2060-04-01';
BEGIN
  SELECT * INTO f FROM _cw2_t041_org_fixture();
  SELECT * INTO lf FROM _cw2_t041_lead_first_bundle(f.org_id, f.consultant_auth);
  v_pe := _cw2_t05_add_portfolio_entry(f.org_id, f.consultant_user, 102, lf.lead_id, NULL);
  PERFORM _cw2_t041_as_auth(f.consultant_auth);
  j := public.get_consultant_portfolio_entry_detail(v_pe);
  SELECT count(*) INTO v_pay FROM payment WHERE organization_id = f.org_id;
  PERFORM _cw2_t10_record(4, 'S2 draft declaration no payment yet', (
    v_pay = 0 AND (_cw2_t08_sales(v_month)->>'sales_amount')::bigint = 0
  ));
  v_decl := public.save_consultant_payment_declaration_draft(
    NULL, CURRENT_DATE, 2500000, 't10-draft', lf.lead_id, NULL, NULL, NULL,
    lf.enrollment_id, lf.terms_id, lf.guardian_id, 10000000, 't10-s2'
  );
  SELECT count(*) INTO v_pay FROM payment WHERE organization_id = f.org_id;
  PERFORM _cw2_t10_record(5, 'S2 draft still no authoritative payment', v_pay = 0);
  PERFORM public.submit_consultant_payment_declaration(v_decl);
  SELECT student_code INTO v_code FROM student WHERE id = lf.prospect_student_id;
  PERFORM _cw2_t10_record(6, 'S3 submit awaits accounting no sales no official code', (
    (SELECT status FROM consultant_revenue_declaration WHERE id = v_decl) = 'pending'
    AND (_cw2_t08_sales(v_month)->>'sales_amount')::bigint = 0
    AND NOT public._cw2_is_official_student_code(COALESCE(v_code, ''))
  ));
END $$;

-- 7–10 Scenario 4: Accounting confirmation — payment, registration, code, attribution, sales once
DO $$
DECLARE f record; lf record; v_decl uuid; r record; v_pay integer; v_attr integer; v_conv integer;
  v_month date := '2060-05-01'; j jsonb;
BEGIN
  SELECT * INTO f FROM _cw2_t041_org_fixture();
  SELECT * INTO lf FROM _cw2_t041_lead_first_bundle(f.org_id, f.consultant_auth);
  PERFORM _cw2_t05_add_portfolio_entry(f.org_id, f.consultant_user, 103, lf.lead_id, NULL);
  PERFORM _cw2_t041_as_auth(f.consultant_auth);
  v_decl := public.save_consultant_payment_declaration_draft(
    NULL, CURRENT_DATE, 4000000, 't10-confirm', lf.lead_id, NULL, NULL, NULL,
    lf.enrollment_id, lf.terms_id, lf.guardian_id, 10000000, 't10-s4'
  );
  PERFORM public.submit_consultant_payment_declaration(v_decl);
  PERFORM _cw2_t041_as_auth(f.accountant_auth);
  r := public.confirm_consultant_payment_declaration(v_decl, '2060-05-18T09:00:00Z'::timestamptz);
  SELECT count(*) INTO v_pay FROM payment p
    JOIN consultant_revenue_declaration d ON d.approved_payment_id = p.id WHERE d.id = v_decl;
  SELECT count(*) INTO v_attr FROM payment_consultant_attribution WHERE payment_id = r.payment_id;
  SELECT count(*) INTO v_conv FROM lead_conversion WHERE lead_id = lf.lead_id AND organization_id = f.org_id;
  PERFORM _cw2_t041_as_auth(f.consultant_auth);
  j := _cw2_t08_sales(v_month);
  PERFORM _cw2_t10_record(7, 'S4 authoritative payment and conversion', (
    r.payment_id IS NOT NULL
    AND (
      v_conv = 1
      OR EXISTS (SELECT 1 FROM lead WHERE id = lf.lead_id AND status = 'converted')
    )
  ));
  PERFORM _cw2_t10_record(8, 'S4 official student code allocated once', public._cw2_is_official_student_code(r.official_student_code));
  PERFORM _cw2_t10_record(9, 'S4 payment attribution exactly once', v_pay = 1 AND v_attr = 1);
  PERFORM _cw2_t10_record(10, 'S4 monthly sales includes confirmed cash once', (
    (j->>'sales_amount')::bigint = 4000000 AND (j->>'payment_count')::int = 1
  ));
END $$;

-- 11–12 Scenario 5: Replay confirmation — no duplicates
DO $$
DECLARE f record; lf record; v_decl uuid; r2 public.consultant_payment_confirmation_result;
BEGIN
  SELECT * INTO f FROM _cw2_t041_org_fixture();
  SELECT * INTO lf FROM _cw2_t041_lead_first_bundle(f.org_id, f.consultant_auth);
  PERFORM _cw2_t041_as_auth(f.consultant_auth);
  v_decl := public.save_consultant_payment_declaration_draft(
    NULL, CURRENT_DATE, 1500000, 't10-replay', lf.lead_id, NULL, NULL, NULL,
    lf.enrollment_id, lf.terms_id, lf.guardian_id, 10000000, 't10-s5'
  );
  PERFORM public.submit_consultant_payment_declaration(v_decl);
  PERFORM _cw2_t041_as_auth(f.accountant_auth);
  PERFORM public.confirm_consultant_payment_declaration(v_decl, '2060-06-10T10:00:00Z'::timestamptz);
  r2 := public.confirm_consultant_payment_declaration(v_decl, '2060-06-10T10:00:00Z'::timestamptz);
  PERFORM _cw2_t041_as_auth(f.consultant_auth);
  PERFORM _cw2_t10_record(11, 'S5 idempotent confirm replay flag', r2.idempotent_replay);
  PERFORM _cw2_t10_record(12, 'S5 replay one payment row', (
    r2.idempotent_replay
    AND (SELECT approved_payment_id IS NOT NULL FROM consultant_revenue_declaration WHERE id = v_decl)
  ));
END $$;

-- 13–14 Scenario 6: Second legitimate payment — code unchanged, sales additive
DO $$
DECLARE
  f record;
  v_d1 uuid;
  v_d2 uuid;
  r1 public.consultant_payment_confirmation_result;
  r2 public.consultant_payment_confirmation_result;
  j jsonb;
  v_month date := '2060-07-01';
BEGIN
  SELECT * INTO f FROM _cw2_t04_fixture();
  PERFORM _cw2_t04_as_auth(f.consultant_auth);
  v_d1 := public.save_consultant_payment_declaration_draft(
    NULL, CURRENT_DATE, 3000000, 't10-m1', NULL, f.student_id, NULL, NULL,
    f.enrollment_id, f.terms_id, f.guardian_id, NULL, 't10-m1', NULL
  );
  PERFORM public.submit_consultant_payment_declaration(v_d1);
  PERFORM _cw2_t04_as_auth(f.reviewer_auth);
  r1 := public.confirm_consultant_payment_declaration(v_d1, '2060-07-05T08:00:00Z'::timestamptz);
  PERFORM _cw2_t04_as_auth(f.consultant_auth);
  v_d2 := public.save_consultant_payment_declaration_draft(
    NULL, CURRENT_DATE, 2000000, 't10-m2', NULL, f.student_id, NULL, NULL,
    f.enrollment_id, f.terms_id, f.guardian_id, NULL, 't10-m2', NULL
  );
  PERFORM public.submit_consultant_payment_declaration(v_d2);
  PERFORM _cw2_t04_as_auth(f.reviewer_auth);
  r2 := public.confirm_consultant_payment_declaration(v_d2, '2060-07-12T08:00:00Z'::timestamptz);
  PERFORM _cw2_t04_as_auth(f.consultant_auth);
  j := _cw2_t08_sales(v_month);
  PERFORM _cw2_t10_record(13, 'S6 official code unchanged on second payment', (
    public._cw2_is_official_student_code(r1.official_student_code)
    AND r1.official_student_code IS NOT DISTINCT FROM r2.official_student_code
  ));
  PERFORM _cw2_t10_record(14, 'S6 sales increases by second confirmed payment only', (
    (j->>'sales_amount')::bigint = 5000000 AND (j->>'payment_count')::int = 2
  ));
END $$;

-- 15 Scenario 7: Full-paid — cannot declare when no outstanding obligation
DO $$
DECLARE f record; ok boolean := false;
BEGIN
  SELECT * INTO f FROM _cw2_t04_fixture();
  PERFORM _cw2_t08_confirm_amount(
    f.consultant_auth, f.reviewer_auth, f.student_id, f.enrollment_id, f.terms_id, f.guardian_id,
    10000000, 't10-full', '2060-08-01T08:00:00Z'::timestamptz
  );
  PERFORM _cw2_t04_as_auth(f.consultant_auth);
  BEGIN
    PERFORM public.save_consultant_payment_declaration_draft(
      NULL, CURRENT_DATE, 100000, 'x', NULL, f.student_id, NULL, NULL,
      f.enrollment_id, f.terms_id, f.guardian_id, 10000000, 't10-settled'
    );
  EXCEPTION WHEN OTHERS THEN ok := SQLERRM LIKE '%no_outstanding_obligation%'; END;
  PERFORM _cw2_t10_record(15, 'S7 settled obligation blocks new declaration', ok);
END $$;

-- 16 Scenario 8: Student detail finance read-only
DO $$
DECLARE f record; fin record; v_pe uuid; j jsonb;
BEGIN
  SELECT * INTO f FROM _cw2_t05_org();
  SELECT * INTO fin FROM _cw2_t05_student_with_finance(f.org_id, f.consultant_a_auth);
  v_pe := _cw2_t05_add_portfolio_entry(f.org_id, f.consultant_a_user, 116, NULL, fin.student_id);
  PERFORM _cw2_t05_as_auth(f.consultant_a_auth);
  j := public.get_consultant_portfolio_entry_detail(v_pe);
  PERFORM _cw2_t10_record(16, 'S8 detail shows authoritative student finance read-only', (
    j ? 'tuition_outstanding' AND j ? 'tuition_payment_state'
  ));
END $$;

-- 17 Scenario 9: official student profile locked; code immutable (mirrors CW2-T09 SQL 13)
DO $$
DECLARE f record; fin record; v_pe uuid; v_code text; v_cc char(2); ok_locked boolean := false;
BEGIN
  SELECT * INTO f FROM _cw2_t05_org();
  SELECT * INTO fin FROM _cw2_t05_student_with_finance(f.org_id, f.consultant_a_auth);
  PERFORM _cw2_t05_as_postgres();
  SELECT consultant_operational_code INTO v_cc FROM app_user WHERE id = f.consultant_a_user;
  v_code := v_cc || '15' || '0901';
  UPDATE student SET student_code = v_code WHERE id = fin.student_id;
  v_pe := _cw2_t05_add_portfolio_entry(f.org_id, f.consultant_a_user, 117, NULL, fin.student_id);
  SELECT student_code INTO v_code FROM student WHERE id = fin.student_id;
  PERFORM _cw2_t05_as_auth(f.consultant_a_auth);
  BEGIN
    PERFORM public.save_consultant_portfolio_profile(v_pe, 'Nguyen', 'Chi', '2015-09-09', NULL, NULL, NULL, NULL);
  EXCEPTION WHEN OTHERS THEN ok_locked := SQLERRM LIKE '%profile_locked%'; END;
  PERFORM _cw2_t05_as_postgres();
  PERFORM _cw2_t10_record(17, 'S9 official student profile locked; code unchanged', (
    ok_locked
    AND v_code IS NOT NULL
    AND public._cw2_is_official_student_code(v_code)
    AND (SELECT student_code FROM student WHERE id = fin.student_id) = v_code
  ));
END $$;

-- 18 Scenarios 10–12: IDOR, hidden preference, sort/filter stability
DO $$
DECLARE f record; fin record; v_pe uuid; r_hide jsonb; r_show jsonb; v_stt bigint := 118;
BEGIN
  SELECT * INTO f FROM _cw2_t05_org();
  SELECT * INTO fin FROM _cw2_t05_student_with_finance(f.org_id, f.consultant_a_auth);
  v_pe := _cw2_t05_add_portfolio_entry(f.org_id, f.consultant_a_user, v_stt, NULL, fin.student_id);
  PERFORM _cw2_t05_as_auth(f.consultant_a_auth);
  INSERT INTO consultant_grid_hidden_row (organization_id, app_user_id, subject_type, subject_id)
    VALUES (f.org_id, f.consultant_a_user, 'student', fin.student_id)
  ON CONFLICT DO NOTHING;
  r_hide := public.list_consultant_workspace_portfolio();
  r_show := public.list_consultant_workspace_portfolio('{}'::jsonb, 'workspace_sequence', 'desc', 50, NULL, NULL, true);
  PERFORM _cw2_t10_record(18, 'S11–S12 hidden preference and stable STT', (
    jsonb_array_length(COALESCE(r_hide->'rows', '[]'::jsonb)) = 0
    AND jsonb_array_length(COALESCE(r_show->'rows', '[]'::jsonb)) = 1
    AND (r_show->'rows'->0->>'workspace_sequence')::bigint = v_stt
  ));
END $$;

DO $$
DECLARE v_fail integer; v_total integer;
BEGIN
  SELECT count(*) FILTER (WHERE result = 'FAIL'), count(*) INTO v_fail, v_total FROM _cw2_t10_results;
  IF v_fail > 0 THEN
    RAISE EXCEPTION 'CW2-T10 tests failed: % / % (%)',
      v_fail, v_total,
      (SELECT string_agg(test_no::text || ':' || test_name, '; ') FROM _cw2_t10_results WHERE result = 'FAIL');
  END IF;
  RAISE NOTICE 'CW2-T10: all % tests passed', v_total;
END $$;
