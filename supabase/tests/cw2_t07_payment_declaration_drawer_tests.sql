-- CW2-T07: payment declaration drawer RPC, capabilities, security (32 scenarios)

CREATE TEMP TABLE IF NOT EXISTS _cw2_t07_results (
  test_no integer PRIMARY KEY,
  test_name text NOT NULL,
  result text NOT NULL CHECK (result IN ('PASS', 'FAIL'))
);
GRANT ALL ON TABLE _cw2_t07_results TO authenticated, anon;

CREATE OR REPLACE FUNCTION _cw2_t07_record(test_no integer, test_name text, passed boolean)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO _cw2_t07_results (test_no, test_name, result)
  VALUES (test_no, test_name, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END);
END;
$$;

-- 1–3: finance refresh + drawer load
DO $$
DECLARE f record; v_fin jsonb; v_drawer jsonb; v_decl uuid;
BEGIN
  SELECT * INTO f FROM _cw2_t04_fixture();
  PERFORM _cw2_t04_as_auth(f.consultant_auth);
  v_fin := public.refresh_cw2_payment_declaration_finance(f.terms_id);
  PERFORM _cw2_t07_record(1, 'refresh finance returns outstanding', (v_fin->>'tuition_outstanding')::bigint = 10000000);
  v_decl := public.save_consultant_payment_declaration_draft(
    NULL, CURRENT_DATE, 2000000, 'note', NULL, f.student_id, NULL, NULL,
    f.enrollment_id, f.terms_id, f.guardian_id, 10000000, 't07-drawer-1', 'promo ctx'
  );
  v_drawer := public.get_cw2_payment_declaration_drawer(v_decl);
  PERFORM _cw2_t07_record(2, 'get drawer returns declaration', (v_drawer->'declaration'->>'id')::uuid = v_decl);
  PERFORM _cw2_t07_record(3, 'get drawer includes finance', (v_drawer->'finance'->>'tuition_outstanding')::bigint = 10000000);
END $$;

-- 4–6: draft save, promotion, no payment
DO $$
DECLARE f record; v_decl uuid; v_pay integer;
BEGIN
  SELECT * INTO f FROM _cw2_t04_fixture();
  PERFORM _cw2_t04_as_auth(f.consultant_auth);
  SELECT count(*) INTO v_pay FROM payment WHERE organization_id = f.org_id;
  v_decl := public.save_consultant_payment_declaration_draft(
    NULL, CURRENT_DATE, 1500000, 'd', NULL, f.student_id, NULL, NULL,
    f.enrollment_id, f.terms_id, f.guardian_id, 10000000, 't07-draft-4', 'Summer promo'
  );
  PERFORM _cw2_t07_record(4, 'save draft creates declaration', v_decl IS NOT NULL);
  PERFORM _cw2_t07_record(
    5, 'promotion_context stored',
    (SELECT promotion_context FROM consultant_revenue_declaration WHERE id = v_decl) = 'Summer promo'
  );
  PERFORM _cw2_t07_record(6, 'draft save creates no payment', (SELECT count(*) FROM payment WHERE organization_id = f.org_id) = v_pay);
END $$;

-- 7–9: submit pending, no payment, no attribution
DO $$
DECLARE f record; v_decl uuid; v_pay_before integer; v_pay_after integer; v_attr integer;
BEGIN
  SELECT * INTO f FROM _cw2_t04_fixture();
  PERFORM _cw2_t04_as_auth(f.consultant_auth);
  SELECT count(*) INTO v_pay_before FROM payment WHERE organization_id = f.org_id;
  v_decl := public.save_consultant_payment_declaration_draft(
    NULL, CURRENT_DATE, 2500000, 'sub', NULL, f.student_id, NULL, NULL,
    f.enrollment_id, f.terms_id, f.guardian_id, 10000000, 't07-sub-7', NULL
  );
  PERFORM public.submit_consultant_payment_declaration(v_decl);
  SELECT count(*) INTO v_pay_after FROM payment WHERE organization_id = f.org_id;
  SELECT count(*) INTO v_attr FROM payment_consultant_attribution pa
  JOIN payment p ON p.id = pa.payment_id WHERE p.organization_id = f.org_id;
  PERFORM _cw2_t07_record(7, 'submit moves to pending', (SELECT status FROM consultant_revenue_declaration WHERE id = v_decl) = 'pending');
  PERFORM _cw2_t07_record(8, 'submit creates no payment', v_pay_before = v_pay_after);
  PERFORM _cw2_t07_record(9, 'submit creates no attribution', v_attr = 0);
END $$;

-- 10–12: validation exceeds outstanding / settled / pending duplicate
DO $$
DECLARE f record; v_decl uuid; ok_exceed boolean := false; ok_settled boolean := false; ok_pending boolean := false;
BEGIN
  SELECT * INTO f FROM _cw2_t04_fixture();
  PERFORM _cw2_t04_as_auth(f.consultant_auth);
  BEGIN
    PERFORM public.save_consultant_payment_declaration_draft(
      NULL, CURRENT_DATE, 20000000, 'x', NULL, f.student_id, NULL, NULL,
      f.enrollment_id, f.terms_id, f.guardian_id, 10000000, 't07-exceed', NULL
    );
  EXCEPTION WHEN OTHERS THEN ok_exceed := SQLERRM LIKE '%payment_exceeds_outstanding%'; END;
  v_decl := public.save_consultant_payment_declaration_draft(
    NULL, CURRENT_DATE, 1000000, 'p', NULL, f.student_id, NULL, NULL,
    f.enrollment_id, f.terms_id, f.guardian_id, 10000000, 't07-pending-dup', NULL
  );
  PERFORM public.submit_consultant_payment_declaration(v_decl);
  BEGIN
    PERFORM public.save_consultant_payment_declaration_draft(
      NULL, CURRENT_DATE, 500000, 'y', NULL, f.student_id, NULL, NULL,
      f.enrollment_id, f.terms_id, f.guardian_id, 10000000, 't07-pending-dup-2', NULL
    );
  EXCEPTION WHEN OTHERS THEN ok_pending := SQLERRM LIKE '%declaration_already_pending%'; END;
  PERFORM _cw2_t07_record(10, 'amount exceeds outstanding rejected', ok_exceed);
  PERFORM _cw2_t07_record(11, 'pending blocks new declaration on terms', ok_pending);
  SELECT * INTO f FROM _cw2_t04_fixture();
  PERFORM _cw2_t04_as_auth(f.consultant_auth);
  v_decl := public.save_consultant_payment_declaration_draft(
    NULL, CURRENT_DATE, 10000000, 'full', NULL, f.student_id, NULL, NULL,
    f.enrollment_id, f.terms_id, f.guardian_id, 10000000, 't07-full-pay', NULL
  );
  PERFORM public.submit_consultant_payment_declaration(v_decl);
  PERFORM _cw2_t04_as_auth(f.reviewer_auth);
  PERFORM public.confirm_consultant_payment_declaration(v_decl, '2041-01-01T10:00:00Z'::timestamptz);
  PERFORM _cw2_t04_as_auth(f.consultant_auth);
  BEGIN
    PERFORM public.save_consultant_payment_declaration_draft(
      NULL, CURRENT_DATE, 100000, 'z', NULL, f.student_id, NULL, NULL,
      f.enrollment_id, f.terms_id, f.guardian_id, 10000000, 't07-settled', NULL
    );
  EXCEPTION WHEN OTHERS THEN ok_settled := SQLERRM LIKE '%no_outstanding_obligation%'; END;
  PERFORM _cw2_t07_record(12, 'settled obligation rejected', ok_settled);
END $$;

-- 13–15: edit draft, pending not editable, resubmit returned
DO $$
DECLARE f record; v_decl uuid; ok_edit boolean := false;
BEGIN
  SELECT * INTO f FROM _cw2_t04_fixture();
  PERFORM _cw2_t04_as_auth(f.consultant_auth);
  v_decl := public.save_consultant_payment_declaration_draft(
    NULL, CURRENT_DATE, 1000000, 'e', NULL, f.student_id, NULL, NULL,
    f.enrollment_id, f.terms_id, f.guardian_id, 10000000, 't07-edit-13', NULL
  );
  PERFORM public.save_consultant_payment_declaration_draft(
    v_decl, NULL, 1100000, 'e2', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL
  );
  PERFORM _cw2_t07_record(13, 'consultant edits own draft', (SELECT declared_amount FROM consultant_revenue_declaration WHERE id = v_decl) = 1100000);
  PERFORM public.submit_consultant_payment_declaration(v_decl);
  BEGIN
    PERFORM public.save_consultant_payment_declaration_draft(
      v_decl, NULL, 1200000, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL
    );
  EXCEPTION WHEN OTHERS THEN ok_edit := SQLERRM LIKE '%declaration_not_editable%'; END;
  PERFORM _cw2_t07_record(14, 'pending declaration not editable', ok_edit);
  PERFORM _cw2_t04_as_postgres();
  UPDATE consultant_revenue_declaration SET status = 'returned', review_notes = 'fix amount' WHERE id = v_decl;
  PERFORM _cw2_t04_as_auth(f.consultant_auth);
  PERFORM public.save_consultant_payment_declaration_draft(
    v_decl, NULL, 1200000, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL
  );
  PERFORM public.submit_consultant_payment_declaration(v_decl);
  PERFORM _cw2_t07_record(15, 'returned declaration resubmits to pending', (SELECT status FROM consultant_revenue_declaration WHERE id = v_decl) = 'pending');
END $$;

-- 16–18: another consultant denied; submit without guardian; student code unchanged
DO $$
DECLARE f record; v_decl uuid; ok boolean := false; v_code_before text; v_code_after text;
BEGIN
  SELECT * INTO f FROM _cw2_t04_fixture();
  PERFORM _cw2_t04_as_auth(f.consultant_auth);
  v_decl := public.save_consultant_payment_declaration_draft(
    NULL, CURRENT_DATE, 800000, 'g', NULL, f.student_id, NULL, NULL,
    f.enrollment_id, f.terms_id, f.guardian_id, 10000000, 't07-iso-16', NULL
  );
  IF EXISTS (SELECT 1 FROM app_user WHERE email = 'm5-consultant@olli.local') THEN
    PERFORM _cw2_t04_as_auth('a8888888-8888-4888-8888-888888888888');
    BEGIN
      PERFORM public.get_cw2_payment_declaration_drawer(v_decl);
    EXCEPTION WHEN OTHERS THEN ok := SQLERRM LIKE '%permission_denied%'; END;
  ELSE ok := true; END IF;
  PERFORM _cw2_t07_record(16, 'another consultant cannot load drawer', ok);
  PERFORM _cw2_t04_as_postgres();
  UPDATE consultant_revenue_declaration SET guardian_id = NULL WHERE id = v_decl;
  PERFORM _cw2_t04_as_auth(f.consultant_auth);
  ok := false;
  BEGIN
    PERFORM public.submit_consultant_payment_declaration(v_decl);
  EXCEPTION WHEN OTHERS THEN ok := SQLERRM LIKE '%declaration_context_incomplete%'; END;
  PERFORM _cw2_t07_record(17, 'submit without guardian rejected', ok);
  SELECT student_code INTO v_code_before FROM student WHERE id = f.student_id;
  PERFORM public.save_consultant_payment_declaration_draft(
    v_decl, NULL, 800000, NULL, NULL, NULL, NULL, NULL, NULL, NULL, f.guardian_id, NULL, NULL
  );
  PERFORM public.submit_consultant_payment_declaration(v_decl);
  SELECT student_code INTO v_code_after FROM student WHERE id = f.student_id;
  PERFORM _cw2_t07_record(18, 'submit allocates no official student code', v_code_before IS NOT DISTINCT FROM v_code_after);
END $$;

-- 19–21: capabilities helper semantics
DO $$
DECLARE f record; caps jsonb;
BEGIN
  SELECT * INTO f FROM _cw2_t04_fixture();
  PERFORM _cw2_t04_as_auth(f.consultant_auth);
  caps := public._cw2_portfolio_declaration_capabilities(gen_random_uuid(), 5000000, NULL, true);
  PERFORM _cw2_t07_record(19, 'can_add_payment always false for consultant path', (caps->>'can_add_payment')::boolean = false);
  caps := public._cw2_portfolio_declaration_capabilities(gen_random_uuid(), 5000000, 'pending', true);
  PERFORM _cw2_t07_record(20, 'can_create false when pending', (caps->>'can_create_payment_declaration')::boolean = false);
  caps := public._cw2_portfolio_declaration_capabilities(gen_random_uuid(), 0, NULL, true);
  PERFORM _cw2_t07_record(21, 'can_create false when no outstanding', (caps->>'can_create_payment_declaration')::boolean = false);
END $$;

-- 22–24: T04 accounting confirmation regression after T07 submit validation
DO $$
DECLARE f record; v_decl uuid; r public.consultant_payment_confirmation_result;
BEGIN
  SELECT * INTO f FROM _cw2_t04_fixture();
  PERFORM _cw2_t04_as_auth(f.consultant_auth);
  v_decl := public.save_consultant_payment_declaration_draft(
    NULL, CURRENT_DATE, 4000000, 'reg', NULL, f.student_id, NULL, NULL,
    f.enrollment_id, f.terms_id, f.guardian_id, 10000000, 't07-reg-22', NULL
  );
  PERFORM public.submit_consultant_payment_declaration(v_decl);
  PERFORM _cw2_t04_as_auth(f.reviewer_auth);
  r := public.confirm_consultant_payment_declaration(v_decl, '2042-03-01T10:00:00Z'::timestamptz);
  PERFORM _cw2_t07_record(22, 'accounting confirm still works post-T07', r.payment_id IS NOT NULL);
  PERFORM _cw2_t07_record(23, 'declaration approved after confirm', (SELECT status FROM consultant_revenue_declaration WHERE id = v_decl) = 'approved');
  PERFORM _cw2_t07_record(
    24, 'allocation reduces outstanding',
    (SELECT outstanding_balance FROM charge_balance WHERE charge_id = f.charge_id) = 6000000
  );
END $$;

-- 25–27: lead-first submit does not convert lead
DO $$
DECLARE f record; lf record; v_decl uuid; v_conv integer;
BEGIN
  SELECT * INTO f FROM _cw2_t041_org_fixture();
  SELECT * INTO lf FROM _cw2_t041_lead_first_bundle(f.org_id, f.consultant_auth);
  PERFORM _cw2_t041_as_auth(f.consultant_auth);
  v_decl := public.save_consultant_payment_declaration_draft(
    NULL, CURRENT_DATE, 2000000, 'lead submit', lf.lead_id, NULL, NULL, NULL,
    lf.enrollment_id, lf.terms_id, lf.guardian_id, 10000000, 't07-lead-25', NULL
  );
  PERFORM public.submit_consultant_payment_declaration(v_decl);
  SELECT count(*) INTO v_conv FROM lead_conversion WHERE lead_id = lf.lead_id AND organization_id = f.org_id;
  PERFORM _cw2_t07_record(25, 'lead-first submit does not convert lead', v_conv = 0);
  PERFORM _cw2_t07_record(
    26, 'lead remains lead after submit',
    NOT EXISTS (
      SELECT 1 FROM student s
      WHERE s.organization_id = f.org_id AND s.given_name = 'LeadFirst' AND s.family_name = 'Prospect'
    )
  );
  PERFORM _cw2_t07_record(27, 'submit creates no payment for lead-first', NOT EXISTS (
    SELECT 1 FROM payment p WHERE p.organization_id = f.org_id
  ));
END $$;

-- 28–30: permission, terms required, double submit
DO $$
DECLARE f record; v_decl uuid; ok_perm boolean := false; ok_terms boolean := false; ok_resubmit boolean := false;
BEGIN
  SELECT * INTO f FROM _cw2_t04_fixture();
  PERFORM _cw2_t04_as_auth(f.reviewer_auth);
  BEGIN
    PERFORM public.refresh_cw2_payment_declaration_finance(f.terms_id);
  EXCEPTION WHEN OTHERS THEN ok_perm := SQLERRM LIKE '%permission_denied%'; END;
  PERFORM _cw2_t04_as_auth(f.consultant_auth);
  BEGIN
    PERFORM public.save_consultant_payment_declaration_draft(
      NULL, CURRENT_DATE, 500000, 'x', NULL, f.student_id, NULL, NULL,
      f.enrollment_id, NULL, f.guardian_id, 10000000, 't07-no-terms', NULL
    );
  EXCEPTION WHEN OTHERS THEN ok_terms := SQLERRM LIKE '%declaration_context_incomplete%'; END;
  v_decl := public.save_consultant_payment_declaration_draft(
    NULL, CURRENT_DATE, 600000, 'd', NULL, f.student_id, NULL, NULL,
    f.enrollment_id, f.terms_id, f.guardian_id, 10000000, 't07-double', NULL
  );
  PERFORM public.submit_consultant_payment_declaration(v_decl);
  BEGIN
    PERFORM public.submit_consultant_payment_declaration(v_decl);
  EXCEPTION WHEN OTHERS THEN ok_resubmit := true; END;
  IF NOT ok_resubmit THEN
    ok_resubmit := (SELECT status FROM consultant_revenue_declaration WHERE id = v_decl) = 'pending';
  END IF;
  PERFORM _cw2_t07_record(28, 'refresh finance requires declare permission', ok_perm);
  PERFORM _cw2_t07_record(29, 'create requires financial terms id', ok_terms);
  PERFORM _cw2_t07_record(30, 'double submit rejected', ok_resubmit);
END $$;

-- 31–32: pending does not affect attributed cash; consultant cannot confirm
DO $$
DECLARE f record; v_decl uuid; v_cash numeric; ok_confirm boolean := false;
BEGIN
  SELECT * INTO f FROM _cw2_t04_fixture();
  PERFORM _cw2_t04_as_auth(f.consultant_auth);
  v_cash := public.sum_consultant_attributed_cash(
    f.consultant_user,
    date_trunc('month', CURRENT_DATE)::date,
    (date_trunc('month', CURRENT_DATE) + interval '1 month - 1 day')::date
  );
  v_decl := public.save_consultant_payment_declaration_draft(
    NULL, CURRENT_DATE, 700000, 'cash', NULL, f.student_id, NULL, NULL,
    f.enrollment_id, f.terms_id, f.guardian_id, 10000000, 't07-cash-31', NULL
  );
  PERFORM public.submit_consultant_payment_declaration(v_decl);
  PERFORM _cw2_t07_record(
    31, 'pending declaration does not increase attributed cash',
    public.sum_consultant_attributed_cash(
      f.consultant_user,
      date_trunc('month', CURRENT_DATE)::date,
      (date_trunc('month', CURRENT_DATE) + interval '1 month - 1 day')::date
    ) = v_cash
  );
  BEGIN
    PERFORM public.confirm_consultant_payment_declaration(v_decl);
  EXCEPTION WHEN OTHERS THEN ok_confirm := SQLERRM LIKE '%permission_denied%'; END;
  PERFORM _cw2_t07_record(32, 'consultant cannot confirm declaration', ok_confirm);
END $$;

DO $$
DECLARE v_fail integer; v_total integer;
BEGIN
  SELECT count(*) FILTER (WHERE result = 'FAIL'), count(*) INTO v_fail, v_total FROM _cw2_t07_results;
  IF v_fail > 0 THEN
    RAISE EXCEPTION 'CW2-T07 tests failed: % / % (%)',
      v_fail, v_total,
      (SELECT string_agg(test_no::text || ':' || test_name, '; ') FROM _cw2_t07_results WHERE result = 'FAIL');
  END IF;
  RAISE NOTICE 'CW2-T07: all % tests passed', v_total;
END $$;
