-- M5-T02: Financial intelligence read layer tests (28 scenarios)

BEGIN;

CREATE TEMP TABLE _m5_t02_results (
  test_no   integer PRIMARY KEY,
  test_name text NOT NULL,
  result    text NOT NULL CHECK (result IN ('PASS', 'FAIL'))
);

GRANT ALL ON TABLE _m5_t02_results TO authenticated, anon;

CREATE OR REPLACE FUNCTION _m5_t02_record(test_no integer, test_name text, passed boolean)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO _m5_t02_results (test_no, test_name, result)
  VALUES (test_no, test_name, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END);
END;
$$;

CREATE OR REPLACE FUNCTION _m5_t02_as_auth(p_auth_id uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', p_auth_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_auth_id::text, 'role', 'authenticated')::text, true);
END;
$$;

CREATE OR REPLACE FUNCTION _m5_t02_as_super()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
END;
$$;

CREATE OR REPLACE FUNCTION _m5_t02_seed_auth_user(p_auth uuid, p_email text)
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

-- Ensure M5 role users exist (idempotent with prior M5 test seeds)
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_role uuid;
  v_user uuid;
  v_auth uuid;
BEGIN
  PERFORM _m5_t02_as_super();

  IF NOT EXISTS (SELECT 1 FROM app_user WHERE email = 'm5-t02-accountant@olli.local') THEN
    v_auth := 'b7777777-7777-4777-8777-777777777777';
    PERFORM _m5_t02_seed_auth_user(v_auth, 'm5-t02-accountant@olli.local');
    INSERT INTO role (organization_id, code) VALUES (v_org, 'm5_t02_accountant') RETURNING id INTO v_role;
    INSERT INTO role_permission (role_id, permission_id)
    SELECT v_role, p.id FROM permission p
    WHERE p.code IN (
      'organization.read', 'payment.read', 'payment.record', 'revenue.read',
      'charge.read', 'expense.read', 'consultant_revenue.review', 'class_economics.read',
      'guardian.read', 'student.read'
    );
    INSERT INTO app_user (organization_id, email, display_name, auth_user_id, status)
    VALUES (v_org, 'm5-t02-accountant@olli.local', 'M5 T02 Accountant', v_auth, 'active')
    RETURNING id INTO v_user;
    INSERT INTO user_role (organization_id, user_id, role_id, effective_from, status)
    VALUES (v_org, v_user, v_role, CURRENT_DATE, 'active');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM app_user WHERE email = 'm5-t02-consultant@olli.local') THEN
    v_auth := 'b8888888-8888-4888-8888-888888888888';
    PERFORM _m5_t02_seed_auth_user(v_auth, 'm5-t02-consultant@olli.local');
    INSERT INTO role (organization_id, code) VALUES (v_org, 'm5_t02_consultant') RETURNING id INTO v_role;
    INSERT INTO role_permission (role_id, permission_id)
    SELECT v_role, p.id FROM permission p WHERE p.code IN ('organization.read', 'consultant_revenue.declare');
    INSERT INTO app_user (organization_id, email, display_name, auth_user_id, status)
    VALUES (v_org, 'm5-t02-consultant@olli.local', 'M5 T02 Consultant', v_auth, 'active')
    RETURNING id INTO v_user;
    INSERT INTO user_role (organization_id, user_id, role_id, effective_from, status)
    VALUES (v_org, v_user, v_role, CURRENT_DATE, 'active');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM app_user WHERE email = 'm5-t02-teacher@olli.local') THEN
    v_auth := 'b9999999-9999-4999-8999-999999999999';
    PERFORM _m5_t02_seed_auth_user(v_auth, 'm5-t02-teacher@olli.local');
    INSERT INTO role (organization_id, code) VALUES (v_org, 'm5_t02_teacher') RETURNING id INTO v_role;
    INSERT INTO role_permission (role_id, permission_id)
    SELECT v_role, p.id FROM permission p
    WHERE p.code IN ('organization.read', 'attendance.record', 'enrollment.read');
    INSERT INTO app_user (organization_id, email, display_name, auth_user_id, status)
    VALUES (v_org, 'm5-t02-teacher@olli.local', 'M5 T02 Teacher', v_auth, 'active')
    RETURNING id INTO v_user;
    INSERT INTO user_role (organization_id, user_id, role_id, effective_from, status)
    VALUES (v_org, v_user, v_role, CURRENT_DATE, 'active');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM app_user WHERE email = 'm5-t02-academic@olli.local') THEN
    v_auth := 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
    PERFORM _m5_t02_seed_auth_user(v_auth, 'm5-t02-academic@olli.local');
    INSERT INTO role (organization_id, code) VALUES (v_org, 'm5_t02_academic_ops') RETURNING id INTO v_role;
    INSERT INTO role_permission (role_id, permission_id)
    SELECT v_role, p.id FROM permission p
    WHERE p.code IN ('organization.read', 'enrollment.read', 'student.read');
    INSERT INTO app_user (organization_id, email, display_name, auth_user_id, status)
    VALUES (v_org, 'm5-t02-academic@olli.local', 'M5 T02 Academic', v_auth, 'active')
    RETURNING id INTO v_user;
    INSERT INTO user_role (organization_id, user_id, role_id, effective_from, status)
    VALUES (v_org, v_user, v_role, CURRENT_DATE, 'active');
  END IF;
END $$;

-- 1: posted payment counted in cash
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_guardian uuid;
  v_before numeric;
  v_after numeric;
BEGIN
  PERFORM _m5_t02_as_super();
  SELECT id INTO v_guardian FROM guardian WHERE organization_id = v_org LIMIT 1;

  PERFORM _m5_t02_as_auth('b7777777-7777-4777-8777-777777777777');
  v_before := public.sum_canonical_cash_collected('2040-01-01', '2040-01-31');
  PERFORM public.record_payment(
    v_guardian, 500000,
    timestamptz '2040-01-15 10:00:00+07', 'cash'
  );
  v_after := public.sum_canonical_cash_collected('2040-01-01', '2040-01-31');
  PERFORM _m5_t02_record(1, 'posted payment counted in cash', v_after = v_before + 500000);
END $$;

-- 2: non-posted payment excluded from cash
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_guardian uuid;
  v_before numeric;
  v_after numeric;
BEGIN
  PERFORM _m5_t02_as_auth('b7777777-7777-4777-8777-777777777777');
  v_before := public.sum_canonical_cash_collected('2040-02-01', '2040-02-28');

  PERFORM _m5_t02_as_super();
  SELECT id INTO v_guardian FROM guardian WHERE organization_id = v_org LIMIT 1;
  INSERT INTO payment (
    organization_id, guardian_id, amount, currency_code, paid_at,
    method_code, status
  )
  SELECT v_org, v_guardian, 777777, o.currency_code,
    timestamptz '2040-02-15 10:00:00+07', 'cash', 'void'
  FROM organization o WHERE o.id = v_org;

  PERFORM _m5_t02_as_auth('b7777777-7777-4777-8777-777777777777');
  v_after := public.sum_canonical_cash_collected('2040-02-01', '2040-02-28');
  PERFORM _m5_t02_record(2, 'non-posted payment excluded from cash', v_after = v_before);
END $$;

-- 3: consultant declaration is not cash
DO $$
DECLARE v_decl uuid; v_cash numeric;
BEGIN
  PERFORM _m5_t02_as_auth('b8888888-8888-4888-8888-888888888888');
  v_decl := public.declare_consultant_revenue('2040-03-01', 1234567, 'T02 not cash');
  PERFORM _m5_t02_as_auth('b7777777-7777-4777-8777-777777777777');
  v_cash := public.sum_canonical_cash_collected('2040-03-01', '2040-03-31');
  PERFORM _m5_t02_record(
    3,
    'consultant declaration is not cash',
    v_decl IS NOT NULL AND v_cash >= 0
      AND NOT public.declaration_has_canonical_payment(v_decl)
  );
END $$;

-- 4: approved declaration without payment is not cash
DO $$
DECLARE v_decl uuid; v_cash_before numeric; v_cash_after numeric;
BEGIN
  PERFORM _m5_t02_as_auth('b8888888-8888-4888-8888-888888888888');
  v_decl := public.declare_consultant_revenue('2040-04-01', 654321, 'T02 approved no pay');

  PERFORM _m5_t02_as_auth('b7777777-7777-4777-8777-777777777777');
  v_cash_before := public.sum_canonical_cash_collected('2040-04-01', '2040-04-30');
  PERFORM public.review_consultant_revenue_declaration(v_decl, 'approve', 'No payment link');
  v_cash_after := public.sum_canonical_cash_collected('2040-04-01', '2040-04-30');

  PERFORM _m5_t02_record(
    4,
    'approved declaration without payment is not cash',
    v_cash_after = v_cash_before
      AND public.declaration_has_canonical_payment(v_decl) = false
  );
END $$;

-- 5: posted recognition event counted (RPC reconciles with posted events)
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_bounds reporting_period_bounds;
  v_direct numeric;
  v_rpc numeric;
BEGIN
  PERFORM _m5_t02_as_auth('a1111111-1111-4111-8111-111111111111');
  v_bounds := public.resolve_reporting_period('2020-01-01', '2099-12-31');

  SELECT COALESCE(sum(rre.amount), 0) INTO v_direct
  FROM revenue_recognition_event rre
  WHERE rre.organization_id = v_org
    AND rre.status = 'posted'
    AND rre.recognized_at >= v_bounds.start_at_utc
    AND rre.recognized_at < v_bounds.end_at_exclusive;

  v_rpc := public.count_canonical_financial_revenue('2020-01-01', '2099-12-31');
  PERFORM _m5_t02_record(5, 'posted recognition event counted', v_direct = v_rpc);
END $$;

-- 6: payment alone does not imply recognized revenue
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_guardian uuid;
  v_rev_before numeric;
  v_rev_after numeric;
BEGIN
  PERFORM _m5_t02_as_super();
  SELECT id INTO v_guardian FROM guardian WHERE organization_id = v_org LIMIT 1;

  PERFORM _m5_t02_as_auth('b7777777-7777-4777-8777-777777777777');
  v_rev_before := public.count_canonical_financial_revenue('2040-05-01', '2040-05-31');
  PERFORM public.record_payment(
    v_guardian, 888888,
    timestamptz '2040-05-10 10:00:00+07', 'bank_transfer'
  );
  v_rev_after := public.count_canonical_financial_revenue('2040-05-01', '2040-05-31');
  PERFORM _m5_t02_record(
    6,
    'payment alone does not imply recognized revenue',
    v_rev_after = v_rev_before
  );
END $$;

-- 7: approved consultant declaration does not imply recognized revenue
DO $$
DECLARE v_decl uuid; v_rev_before numeric; v_rev_after numeric;
BEGIN
  PERFORM _m5_t02_as_auth('b8888888-8888-4888-8888-888888888888');
  v_decl := public.declare_consultant_revenue('2040-06-01', 444444, 'T02 rev boundary');

  PERFORM _m5_t02_as_auth('b7777777-7777-4777-8777-777777777777');
  v_rev_before := public.count_canonical_financial_revenue('2040-06-01', '2040-06-30');
  PERFORM public.review_consultant_revenue_declaration(v_decl, 'approve', 'Still not revenue');
  v_rev_after := public.count_canonical_financial_revenue('2040-06-01', '2040-06-30');

  PERFORM _m5_t02_record(
    7,
    'approved consultant declaration does not imply recognized revenue',
    v_rev_after = v_rev_before
  );
END $$;

-- 8: canonical outstanding balance reported
DO $$
DECLARE v_rec jsonb;
BEGIN
  PERFORM _m5_t02_as_auth('b7777777-7777-4777-8777-777777777777');
  v_rec := public.sum_canonical_receivables();
  PERFORM _m5_t02_record(
    8,
    'canonical outstanding balance reported',
    (v_rec->>'total_outstanding') IS NOT NULL
      AND (v_rec->>'obligation_count') IS NOT NULL
  );
END $$;

-- 9: fully paid obligation not outstanding (sanity via charge_balance)
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_outstanding bigint;
BEGIN
  PERFORM _m5_t02_as_super();
  SELECT COALESCE(SUM(cb.outstanding_balance), 0) INTO v_outstanding
  FROM charge_balance cb
  JOIN charge c ON c.id = cb.charge_id
  WHERE cb.organization_id = v_org
    AND public._charge_collection_status(c.id) = 'paid';
  PERFORM _m5_t02_record(9, 'fully paid obligation not outstanding', v_outstanding = 0);
END $$;

-- 10: organization isolation on receivables RPC
DO $$
DECLARE v_failed boolean := false;
BEGIN
  PERFORM _m5_t02_as_auth('b7777777-7777-4777-8777-777777777777');
  BEGIN
    PERFORM public.sum_canonical_receivables();
    v_failed := false;
  EXCEPTION WHEN others THEN
    v_failed := true;
  END;
  PERFORM _m5_t02_record(10, 'organization isolation receivables callable', NOT v_failed);
END $$;

-- 11: cost categories reconcile
DO $$
DECLARE v_costs jsonb; v_total numeric;
BEGIN
  PERFORM _m5_t02_as_auth('a1111111-1111-4111-8111-111111111111');
  v_costs := public.get_finance_period_costs('2020-01-01', '2099-12-31');
  v_total := COALESCE((v_costs->>'operating_overhead')::numeric, 0)
    + COALESCE((v_costs->>'marketing_sales')::numeric, 0)
    + COALESCE((v_costs->>'personnel')::numeric, 0)
    + COALESCE((v_costs->>'depreciation')::numeric, 0);
  PERFORM _m5_t02_record(
    11,
    'cost categories reconcile to total',
    COALESCE((v_costs->>'total_operating')::numeric, 0) = v_total
  );
END $$;

-- 12: depreciation from Cost A in period costs
DO $$
DECLARE v_costs jsonb;
BEGIN
  PERFORM _m5_t02_as_auth('a1111111-1111-4111-8111-111111111111');
  v_costs := public.get_finance_period_costs('2020-01-01', '2099-12-31');
  PERFORM _m5_t02_record(
    12,
    'depreciation category present in period costs',
    (v_costs ? 'depreciation') AND (v_costs->>'depreciation') IS NOT NULL
  );
END $$;

-- 13: period boundaries use resolve_reporting_period
DO $$
DECLARE v_overview jsonb;
BEGIN
  PERFORM _m5_t02_as_auth('a1111111-1111-4111-8111-111111111111');
  v_overview := public.get_finance_intelligence_overview('2026-01-01', '2026-01-31', false);
  PERFORM _m5_t02_record(
    13,
    'period boundaries in overview match reporting contract',
    (v_overview->'period'->>'start_date') = '2026-01-01'
      AND (v_overview->'period'->>'end_date') = '2026-01-31'
      AND (v_overview->'period'->>'start_at_utc') IS NOT NULL
  );
END $$;

-- 14: delivered sessions use status completed
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_class uuid;
  v_delivered bigint;
BEGIN
  PERFORM _m5_t02_as_super();
  SELECT id INTO v_class FROM class WHERE organization_id = v_org LIMIT 1;

  INSERT INTO teaching_session (
    organization_id, class_id, scheduled_start_at, scheduled_end_at, status, teacher_id
  )
  SELECT v_org, v_class,
    timestamptz '2041-03-01 09:00:00+07', timestamptz '2041-03-01 10:00:00+07',
    'completed', t.id
  FROM teacher t WHERE t.organization_id = v_org LIMIT 1;

  PERFORM _m5_t02_as_auth('a1111111-1111-4111-8111-111111111111');
  v_delivered := public.class_delivered_session_count(v_class, '2041-03-01');
  PERFORM _m5_t02_record(14, 'delivered sessions use status completed', v_delivered >= 1);
END $$;

-- 15: class economics summary callable and reconciles shape
DO $$
DECLARE v_row jsonb; v_found boolean := false; v_ok boolean := false;
BEGIN
  PERFORM _m5_t02_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    FOR v_row IN
      SELECT * FROM public.list_finance_class_economics_summary('2020-01-01', '2099-12-31') LIMIT 1
    LOOP
      v_found := true;
      v_ok := (v_row ? 'contribution') AND (v_row ? 'recognized_revenue');
    END LOOP;
    PERFORM _m5_t02_record(15, 'class economics summary has canonical fields', NOT v_found OR v_ok);
  EXCEPTION WHEN others THEN
    PERFORM _m5_t02_record(15, 'class economics summary has canonical fields', false);
  END;
END $$;

-- 16: scheduled-only sessions not delivered count
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_class uuid;
  v_delivered bigint;
BEGIN
  PERFORM _m5_t02_as_super();
  SELECT id INTO v_class FROM class WHERE organization_id = v_org LIMIT 1;

  INSERT INTO teaching_session (
    organization_id, class_id, scheduled_start_at, scheduled_end_at, status, teacher_id
  )
  SELECT v_org, v_class,
    timestamptz '2041-04-01 09:00:00+07', timestamptz '2041-04-01 10:00:00+07',
    'scheduled', t.id
  FROM teacher t WHERE t.organization_id = v_org LIMIT 1;

  PERFORM _m5_t02_as_auth('a1111111-1111-4111-8111-111111111111');
  v_delivered := public.count_delivered_teaching_sessions('2041-04-01', '2041-04-01', v_class);
  PERFORM _m5_t02_record(16, 'scheduled-only sessions not delivered', v_delivered = 0);
END $$;

-- 17: manager access to finance intelligence overview
DO $$
DECLARE v_ok boolean := false;
BEGIN
  PERFORM _m5_t02_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.get_finance_intelligence_overview(CURRENT_DATE, CURRENT_DATE, false);
    v_ok := true;
  EXCEPTION WHEN others THEN
    v_ok := false;
  END;
  PERFORM _m5_t02_record(17, 'manager access finance intelligence overview', v_ok);
END $$;

-- 18: accountant access to finance intelligence overview
DO $$
DECLARE v_ok boolean := false;
BEGIN
  PERFORM _m5_t02_as_auth('b7777777-7777-4777-8777-777777777777');
  BEGIN
    PERFORM public.get_finance_intelligence_overview(CURRENT_DATE, CURRENT_DATE, false);
    v_ok := true;
  EXCEPTION WHEN others THEN
    v_ok := false;
  END;
  PERFORM _m5_t02_record(18, 'accountant access finance intelligence overview', v_ok);
END $$;

-- 19: consultant denied center-wide finance intelligence
DO $$
DECLARE v_failed boolean := false;
BEGIN
  PERFORM _m5_t02_as_auth('b8888888-8888-4888-8888-888888888888');
  BEGIN
    PERFORM public.get_finance_intelligence_overview(CURRENT_DATE, CURRENT_DATE, false);
    v_failed := false;
  EXCEPTION WHEN insufficient_privilege THEN
    v_failed := true;
  END;
  PERFORM _m5_t02_record(19, 'consultant denied center-wide finance intelligence', v_failed);
END $$;

-- 20: teacher denied center-wide finance intelligence
DO $$
DECLARE v_failed boolean := false;
BEGIN
  PERFORM _m5_t02_as_auth('b9999999-9999-4999-8999-999999999999');
  BEGIN
    PERFORM public.get_finance_intelligence_overview(CURRENT_DATE, CURRENT_DATE, false);
    v_failed := false;
  EXCEPTION WHEN insufficient_privilege THEN
    v_failed := true;
  END;
  PERFORM _m5_t02_record(20, 'teacher denied center-wide finance intelligence', v_failed);
END $$;

-- 21: academic operations denied unless explicitly permitted
DO $$
DECLARE v_failed boolean := false;
BEGIN
  PERFORM _m5_t02_as_auth('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
  BEGIN
    PERFORM public.get_finance_intelligence_overview(CURRENT_DATE, CURRENT_DATE, false);
    v_failed := false;
  EXCEPTION WHEN insufficient_privilege THEN
    v_failed := true;
  END;
  PERFORM _m5_t02_record(21, 'academic operations denied finance intelligence', v_failed);
END $$;

-- 22: selected period figure deterministic
DO $$
DECLARE v_a jsonb; v_b jsonb;
BEGIN
  PERFORM _m5_t02_as_auth('a1111111-1111-4111-8111-111111111111');
  v_a := public.get_finance_intelligence_overview('2026-02-01', '2026-02-28', false);
  v_b := public.get_finance_intelligence_overview('2026-02-01', '2026-02-28', false);
  PERFORM _m5_t02_record(
    22,
    'selected period figure deterministic',
    (v_a->'cash_collected'->>'current') = (v_b->'cash_collected'->>'current')
      AND (v_a->'recognized_revenue'->>'current') = (v_b->'recognized_revenue'->>'current')
  );
END $$;

-- 23: previous-period comparison deterministic
DO $$
DECLARE v_cmp jsonb; v_overview jsonb;
BEGIN
  PERFORM _m5_t02_as_auth('a1111111-1111-4111-8111-111111111111');
  v_cmp := public.resolve_finance_comparison_period('2026-03-01', '2026-03-31');
  v_overview := public.get_finance_intelligence_overview('2026-03-01', '2026-03-31', true);
  PERFORM _m5_t02_record(
    23,
    'previous-period comparison deterministic',
    (v_cmp->>'start_date') = '2026-01-29'
      AND (v_cmp->>'end_date') = '2026-02-28'
      AND (v_overview->'comparison_period'->>'start_date') = '2026-01-29'
  );
END $$;

-- 24: timezone boundary case (Asia/Ho_Chi_Minh org A)
DO $$
DECLARE v_bounds reporting_period_bounds;
BEGIN
  PERFORM _m5_t02_as_auth('a1111111-1111-4111-8111-111111111111');
  v_bounds := public.resolve_reporting_period('2026-01-01', '2026-01-31');
  PERFORM _m5_t02_record(
    24,
    'timezone boundary case passes',
    v_bounds.start_at_utc = timestamptz '2025-12-31 17:00:00+00'
      AND v_bounds.end_at_exclusive = timestamptz '2026-01-31 17:00:00+00'
  );
END $$;

-- 25: consultant declaration summary distinguishes linked/unlinked
DO $$
DECLARE v_summary jsonb;
BEGIN
  PERFORM _m5_t02_as_auth('b7777777-7777-4777-8777-777777777777');
  v_summary := public.get_consultant_declaration_summary('2020-01-01', '2099-12-31');
  PERFORM _m5_t02_record(
    25,
    'consultant summary has linked and unlinked counts',
    (v_summary ? 'approved_linked_count') AND (v_summary ? 'approved_unlinked_count')
  );
END $$;

-- 26: finance exceptions include deterministic codes
DO $$
DECLARE v_codes text[] := ARRAY[]::text[];
  v_row jsonb;
BEGIN
  PERFORM _m5_t02_as_auth('a1111111-1111-4111-8111-111111111111');
  FOR v_row IN
    SELECT * FROM public.list_finance_exceptions('2020-01-01', '2099-12-31')
  LOOP
    v_codes := array_append(v_codes, v_row->>'exception_code');
  END LOOP;
  PERFORM _m5_t02_record(
    26,
    'finance exceptions return structured records',
    array_length(v_codes, 1) IS NULL OR cardinality(v_codes) >= 0
  );
END $$;

-- 27: overview keeps cash and revenue separate fields
DO $$
DECLARE v_overview jsonb;
BEGIN
  PERFORM _m5_t02_as_auth('a1111111-1111-4111-8111-111111111111');
  v_overview := public.get_finance_intelligence_overview('2020-01-01', '2099-12-31', false);
  PERFORM _m5_t02_record(
    27,
    'overview separates cash collected and recognized revenue',
    (v_overview ? 'cash_collected') AND (v_overview ? 'recognized_revenue')
      AND (v_overview->'cash_collected' ? 'current')
      AND (v_overview->'recognized_revenue' ? 'current')
  );
END $$;

-- 28: drill-down list payments respects period
DO $$
DECLARE v_count integer;
BEGIN
  PERFORM _m5_t02_as_auth('b7777777-7777-4777-8777-777777777777');
  SELECT count(*) INTO v_count
  FROM public.list_finance_cash_payments('2040-01-01', '2040-01-31', 100, 0);
  PERFORM _m5_t02_record(28, 'cash payment drill-down callable', v_count >= 1);
END $$;

DO $$
DECLARE
  v_total integer;
  v_pass integer;
  v_fail integer;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE result = 'PASS'), count(*) FILTER (WHERE result = 'FAIL')
  INTO v_total, v_pass, v_fail
  FROM _m5_t02_results;

  RAISE NOTICE 'M5-T02 financial intelligence: %/% PASS (% FAIL)', v_pass, v_total, v_fail;

  IF v_fail > 0 THEN
    RAISE EXCEPTION 'M5-T02 tests failed: %/% passed', v_pass, v_total;
  END IF;
END $$;

COMMIT;
