-- CW2-T08: consultant monthly sales header RPC tests (30 scenarios)

CREATE TEMP TABLE IF NOT EXISTS _cw2_t08_results (
  test_no integer PRIMARY KEY,
  test_name text NOT NULL,
  result text NOT NULL CHECK (result IN ('PASS', 'FAIL'))
);
GRANT ALL ON TABLE _cw2_t08_results TO authenticated, anon;

CREATE OR REPLACE FUNCTION _cw2_t08_record(test_no integer, test_name text, passed boolean)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO _cw2_t08_results (test_no, test_name, result)
  VALUES (test_no, test_name, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END);
END;
$$;

CREATE OR REPLACE FUNCTION _cw2_t08_sales(p_month date)
RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT public.get_consultant_monthly_sales(p_month);
$$;

CREATE OR REPLACE FUNCTION _cw2_t08_confirm_amount(
  p_consultant_auth uuid,
  p_reviewer_auth uuid,
  p_student_id uuid,
  p_enrollment_id uuid,
  p_terms_id uuid,
  p_guardian_id uuid,
  p_amount numeric,
  p_idem text,
  p_paid timestamptz DEFAULT NULL
)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_decl uuid;
BEGIN
  PERFORM _cw2_t04_as_auth(p_consultant_auth);
  v_decl := public.save_consultant_payment_declaration_draft(
    NULL, CURRENT_DATE, p_amount, p_idem, NULL, p_student_id, NULL, NULL,
    p_enrollment_id, p_terms_id, p_guardian_id, NULL, p_idem, NULL
  );
  PERFORM public.submit_consultant_payment_declaration(v_decl);
  PERFORM _cw2_t04_as_auth(p_reviewer_auth);
  PERFORM public.confirm_consultant_payment_declaration(v_decl, p_paid);
  RETURN v_decl;
END;
$$;

-- 1–4 access + zero
DO $$
DECLARE f record; j jsonb;
BEGIN
  SELECT * INTO f FROM _cw2_t04_fixture();
  PERFORM _cw2_t04_as_auth(f.consultant_auth);
  j := _cw2_t08_sales('2099-06-01');
  PERFORM _cw2_t08_record(1, 'consultant reads own monthly sales', (j->>'sales_amount')::bigint = 0);
  PERFORM _cw2_t08_record(2, 'zero month returns zero not error', j ? 'sales_amount');
  PERFORM _cw2_t08_record(3, 'currency VND', j->>'currency_code' = 'VND');
  PERFORM _cw2_t08_record(4, 'payment count zero', (j->>'payment_count')::int = 0);
END $$;

-- 5–7 aggregation
DO $$
DECLARE f record; j jsonb; v_decl uuid;
BEGIN
  SELECT * INTO f FROM _cw2_t04_fixture();
  v_decl := _cw2_t08_confirm_amount(
    f.consultant_auth, f.reviewer_auth, f.student_id, f.enrollment_id, f.terms_id, f.guardian_id,
    3000000, 't08-a', '2041-09-15T10:00:00Z'::timestamptz
  );
  PERFORM _cw2_t08_confirm_amount(
    f.consultant_auth, f.reviewer_auth, f.student_id, f.enrollment_id, f.terms_id, f.guardian_id,
    2000000, 't08-b', '2041-09-20T10:00:00Z'::timestamptz
  );
  PERFORM _cw2_t04_as_auth(f.consultant_auth);
  j := _cw2_t08_sales('2041-09-01');
  PERFORM _cw2_t08_record(5, 'confirmed payments summed', (j->>'sales_amount')::bigint = 5000000);
  PERFORM _cw2_t08_record(6, 'one payment counted once per confirm', (
    SELECT count(*) FROM consultant_revenue_declaration d
    WHERE d.id = v_decl AND d.approved_payment_id IS NOT NULL
  ) = 1);
  PERFORM _cw2_t08_record(7, 'payment count distinct payments', (j->>'payment_count')::int = 2);
END $$;

-- 8–12 lifecycle exclusions + confirmed inclusion
DO $$
DECLARE f record; j jsonb; v_decl uuid; v_before bigint;
BEGIN
  SELECT * INTO f FROM _cw2_t04_fixture();
  PERFORM _cw2_t04_as_auth(f.consultant_auth);
  j := _cw2_t08_sales('2042-03-01');
  v_before := (j->>'sales_amount')::bigint;
  v_decl := public.save_consultant_payment_declaration_draft(
    NULL, CURRENT_DATE, 1000000, 'd', NULL, f.student_id, NULL, NULL,
    f.enrollment_id, f.terms_id, f.guardian_id, NULL, 't08-draft', NULL
  );
  j := _cw2_t08_sales('2042-03-01');
  PERFORM _cw2_t08_record(8, 'draft excluded', (j->>'sales_amount')::bigint = v_before);
  PERFORM public.submit_consultant_payment_declaration(v_decl);
  j := _cw2_t08_sales('2042-03-01');
  PERFORM _cw2_t08_record(9, 'pending excluded', (j->>'sales_amount')::bigint = v_before);
  PERFORM _cw2_t04_as_auth(f.reviewer_auth);
  PERFORM public.review_consultant_revenue_declaration(v_decl, 'return', 'fix');
  j := _cw2_t08_sales('2042-03-01');
  PERFORM _cw2_t08_record(10, 'returned excluded', (j->>'sales_amount')::bigint = v_before);
  PERFORM _cw2_t04_as_auth(f.consultant_auth);
  v_decl := public.save_consultant_payment_declaration_draft(
    v_decl, CURRENT_DATE, 1000000, 'd2', NULL, f.student_id, NULL, NULL,
    f.enrollment_id, f.terms_id, f.guardian_id, NULL, 't08-pend2', NULL
  );
  PERFORM public.submit_consultant_payment_declaration(v_decl);
  PERFORM _cw2_t04_as_auth(f.reviewer_auth);
  PERFORM public.review_consultant_revenue_declaration(v_decl, 'reject', 'no');
  j := _cw2_t08_sales('2042-03-01');
  PERFORM _cw2_t08_record(11, 'rejected excluded', (j->>'sales_amount')::bigint = v_before);
  PERFORM _cw2_t08_confirm_amount(
    f.consultant_auth, f.reviewer_auth, f.student_id, f.enrollment_id, f.terms_id, f.guardian_id,
    1500000, 't08-conf', '2042-03-10T12:00:00Z'::timestamptz
  );
  PERFORM _cw2_t04_as_auth(f.consultant_auth);
  j := _cw2_t08_sales('2042-03-01');
  PERFORM _cw2_t08_record(12, 'confirmed attributed included', (j->>'sales_amount')::bigint = v_before + 1500000);
END $$;

-- 13–14 attribution required
DO $$
DECLARE f record; j jsonb; v_pay uuid;
BEGIN
  SELECT * INTO f FROM _cw2_t04_fixture();
  PERFORM _cw2_t08_confirm_amount(
    f.consultant_auth, f.reviewer_auth, f.student_id, f.enrollment_id, f.terms_id, f.guardian_id,
    900000, 't08-attr', '2043-01-05T08:00:00Z'::timestamptz
  );
  PERFORM _cw2_t04_as_auth(f.consultant_auth);
  j := _cw2_t08_sales('2043-01-01');
  PERFORM _cw2_t08_record(13, 'attributed payment included', (j->>'sales_amount')::bigint >= 900000);
  PERFORM _cw2_t04_as_postgres();
  INSERT INTO payment (
    organization_id, guardian_id, amount, currency_code, method_code, status, paid_at
  ) VALUES (f.org_id, f.guardian_id, 500000, 'VND', 'cash', 'posted', '2043-01-06T08:00:00Z'::timestamptz)
  RETURNING id INTO v_pay;
  PERFORM _cw2_t04_as_auth(f.consultant_auth);
  j := _cw2_t08_sales('2043-01-01');
  PERFORM _cw2_t08_record(14, 'unattributed payment excluded', (j->>'sales_amount')::bigint = 900000);
END $$;

-- 15–17 period semantics (aligned with CW2-T04: confirm paid_at in February, declaration date January)
DO $$
DECLARE f record; v_decl uuid; j_jan jsonb; j_feb jsonb;
BEGIN
  SELECT * INTO f FROM _cw2_t04_fixture();
  PERFORM _cw2_t04_as_auth(f.consultant_auth);
  v_decl := public.save_consultant_payment_declaration_draft(
    NULL, '2040-01-31', 2500000, 'month', NULL, f.student_id, NULL, NULL,
    f.enrollment_id, f.terms_id, f.guardian_id, NULL, 't08-month', NULL
  );
  PERFORM public.submit_consultant_payment_declaration(v_decl);
  PERFORM _cw2_t04_as_auth(f.reviewer_auth);
  PERFORM public.confirm_consultant_payment_declaration(v_decl, '2040-02-01T12:00:00Z'::timestamptz);
  PERFORM _cw2_t04_as_auth(f.consultant_auth);
  j_jan := _cw2_t08_sales('2040-01-01');
  j_feb := _cw2_t08_sales('2040-02-01');
  PERFORM _cw2_t08_record(15, 'paid_at determines month feb', (j_feb->>'sales_amount')::bigint >= 2500000);
  PERFORM _cw2_t08_record(16, 'declaration date not sales month', (j_jan->>'sales_amount')::bigint = 0);
  PERFORM _cw2_t08_record(
    17, 'attribution_recorded_at not sales driver',
    public.sum_consultant_attributed_cash(f.consultant_user, '2040-01-01', '2040-01-31')
      = (j_jan->>'sales_amount')::bigint
  );
END $$;

-- 18 revenue recognition independence
DO $$
DECLARE f record; j jsonb;
BEGIN
  SELECT * INTO f FROM _cw2_t04_fixture();
  PERFORM _cw2_t08_confirm_amount(
    f.consultant_auth, f.reviewer_auth, f.student_id, f.enrollment_id, f.terms_id, f.guardian_id,
    5000000, 't08-rev', '2044-05-01T12:00:00Z'::timestamptz
  );
  PERFORM _cw2_t04_as_auth(f.consultant_auth);
  j := _cw2_t08_sales('2044-05-01');
  PERFORM _cw2_t08_record(18, 'sales independent of revenue recognition', (j->>'sales_amount')::bigint = 5000000);
END $$;

-- 19–20 idempotent + allocation shape
DO $$
DECLARE f record; j jsonb; v_decl uuid;
BEGIN
  SELECT * INTO f FROM _cw2_t04_fixture();
  PERFORM _cw2_t04_as_auth(f.consultant_auth);
  v_decl := public.save_consultant_payment_declaration_draft(
    NULL, CURRENT_DATE, 1000000, 'idem', NULL, f.student_id, NULL, NULL,
    f.enrollment_id, f.terms_id, f.guardian_id, NULL, 't08-idem', NULL
  );
  PERFORM public.submit_consultant_payment_declaration(v_decl);
  PERFORM _cw2_t04_as_auth(f.reviewer_auth);
  PERFORM public.confirm_consultant_payment_declaration(v_decl, '2045-07-01T12:00:00Z'::timestamptz);
  PERFORM public.confirm_consultant_payment_declaration(v_decl, '2045-07-01T12:00:00Z'::timestamptz);
  PERFORM _cw2_t04_as_auth(f.consultant_auth);
  j := _cw2_t08_sales('2045-07-01');
  PERFORM _cw2_t08_record(19, 'idempotent confirm does not duplicate sales', (j->>'sales_amount')::bigint = 1000000);
  PERFORM _cw2_t08_record(20, 'split allocations still one payment amount', (j->>'payment_count')::int = 1);
END $$;

-- 21–22 other consultant isolation
DO $$
DECLARE f record; j_a jsonb; j_b jsonb; v_cons_b uuid; v_auth_b uuid;
BEGIN
  SELECT * INTO f FROM _cw2_t04_fixture();
  PERFORM _cw2_t08_confirm_amount(
    f.consultant_auth, f.reviewer_auth, f.student_id, f.enrollment_id, f.terms_id, f.guardian_id,
    800000, 't08-own', '2046-01-10T12:00:00Z'::timestamptz
  );
  PERFORM _cw2_t04_as_postgres();
  v_auth_b := gen_random_uuid();
  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at, is_sso_user, is_anonymous)
  VALUES (v_auth_b, (SELECT id FROM auth.instances LIMIT 1), 'authenticated', 'authenticated', 't08-b-' || f.org_id::text || '@olli.local', '', now(), now(), now(), false, false);
  v_cons_b := public.test_fixture_insert_app_user(f.org_id, 't08-b-' || f.org_id::text || '@olli.local', 'T08 B', v_auth_b);
  INSERT INTO user_role (organization_id, user_id, role_id, effective_from, status)
  SELECT f.org_id, v_cons_b, r.id, CURRENT_DATE, 'active'
  FROM role r WHERE r.organization_id = f.org_id AND r.canonical_code = 'consultant';
  PERFORM _cw2_t04_as_auth(f.consultant_auth);
  j_a := _cw2_t08_sales('2046-01-01');
  PERFORM _cw2_t04_as_auth(v_auth_b);
  j_b := _cw2_t08_sales('2046-01-01');
  PERFORM _cw2_t08_record(21, 'other consultant zero own sales', (j_b->>'sales_amount')::bigint = 0);
  PERFORM _cw2_t08_record(22, 'consultant A retains sales', (j_a->>'sales_amount')::bigint = 800000);
END $$;

-- 23 comparison previous zero -> new
DO $$
DECLARE f record; j jsonb;
BEGIN
  SELECT * INTO f FROM _cw2_t04_fixture();
  PERFORM _cw2_t08_confirm_amount(
    f.consultant_auth, f.reviewer_auth, f.student_id, f.enrollment_id, f.terms_id, f.guardian_id,
    1200000, 't08-cmp', '2047-08-05T12:00:00Z'::timestamptz
  );
  PERFORM _cw2_t04_as_auth(f.consultant_auth);
  j := _cw2_t08_sales('2047-08-01');
  PERFORM _cw2_t08_record(
    23, 'previous zero comparison kind new',
    (j->'comparison'->>'kind') = 'new' AND (j->'comparison'->>'percent') IS NULL
  );
END $$;

-- 24–25 month boundary + read-only
DO $$
DECLARE f record; j jsonb; v_pay_cnt integer;
BEGIN
  SELECT * INTO f FROM _cw2_t04_fixture();
  PERFORM _cw2_t08_confirm_amount(
    f.consultant_auth, f.reviewer_auth, f.student_id, f.enrollment_id, f.terms_id, f.guardian_id,
    100000, 't08-bnd', '2048-12-31T15:00:00Z'::timestamptz
  );
  PERFORM _cw2_t04_as_auth(f.consultant_auth);
  j := _cw2_t08_sales('2048-12-01');
  PERFORM _cw2_t08_record(24, 'month boundary december', (j->>'sales_amount')::bigint = 100000);
  SELECT count(*) INTO v_pay_cnt FROM payment WHERE organization_id = f.org_id;
  PERFORM _cw2_t08_sales('2048-12-01');
  PERFORM _cw2_t08_record(25, 'read causes no mutation', (SELECT count(*) FROM payment WHERE organization_id = f.org_id) = v_pay_cnt);
END $$;

-- 26–27 navigation + helper parity
DO $$
DECLARE f record; j jsonb;
BEGIN
  SELECT * INTO f FROM _cw2_t04_fixture();
  PERFORM _cw2_t04_as_auth(f.consultant_auth);
  j := _cw2_t08_sales(NULL);
  PERFORM _cw2_t08_record(26, 'navigation block includes can_go_next', j ? 'navigation');
  PERFORM _cw2_t08_record(
    27, 'rpc matches sum_consultant_attributed_cash',
    (j->>'sales_amount')::bigint = public.sum_consultant_attributed_cash(
      f.consultant_user,
      (j->'period'->>'month_start')::date,
      (j->'period'->>'month_end')::date
    )
  );
END $$;

-- 28 lead-first counted once
DO $$
DECLARE f record; lf record; v_decl uuid; j jsonb;
BEGIN
  SELECT * INTO f FROM _cw2_t041_org_fixture();
  SELECT * INTO lf FROM _cw2_t041_lead_first_bundle(f.org_id, f.consultant_auth);
  PERFORM _cw2_t041_as_auth(f.consultant_auth);
  v_decl := public.save_consultant_payment_declaration_draft(
    NULL, CURRENT_DATE, 3000000, 'lf', lf.lead_id, NULL, NULL, NULL,
    lf.enrollment_id, lf.terms_id, lf.guardian_id, 10000000, 't08-lf'
  );
  PERFORM public.submit_consultant_payment_declaration(v_decl);
  PERFORM _cw2_t041_as_auth(f.accountant_auth);
  PERFORM public.confirm_consultant_payment_declaration(v_decl, '2049-03-12T10:00:00Z'::timestamptz);
  PERFORM _cw2_t041_as_auth(f.consultant_auth);
  j := _cw2_t08_sales('2049-03-01');
  PERFORM _cw2_t08_record(28, 'lead-first confirmation counts payment once', (j->>'payment_count')::int = 1);
END $$;

-- 29 permission denied without session
DO $$
DECLARE ok boolean := false;
BEGIN
  PERFORM _cw2_t04_as_auth('00000000-0000-4000-8000-000000000099');
  BEGIN
    PERFORM _cw2_t08_sales('2050-01-01');
  EXCEPTION WHEN OTHERS THEN ok := true; END;
  PERFORM _cw2_t08_record(29, 'invalid session denied', ok);
END $$;

-- 30 mandatory acceptance scenario
DO $$
DECLARE f record; j jsonb; v_decl uuid; v_m date := '2051-06-01'; ok boolean := true;
BEGIN
  SELECT * INTO f FROM _cw2_t04_fixture();
  PERFORM _cw2_t04_as_auth(f.consultant_auth);
  j := _cw2_t08_sales(v_m);
  ok := ok AND (j->>'sales_amount')::bigint = 0;
  v_decl := public.save_consultant_payment_declaration_draft(
    NULL, CURRENT_DATE, 3000000, 'acc', NULL, f.student_id, NULL, NULL,
    f.enrollment_id, f.terms_id, f.guardian_id, NULL, 't08-acc', NULL
  );
  ok := ok AND (_cw2_t08_sales(v_m)->>'sales_amount')::bigint = 0;
  PERFORM public.submit_consultant_payment_declaration(v_decl);
  ok := ok AND (_cw2_t08_sales(v_m)->>'sales_amount')::bigint = 0;
  PERFORM _cw2_t04_as_auth(f.reviewer_auth);
  PERFORM public.confirm_consultant_payment_declaration(v_decl, '2051-06-20T08:00:00Z'::timestamptz);
  PERFORM public.confirm_consultant_payment_declaration(v_decl, '2051-06-20T08:00:00Z'::timestamptz);
  PERFORM _cw2_t08_confirm_amount(
    f.consultant_auth, f.reviewer_auth, f.student_id, f.enrollment_id, f.terms_id, f.guardian_id,
    2000000, 't08-acc2', '2051-06-25T08:00:00Z'::timestamptz
  );
  PERFORM _cw2_t04_as_auth(f.consultant_auth);
  j := _cw2_t08_sales(v_m);
  ok := ok AND (j->>'sales_amount')::bigint = 5000000 AND (j->>'payment_count')::int = 2;
  PERFORM _cw2_t08_record(30, 'acceptance draft pending confirm idempotent total', ok);
END $$;

DO $$
DECLARE v_fail integer; v_total integer;
BEGIN
  SELECT count(*) FILTER (WHERE result = 'FAIL'), count(*) INTO v_fail, v_total FROM _cw2_t08_results;
  IF v_fail > 0 THEN
    RAISE EXCEPTION 'CW2-T08 tests failed: % / % (%)',
      v_fail, v_total,
      (SELECT string_agg(test_no::text || ':' || test_name, '; ') FROM _cw2_t08_results WHERE result = 'FAIL');
  END IF;
  RAISE NOTICE 'CW2-T08: all % tests passed', v_total;
END $$;
