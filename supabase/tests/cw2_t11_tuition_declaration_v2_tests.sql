-- CW2-T11: Tuition declaration V2 acceptance (50 scenarios)
-- Requires _cw2_t05_org and helpers from cw2_t05_consultant_workspace_read_model_tests.sql

CREATE TEMP TABLE IF NOT EXISTS _cw2_t11_results (
  test_no integer PRIMARY KEY,
  test_name text NOT NULL,
  result text NOT NULL CHECK (result IN ('PASS', 'FAIL'))
);
GRANT ALL ON TABLE _cw2_t11_results TO authenticated, anon;

CREATE OR REPLACE FUNCTION _cw2_t11_record(test_no integer, test_name text, passed boolean)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO _cw2_t11_results (test_no, test_name, result)
  VALUES (test_no, test_name, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END);
END;
$$;

CREATE OR REPLACE FUNCTION _cw2_t11_as_auth(p_auth uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE; SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', p_auth::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_auth::text, 'role', 'authenticated')::text, true);
END;
$$;

CREATE OR REPLACE FUNCTION _cw2_t11_as_postgres()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN RESET ROLE; SET LOCAL ROLE postgres; END;
$$;

CREATE OR REPLACE FUNCTION _cw2_t11_bare_student(
  p_org uuid,
  p_consultant_auth uuid,
  OUT student_id uuid,
  OUT guardian_id uuid,
  OUT enrollment_id uuid,
  OUT terms_id uuid,
  OUT course_id uuid,
  OUT class_id uuid
)
LANGUAGE plpgsql AS $$
DECLARE v_course uuid; v_class uuid;
BEGIN
  PERFORM _cw2_t11_as_postgres();
  INSERT INTO course (organization_id, code, name)
    VALUES (p_org, 'T11' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 4), 'T11 Course')
    RETURNING id INTO v_course;
  course_id := v_course;
  INSERT INTO class (organization_id, course_id, name, status)
    VALUES (p_org, v_course, 'T11 Class', 'active') RETURNING id INTO v_class;
  class_id := v_class;
  INSERT INTO student (organization_id, given_name, family_name, date_of_birth, status)
    VALUES (p_org, 'T11', 'Bare', '2015-01-01', 'active') RETURNING id INTO student_id;
  INSERT INTO guardian (organization_id, given_name, family_name, email, phone)
    VALUES (p_org, 'T11', 'Guardian', 't11-bare@test.local', '0905111101') RETURNING id INTO guardian_id;
  INSERT INTO student_guardian (organization_id, student_id, guardian_id, is_primary_contact, is_billing_contact)
    VALUES (p_org, student_id, guardian_id, true, true);
  INSERT INTO enrollment (organization_id, student_id, class_id, start_date, status)
    VALUES (p_org, student_id, v_class, CURRENT_DATE, 'active') RETURNING id INTO enrollment_id;
  INSERT INTO enrollment_financial_terms (
    organization_id, enrollment_id, agreed_tuition_amount, discount_amount, net_tuition_amount, agreement_date, status
  ) VALUES (p_org, enrollment_id, 0, 0, 0, CURRENT_DATE, 'active') RETURNING id INTO terms_id;
  PERFORM _cw2_t11_as_auth(p_consultant_auth);
END;
$$;

CREATE OR REPLACE FUNCTION _cw2_t11_teacher(p_org uuid)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_id uuid;
BEGIN
  PERFORM _cw2_t11_as_postgres();
  INSERT INTO teacher (organization_id, given_name, family_name, status)
    VALUES (p_org, 'T11', 'Teacher', 'active') RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION _cw2_t11_session(
  p_org uuid, p_class uuid, p_teacher uuid, p_status text DEFAULT 'completed'
)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_id uuid; v_start timestamptz := date_trunc('day', now()) + interval '10 hours';
BEGIN
  PERFORM _cw2_t11_as_postgres();
  INSERT INTO teaching_session (
    organization_id, class_id, teacher_id, scheduled_start_at, scheduled_end_at, status
  ) VALUES (p_org, p_class, p_teacher, v_start, v_start + interval '1 hour', p_status)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION _cw2_t11_confirm(
  p_org uuid,
  p_acct_auth uuid,
  p_decl uuid,
  p_consultant_auth uuid
)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM _cw2_t11_as_auth(p_acct_auth);
  BEGIN
    PERFORM public.confirm_consultant_payment_declaration(p_decl);
  EXCEPTION
    WHEN OTHERS THEN
      PERFORM _cw2_t11_as_auth(p_consultant_auth);
      RAISE;
  END;
  PERFORM _cw2_t11_as_auth(p_consultant_auth);
END;
$$;

CREATE OR REPLACE FUNCTION _cw2_t11_meets_backfill(p_terms uuid)
RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.enrollment_financial_terms t
    WHERE t.id = p_terms
      AND t.status = 'active'
      AND t.net_tuition_amount > 0
      AND t.tuition_plan_established_at IS NULL
      AND EXISTS (
        SELECT 1 FROM public.charge c
        WHERE c.enrollment_financial_terms_id = t.id
          AND c.organization_id = t.organization_id
          AND c.status <> 'void' AND c.amount > 0
      )
      AND EXISTS (
        SELECT 1
        FROM public.payment_allocation pa
        JOIN public.charge c ON c.id = pa.charge_id
        WHERE c.enrollment_financial_terms_id = t.id
          AND c.organization_id = t.organization_id
          AND pa.status = 'posted' AND pa.amount > 0
      )
  );
$$;

-- 1–6: course mode — unestablished read model and initial setup gates
DO $$
DECLARE f record; b record; r jsonb; v_ctx jsonb; v_decl uuid; ok boolean := false;
BEGIN
  SELECT * INTO f FROM _cw2_t05_org();
  SELECT * INTO b FROM _cw2_t11_bare_student(f.org_id, f.consultant_a_auth);
  PERFORM _cw2_t05_add_portfolio_entry(f.org_id, f.consultant_a_user, 1101, NULL, b.student_id);
  PERFORM _cw2_t11_as_auth(f.consultant_a_auth);
  r := public.list_consultant_workspace_portfolio();
  PERFORM _cw2_t11_record(
    1, 'unestablished chua_nop_phi',
    (r->'rows'->0->>'tuition_payment_state') = 'chua_nop_phi'
    AND COALESCE((r->'rows'->0->>'tuition_total_net')::bigint, -1) = 0
  );
  v_ctx := public.get_cw2_tuition_declaration_context(b.enrollment_id);
  PERFORM _cw2_t11_record(
    2, 'context unset can change mode',
    (v_ctx->>'tuition_established')::boolean = false
    AND (v_ctx->>'can_change_billing_mode')::boolean = true
  );
  BEGIN
    PERFORM public.save_consultant_payment_declaration_draft(
      NULL, CURRENT_DATE, 1000000, 'pay', NULL, b.student_id, b.course_id, b.class_id,
      b.enrollment_id, b.terms_id, b.guardian_id, NULL, 't11-no-setup', NULL,
      NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'payment_only'
    );
  EXCEPTION WHEN OTHERS THEN ok := SQLERRM LIKE '%initial_tuition_setup_required%'; END;
  PERFORM _cw2_t11_record(3, 'payment_only requires initial setup', ok);
  v_decl := public.save_consultant_payment_declaration_draft(
    NULL, CURRENT_DATE, 2000000, 'init', NULL, b.student_id, b.course_id, b.class_id,
    b.enrollment_id, b.terms_id, b.guardian_id, NULL, 't11-init-course', NULL,
    'course_lump_sum', 10000000, NULL, NULL, NULL, NULL, NULL, 'initial_tuition_setup'
  );
  PERFORM _cw2_t11_record(
    4, 'initial course draft stored',
    (SELECT declaration_kind FROM consultant_revenue_declaration WHERE id = v_decl) = 'initial_tuition_setup'
    AND (SELECT tuition_billing_mode FROM consultant_revenue_declaration WHERE id = v_decl) = 'course_lump_sum'
  );
  PERFORM public.submit_consultant_payment_declaration(v_decl);
  r := public.list_consultant_workspace_portfolio();
  PERFORM _cw2_t11_record(
    5, 'pending initial coc_cho_xac_nhan',
    (r->'rows'->0->>'tuition_payment_state') = 'coc_cho_xac_nhan'
    AND (r->'rows'->0->>'declaration_status') = 'pending'
  );
  ok := false;
  BEGIN
    PERFORM public.save_consultant_payment_declaration_draft(
      NULL, CURRENT_DATE, 2000000, 'dup', NULL, b.student_id, b.course_id, b.class_id,
      b.enrollment_id, b.terms_id, b.guardian_id, NULL, 't11-dup-init', NULL,
      'course_lump_sum', 10000000, NULL, NULL, NULL, NULL, NULL, 'initial_tuition_setup'
    );
  EXCEPTION WHEN OTHERS THEN ok := SQLERRM LIKE '%initial_tuition_plan_already_pending%'; END;
  PERFORM _cw2_t11_record(6, 'duplicate initial setup rejected', ok);
END $$;

-- 7–12: course confirm path, depends_on, established gates
DO $$
DECLARE
  f record; b record; acct record; v_init uuid; v_pay uuid; r jsonb; ok boolean := false;
  v_acct record;
BEGIN
  SELECT * INTO f FROM _cw2_t05_org();
  SELECT * INTO b FROM _cw2_t11_bare_student(f.org_id, f.consultant_a_auth);
  SELECT * INTO acct FROM _cw2_t05_accountant_for_org(f.org_id);
  PERFORM _cw2_t11_as_auth(f.consultant_a_auth);
  v_init := public.save_consultant_payment_declaration_draft(
    NULL, CURRENT_DATE, 2000000, 'init', NULL, b.student_id, b.course_id, b.class_id,
    b.enrollment_id, b.terms_id, b.guardian_id, NULL, 't11-init-7', NULL,
    'course_lump_sum', 10000000, NULL, NULL, NULL, NULL, NULL, 'initial_tuition_setup'
  );
  PERFORM public.submit_consultant_payment_declaration(v_init);
  v_pay := public.save_consultant_payment_declaration_draft(
    NULL, CURRENT_DATE, 1500000, 'pay', NULL, b.student_id, b.course_id, b.class_id,
    b.enrollment_id, b.terms_id, b.guardian_id, NULL, 't11-pay-7', NULL,
    NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'payment_only'
  );
  PERFORM _cw2_t11_record(
    7, 'payment depends on pending initial',
    (SELECT depends_on_declaration_id FROM consultant_revenue_declaration WHERE id = v_pay) = v_init
  );
  PERFORM public.submit_consultant_payment_declaration(v_pay);
  ok := false;
  BEGIN
    PERFORM _cw2_t11_confirm(f.org_id, acct.accountant_auth, v_pay, f.consultant_a_auth);
  EXCEPTION WHEN OTHERS THEN ok := SQLERRM LIKE '%depends_on_declaration_not_confirmed%'; END;
  PERFORM _cw2_t11_record(8, 'child confirm blocked before parent', ok);
  PERFORM _cw2_t11_confirm(f.org_id, acct.accountant_auth, v_init, f.consultant_a_auth);
  PERFORM _cw2_t11_record(
    9, 'confirm initial establishes billing',
    public._cw2_enrollment_tuition_established(f.org_id, b.enrollment_id)
    AND public._cw2_enrollment_billing_mode(f.org_id, b.enrollment_id) = 'course_lump_sum'
    AND (public._cw2_portfolio_finance_snapshot(f.org_id, b.enrollment_id)->>'canonical_net_tuition')::bigint = 10000000
  );
  PERFORM _cw2_t05_add_portfolio_entry(f.org_id, f.consultant_a_user, 1107, NULL, b.student_id);
  PERFORM _cw2_t11_as_auth(f.consultant_a_auth);
  r := public.list_consultant_workspace_portfolio();
  PERFORM _cw2_t11_record(
    10, 'after deposit da_coc',
    (r->'rows'->0->>'tuition_payment_state') = 'da_coc'
    AND (r->'rows'->0->>'tuition_paid')::bigint = 2000000
    AND (r->'rows'->0->>'tuition_outstanding')::bigint = 8000000
  );
  ok := false;
  BEGIN
    PERFORM public.save_consultant_payment_declaration_draft(
      NULL, CURRENT_DATE, 2000000, 'again', NULL, b.student_id, b.course_id, b.class_id,
      b.enrollment_id, b.terms_id, b.guardian_id, NULL, 't11-init-again', NULL,
      'course_lump_sum', 10000000, NULL, NULL, NULL, NULL, NULL, 'initial_tuition_setup'
    );
  EXCEPTION WHEN OTHERS THEN ok := SQLERRM LIKE '%tuition_plan_already_established%'; END;
  PERFORM _cw2_t11_record(11, 'initial rejected when established', ok);
  PERFORM _cw2_t11_confirm(f.org_id, acct.accountant_auth, v_pay, f.consultant_a_auth);
  r := public.list_consultant_workspace_portfolio();
  PERFORM _cw2_t11_record(
    12, 'second payment nop_phi partial',
    (r->'rows'->0->>'tuition_payment_state') = 'nop_phi'
    AND (r->'rows'->0->>'tuition_paid')::bigint = 3500000
  );
END $$;

-- 13–18: course full pay, context, multi-pending, labels
DO $$
DECLARE
  f record; b record; acct record; v_init uuid; v_p1 uuid; v_p2 uuid; r jsonb; v_fin jsonb;
BEGIN
  SELECT * INTO f FROM _cw2_t05_org();
  SELECT * INTO b FROM _cw2_t11_bare_student(f.org_id, f.consultant_a_auth);
  SELECT * INTO acct FROM _cw2_t05_accountant_for_org(f.org_id);
  PERFORM _cw2_t11_as_auth(f.consultant_a_auth);
  v_init := public.save_consultant_payment_declaration_draft(
    NULL, CURRENT_DATE, 2000000, 'init', NULL, b.student_id, b.course_id, b.class_id,
    b.enrollment_id, b.terms_id, b.guardian_id, NULL, 't11-full-init', NULL,
    'course_lump_sum', 10000000, NULL, NULL, NULL, NULL, NULL, 'initial_tuition_setup'
  );
  PERFORM public.submit_consultant_payment_declaration(v_init);
  PERFORM _cw2_t11_confirm(f.org_id, acct.accountant_auth, v_init, f.consultant_a_auth);
  v_p1 := public.save_consultant_payment_declaration_draft(
    NULL, CURRENT_DATE, 3000000, 'p1', NULL, b.student_id, NULL, NULL,
    b.enrollment_id, b.terms_id, b.guardian_id, NULL, 't11-p1', NULL,
    NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'payment_only'
  );
  v_p2 := public.save_consultant_payment_declaration_draft(
    NULL, CURRENT_DATE, 2000000, 'p2', NULL, b.student_id, NULL, NULL,
    b.enrollment_id, b.terms_id, b.guardian_id, NULL, 't11-p2', NULL,
    NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'payment_only'
  );
  PERFORM public.submit_consultant_payment_declaration(v_p1);
  PERFORM public.submit_consultant_payment_declaration(v_p2);
  PERFORM _cw2_t05_add_portfolio_entry(f.org_id, f.consultant_a_user, 1113, NULL, b.student_id);
  PERFORM _cw2_t11_as_auth(f.consultant_a_auth);
  r := public.list_consultant_workspace_portfolio();
  PERFORM _cw2_t11_record(
    13, 'multi pending sums pending amount',
    (r->'rows'->0->>'tuition_pending_declaration')::bigint = 5000000
    AND (r->'rows'->0->>'tuition_payment_state') = 'da_coc'
  );
  PERFORM _cw2_t11_confirm(f.org_id, acct.accountant_auth, v_p1, f.consultant_a_auth);
  PERFORM _cw2_t11_confirm(f.org_id, acct.accountant_auth, v_p2, f.consultant_a_auth);
  v_p1 := public.save_consultant_payment_declaration_draft(
    NULL, CURRENT_DATE, 3000000, 'finish', NULL, b.student_id, NULL, NULL,
    b.enrollment_id, b.terms_id, b.guardian_id, NULL, 't11-finish', NULL,
    NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'payment_only'
  );
  PERFORM public.submit_consultant_payment_declaration(v_p1);
  PERFORM _cw2_t11_confirm(f.org_id, acct.accountant_auth, v_p1, f.consultant_a_auth);
  PERFORM _cw2_t11_as_auth(f.consultant_a_auth);
  r := public.list_consultant_workspace_portfolio();
  PERFORM _cw2_t11_record(
    14, 'full course full_phi',
    (r->'rows'->0->>'tuition_payment_state') = 'full_phi'
    AND (r->'rows'->0->>'tuition_outstanding')::bigint = 0
  );
  v_fin := public.refresh_cw2_payment_declaration_finance(b.terms_id);
  PERFORM _cw2_t11_record(
    15, 'refresh finance established course',
    (v_fin->>'tuition_established')::boolean = true
    AND (v_fin->>'billing_mode') = 'course_lump_sum'
  );
  PERFORM _cw2_t11_as_auth(f.consultant_a_auth);
  PERFORM _cw2_t11_record(
    16, 'context locked billing mode',
    (public.get_cw2_tuition_declaration_context(b.enrollment_id)->>'can_change_billing_mode')::boolean = false
  );
  PERFORM _cw2_t11_record(
    17, 'state label da_coc',
    public._cw2_tuition_payment_state_label('da_coc') = U&'\0110\00e3 c\1ecdc'
  );
  PERFORM _cw2_t11_record(
    18, 'portfolio billing mode field',
    (r->'rows'->0->>'tuition_billing_mode') = 'course_lump_sum'
  );
END $$;

-- 19–25: periodic A (lesson) — setup, payment ledger, attendance reversal
DO $$
DECLARE
  f record; b record; acct record; v_init uuid; v_pay uuid; v_teacher uuid; v_sess uuid;
  v_lessons integer; v_carry bigint; v_lessons_before integer; r jsonb;
BEGIN
  SELECT * INTO f FROM _cw2_t05_org();
  SELECT * INTO b FROM _cw2_t11_bare_student(f.org_id, f.consultant_a_auth);
  SELECT * INTO acct FROM _cw2_t05_accountant_for_org(f.org_id);
  PERFORM _cw2_t11_as_auth(f.consultant_a_auth);
  v_init := public.save_consultant_payment_declaration_draft(
    NULL, CURRENT_DATE, 2000000, 'plesson', NULL, b.student_id, b.course_id, b.class_id,
    b.enrollment_id, b.terms_id, b.guardian_id, NULL, 't11-lesson-init', NULL,
    'periodic', NULL, 'lesson', 4, 2000000, NULL, NULL, 'initial_tuition_setup'
  );
  PERFORM public.submit_consultant_payment_declaration(v_init);
  PERFORM _cw2_t11_confirm(f.org_id, acct.accountant_auth, v_init, f.consultant_a_auth);
  PERFORM _cw2_t11_record(
    19, 'periodic lesson billing established',
    public._cw2_enrollment_billing_mode(f.org_id, b.enrollment_id) = 'periodic'
    AND EXISTS (
      SELECT 1 FROM enrollment_tuition_billing etb
      WHERE etb.enrollment_id = b.enrollment_id AND etb.period_unit = 'lesson'
    )
  );
  SELECT lessons_remaining_in_block INTO v_lessons
  FROM enrollment_periodic_tuition_balance WHERE enrollment_id = b.enrollment_id;
  PERFORM _cw2_t11_record(20, 'lesson payment grants block', COALESCE(v_lessons, 0) = 4);
  v_pay := public.save_consultant_payment_declaration_draft(
    NULL, CURRENT_DATE, 500000, 'pend', NULL, b.student_id, NULL, NULL,
    b.enrollment_id, b.terms_id, b.guardian_id, NULL, 't11-lesson-pend', NULL,
    NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'payment_only'
  );
  PERFORM public.submit_consultant_payment_declaration(v_pay);
  PERFORM _cw2_t05_add_portfolio_entry(f.org_id, f.consultant_a_user, 1119, NULL, b.student_id);
  PERFORM _cw2_t11_as_auth(f.consultant_a_auth);
  r := public.list_consultant_workspace_portfolio();
  PERFORM _cw2_t11_record(
    21, 'periodic pending cho_xac_nhan',
    (r->'rows'->0->>'tuition_payment_state') = 'cho_xac_nhan'
  );
  PERFORM _cw2_t11_confirm(f.org_id, acct.accountant_auth, v_pay, f.consultant_a_auth);
  SELECT carry_forward_credit INTO v_carry
  FROM enrollment_periodic_tuition_balance
  WHERE organization_id = f.org_id AND enrollment_id = b.enrollment_id;
  PERFORM _cw2_t11_record(22, 'overpay builds carry credit', COALESCE(v_carry, 0) = 500000);
  SELECT lessons_remaining_in_block INTO v_lessons_before
  FROM enrollment_periodic_tuition_balance
  WHERE organization_id = f.org_id AND enrollment_id = b.enrollment_id;
  v_teacher := _cw2_t11_teacher(f.org_id);
  v_sess := _cw2_t11_session(f.org_id, b.class_id, v_teacher, 'completed');
  PERFORM _cw2_t11_as_postgres();
  INSERT INTO attendance (organization_id, teaching_session_id, enrollment_id, status)
    VALUES (f.org_id, v_sess, b.enrollment_id, 'present');
  PERFORM _cw2_t11_as_auth(f.consultant_a_auth);
  SELECT lessons_remaining_in_block INTO v_lessons
  FROM enrollment_periodic_tuition_balance
  WHERE organization_id = f.org_id AND enrollment_id = b.enrollment_id;
  PERFORM _cw2_t11_record(
    23, 'present session consumes lesson',
    COALESCE(v_lessons_before, 0) > 0 AND v_lessons = v_lessons_before - 1
  );
  PERFORM _cw2_t11_as_postgres();
  UPDATE attendance SET status = 'absent' WHERE teaching_session_id = v_sess AND enrollment_id = b.enrollment_id;
  PERFORM _cw2_t11_as_auth(f.consultant_a_auth);
  SELECT lessons_remaining_in_block INTO v_lessons
  FROM enrollment_periodic_tuition_balance
  WHERE organization_id = f.org_id AND enrollment_id = b.enrollment_id;
  PERFORM _cw2_t11_record(24, 'attendance correction reverses lesson', v_lessons = v_lessons_before);
  PERFORM _cw2_t11_as_postgres();
  UPDATE attendance SET status = 'present'
    WHERE teaching_session_id = v_sess AND enrollment_id = b.enrollment_id;
  PERFORM _cw2_t11_as_auth(f.consultant_a_auth);
  SELECT lessons_remaining_in_block INTO v_lessons
  FROM enrollment_periodic_tuition_balance
  WHERE organization_id = f.org_id AND enrollment_id = b.enrollment_id;
  PERFORM public._cw2_periodic_reverse_session_consumption(
    f.org_id, b.enrollment_id, v_sess, 'session_invalidated'
  );
  SELECT lessons_remaining_in_block INTO v_lessons
  FROM enrollment_periodic_tuition_balance
  WHERE organization_id = f.org_id AND enrollment_id = b.enrollment_id;
  PERFORM _cw2_t11_record(25, 'session invalidate reverses consumption', v_lessons = v_lessons_before);
END $$;

-- 26–31: periodic B/C — month activation, week key, school year
DO $$
DECLARE
  f record; b record; acct record; v_init uuid; v_teacher uuid; v_sess uuid; v_key text;
  v_obl bigint; v_sat bigint; ok boolean := false; v_year uuid; v_pay jsonb; v_sess_date date;
BEGIN
  SELECT * INTO f FROM _cw2_t05_org();
  SELECT * INTO b FROM _cw2_t11_bare_student(f.org_id, f.consultant_a_auth);
  SELECT * INTO acct FROM _cw2_t05_accountant_for_org(f.org_id);
  PERFORM _cw2_t11_as_auth(f.consultant_a_auth);
  v_init := public.save_consultant_payment_declaration_draft(
    NULL, CURRENT_DATE, 1000000, 'pmonth', NULL, b.student_id, b.course_id, b.class_id,
    b.enrollment_id, b.terms_id, b.guardian_id, NULL, 't11-month-init', NULL,
    'periodic', NULL, 'month', 1, 3000000, NULL, NULL, 'initial_tuition_setup'
  );
  PERFORM public.submit_consultant_payment_declaration(v_init);
  PERFORM _cw2_t11_confirm(f.org_id, acct.accountant_auth, v_init, f.consultant_a_auth);
  v_teacher := _cw2_t11_teacher(f.org_id);
  v_sess := _cw2_t11_session(f.org_id, b.class_id, v_teacher, 'completed');
  PERFORM _cw2_t11_as_postgres();
  INSERT INTO attendance (organization_id, teaching_session_id, enrollment_id, status)
    VALUES (f.org_id, v_sess, b.enrollment_id, 'present');
  SELECT public.teaching_session_operational_date(
    ts.scheduled_start_at,
    o.timezone
  ) INTO v_sess_date
  FROM teaching_session ts
  JOIN organization o ON o.id = ts.organization_id
  WHERE ts.id = v_sess;
  PERFORM _cw2_t11_as_auth(f.consultant_a_auth);
  v_key := public._cw2_periodic_period_key('month', v_sess_date, NULL);
  SELECT obligation_amount, satisfied_amount INTO v_obl, v_sat
  FROM enrollment_periodic_period_obligation
  WHERE organization_id = f.org_id AND enrollment_id = b.enrollment_id AND period_key = v_key;
  PERFORM _cw2_t11_record(
    26, 'month session activates period obligation',
    v_obl = 3000000 AND COALESCE(v_sat, 0) = 1000000
  );
  PERFORM _cw2_t11_record(
    27, 'month underpaid con_thieu',
    public._cw2_derive_tuition_payment_state(f.org_id, b.enrollment_id, 0, 0, 0, 0) = 'con_thieu'
  );
  v_pay := public._cw2_periodic_apply_confirmed_payment(f.org_id, b.enrollment_id, 2000000, v_sess_date);
  PERFORM _cw2_t11_record(
    28, 'month paid da_du_ky',
    public._cw2_derive_tuition_payment_state(f.org_id, b.enrollment_id, 0, 0, 0, 0) = 'da_du_ky'
    AND (v_pay->>'satisfied_amount')::bigint >= 3000000
  );
  SELECT * INTO b FROM _cw2_t11_bare_student(f.org_id, f.consultant_a_auth);
  PERFORM _cw2_t11_as_auth(f.consultant_a_auth);
  v_init := public.save_consultant_payment_declaration_draft(
    NULL, CURRENT_DATE, 800000, 'pweek', NULL, b.student_id, b.course_id, b.class_id,
    b.enrollment_id, b.terms_id, b.guardian_id, NULL, 't11-week-init', NULL,
    'periodic', NULL, 'week', 1, 800000, NULL, NULL, 'initial_tuition_setup'
  );
  PERFORM public.submit_consultant_payment_declaration(v_init);
  PERFORM _cw2_t11_confirm(f.org_id, acct.accountant_auth, v_init, f.consultant_a_auth);
  v_key := (public._cw2_periodic_apply_confirmed_payment(f.org_id, b.enrollment_id, 800000, CURRENT_DATE)->>'period_key');
  PERFORM _cw2_t11_record(
    29, 'week payment period_key',
    v_key = public._cw2_periodic_period_key('week', CURRENT_DATE, NULL)
  );
  SELECT * INTO b FROM _cw2_t11_bare_student(f.org_id, f.consultant_a_auth);
  ok := false;
  BEGIN
    PERFORM public.save_consultant_payment_declaration_draft(
      NULL, CURRENT_DATE, 500000, 'psy', NULL, b.student_id, b.course_id, b.class_id,
      b.enrollment_id, b.terms_id, b.guardian_id, NULL, 't11-sy-miss', NULL,
      'periodic', NULL, 'school_year', 1, 500000, NULL, NULL, 'initial_tuition_setup'
    );
  EXCEPTION WHEN OTHERS THEN ok := SQLERRM LIKE '%academic_year_required%'; END;
  PERFORM _cw2_t11_record(30, 'school_year requires academic year', ok);
  PERFORM _cw2_t11_as_postgres();
  INSERT INTO organization_academic_year (organization_id, label, start_date, end_date)
    VALUES (f.org_id, 'SY T11', CURRENT_DATE - 30, CURRENT_DATE + 335)
    RETURNING id INTO v_year;
  PERFORM _cw2_t11_as_auth(f.consultant_a_auth);
  v_init := public.save_consultant_payment_declaration_draft(
    NULL, CURRENT_DATE, 500000, 'psy', NULL, b.student_id, b.course_id, b.class_id,
    b.enrollment_id, b.terms_id, b.guardian_id, NULL, 't11-sy-ok', NULL,
    'periodic', NULL, 'school_year', 1, 500000, v_year, NULL, 'initial_tuition_setup'
  );
  PERFORM public.submit_consultant_payment_declaration(v_init);
  PERFORM _cw2_t11_confirm(f.org_id, acct.accountant_auth, v_init, f.consultant_a_auth);
  PERFORM _cw2_t11_record(
    31, 'school_year billing stores year id',
    EXISTS (
      SELECT 1 FROM enrollment_tuition_billing etb
      WHERE etb.enrollment_id = b.enrollment_id
        AND etb.period_unit = 'school_year'
        AND etb.organization_academic_year_id = v_year
    )
  );
END $$;

-- 32–36: conflicting proposal, RLS, cross-org, review preview
DO $$
DECLARE
  f record; f2 record; b record; acct record; acct2 record; v_init uuid;
  ok boolean := false; ok_rls boolean := false; v_detail jsonb;
BEGIN
  SELECT * INTO f FROM _cw2_t05_org();
  SELECT * INTO b FROM _cw2_t11_bare_student(f.org_id, f.consultant_a_auth);
  SELECT * INTO acct FROM _cw2_t05_accountant_for_org(f.org_id);
  PERFORM _cw2_t11_as_auth(f.consultant_a_auth);
  v_init := public.save_consultant_payment_declaration_draft(
    NULL, CURRENT_DATE, 2000000, 'init', NULL, b.student_id, b.course_id, b.class_id,
    b.enrollment_id, b.terms_id, b.guardian_id, NULL, 't11-conflict-init', NULL,
    'course_lump_sum', 10000000, NULL, NULL, NULL, NULL, NULL, 'initial_tuition_setup'
  );
  PERFORM public.submit_consultant_payment_declaration(v_init);
  BEGIN
    PERFORM public.save_consultant_payment_declaration_draft(
      NULL, CURRENT_DATE, 1000000, 'bad', NULL, b.student_id, b.course_id, b.class_id,
      b.enrollment_id, b.terms_id, b.guardian_id, NULL, 't11-conflict-pay', NULL,
      NULL, 9999999, NULL, NULL, NULL, NULL, NULL, 'payment_only'
    );
  EXCEPTION WHEN OTHERS THEN ok := SQLERRM LIKE '%conflicting_tuition_proposal%'; END;
  PERFORM _cw2_t11_record(32, 'conflicting tuition proposal rejected', ok);
  BEGIN
    PERFORM _cw2_t11_as_auth(f.consultant_a_auth);
    INSERT INTO enrollment_tuition_billing (
      organization_id, enrollment_id, enrollment_financial_terms_id, billing_mode, established_at
    ) VALUES (f.org_id, b.enrollment_id, b.terms_id, 'course_lump_sum', now());
  EXCEPTION WHEN OTHERS THEN ok_rls := true; END;
  PERFORM _cw2_t11_record(33, 'consultant cannot insert tuition billing', ok_rls);
  SELECT * INTO f2 FROM _cw2_t05_org();
  SELECT * INTO b FROM _cw2_t11_bare_student(f2.org_id, f2.consultant_a_auth);
  SELECT * INTO acct2 FROM _cw2_t05_accountant_for_org(f2.org_id);
  PERFORM _cw2_t11_as_auth(f.consultant_a_auth);
  PERFORM _cw2_t11_record(
    34, 'cross org snapshot isolated',
    public._cw2_portfolio_finance_snapshot(f.org_id, b.enrollment_id) IS NULL
  );
  PERFORM _cw2_t11_as_auth(f2.consultant_a_auth);
  v_init := public.save_consultant_payment_declaration_draft(
    NULL, CURRENT_DATE, 2000000, 'prev', NULL, b.student_id, b.course_id, b.class_id,
    b.enrollment_id, b.terms_id, b.guardian_id, NULL, 't11-preview-init', NULL,
    'periodic', NULL, 'lesson', 4, 2000000, NULL, NULL, 'initial_tuition_setup'
  );
  PERFORM public.submit_consultant_payment_declaration(v_init);
  PERFORM _cw2_t11_as_auth(acct2.accountant_auth);
  v_detail := public.get_cw2_finance_declaration_review_detail(v_init);
  PERFORM _cw2_t11_record(
    35, 'review detail periodic preview',
    v_detail->'periodic_effect_preview' IS NOT NULL
    AND (v_detail->'declaration'->>'tuition_billing_mode') = 'periodic'
  );
  PERFORM _cw2_t11_as_auth(f2.consultant_a_auth);
  PERFORM _cw2_t11_record(
    36, 'periodic finance outstanding zero',
    (public.refresh_cw2_payment_declaration_finance(b.terms_id)->>'tuition_outstanding')::bigint = 0
  );
END $$;

-- 37–42: migration 82 backfill criteria + legacy established row + het_hoc_phi
DO $$
DECLARE
  f record; b record; acct record; v_terms uuid; v_charge uuid; v_pay jsonb; ok boolean;
  v_init uuid; v_teacher uuid; v_sess uuid; v_i integer; r jsonb;
BEGIN
  SELECT * INTO f FROM _cw2_t05_org();
  SELECT * INTO acct FROM _cw2_t05_accountant_for_org(f.org_id);
  PERFORM _cw2_t11_as_postgres();
  SELECT * INTO b FROM _cw2_t11_bare_student(f.org_id, f.consultant_a_auth);
  PERFORM _cw2_t11_as_postgres();
  PERFORM set_config('row_security', 'off', true);
  PERFORM set_config('cw2.authoritative_tuition_establishment', 'on', true);
  UPDATE enrollment_financial_terms SET net_tuition_amount = 5000000, agreed_tuition_amount = 5000000 WHERE id = b.terms_id;
  INSERT INTO enrollment_payment_schedule_item (
    organization_id, enrollment_financial_terms_id, sequence_number, due_date, amount
  ) VALUES (f.org_id, b.terms_id, 1, CURRENT_DATE, 5000000);
  INSERT INTO charge (
    organization_id, student_id, enrollment_id, guardian_id, enrollment_financial_terms_id,
    enrollment_payment_schedule_item_id, charge_source_code, amount, currency_code,
    charged_at, due_date, status, agreed_tuition_snapshot, net_tuition_snapshot
  )
  SELECT f.org_id, b.student_id, b.enrollment_id, b.guardian_id, b.terms_id, si.id,
    'tuition', si.amount, 'VND', CURRENT_DATE, si.due_date, 'open', 5000000, 5000000
  FROM enrollment_payment_schedule_item si WHERE si.enrollment_financial_terms_id = b.terms_id
  RETURNING id INTO v_charge;
  PERFORM _cw2_t11_record(
    37, 'backfill criteria false without allocation',
    NOT _cw2_t11_meets_backfill(b.terms_id)
    AND NOT public._cw2_enrollment_tuition_established(f.org_id, b.enrollment_id)
  );
  PERFORM set_config('cw2.authoritative_tuition_establishment', 'on', true);
  UPDATE enrollment_financial_terms SET net_tuition_amount = 0, agreed_tuition_amount = 0 WHERE id = b.terms_id;
  PERFORM _cw2_t11_record(
    38, 'zero net excluded from backfill',
    NOT _cw2_t11_meets_backfill(b.terms_id)
  );
  PERFORM set_config('cw2.authoritative_tuition_establishment', 'on', true);
  UPDATE enrollment_financial_terms
  SET net_tuition_amount = 5000000, agreed_tuition_amount = 5000000, tuition_plan_established_at = NULL
  WHERE id = b.terms_id;
  PERFORM _cw2_t11_as_postgres();
  PERFORM set_config('row_security', 'off', true);
  INSERT INTO payment (
    organization_id, guardian_id, student_id, amount, currency_code, paid_at, method_code, status
  ) VALUES (
    f.org_id, b.guardian_id, b.student_id, 1000000, 'VND', now(), 'cash', 'posted'
  );
  INSERT INTO payment_allocation (organization_id, payment_id, charge_id, amount, status)
  SELECT f.org_id, p.id, v_charge, 1000000, 'posted'
  FROM payment p
  WHERE p.organization_id = f.org_id AND p.guardian_id = b.guardian_id
  ORDER BY p.created_at DESC
  LIMIT 1;
  PERFORM _cw2_t11_record(
    39, 'backfill criteria true with posted pay',
    _cw2_t11_meets_backfill(b.terms_id)
  );
  PERFORM _cw2_t11_as_postgres();
  PERFORM set_config('row_security', 'off', true);
  UPDATE public.enrollment_financial_terms t
  SET tuition_plan_established_at = COALESCE(t.charges_generated_at, t.updated_at, t.created_at)
  WHERE t.id = b.terms_id
    AND _cw2_t11_meets_backfill(b.terms_id);
  INSERT INTO public.enrollment_tuition_billing (
    organization_id, enrollment_id, enrollment_financial_terms_id, billing_mode, established_at
  )
  SELECT t.organization_id, t.enrollment_id, t.id, 'course_lump_sum', t.tuition_plan_established_at
  FROM public.enrollment_financial_terms t
  WHERE t.id = b.terms_id
  ON CONFLICT (organization_id, enrollment_id) DO NOTHING;
  PERFORM _cw2_t11_record(
    40, 'backfill path establishes tuition',
    public._cw2_enrollment_tuition_established(f.org_id, b.enrollment_id)
    AND EXISTS (SELECT 1 FROM enrollment_tuition_billing WHERE enrollment_id = b.enrollment_id)
  );
  PERFORM set_config('row_security', 'on', true);
  SELECT * INTO b FROM _cw2_t11_bare_student(f.org_id, f.consultant_a_auth);
  PERFORM _cw2_t11_as_auth(f.consultant_a_auth);
  v_init := public.save_consultant_payment_declaration_draft(
    NULL, CURRENT_DATE, 2000000, 'het', NULL, b.student_id, b.course_id, b.class_id,
    b.enrollment_id, b.terms_id, b.guardian_id, NULL, 't11-het-init', NULL,
    'periodic', NULL, 'lesson', 1, 2000000, NULL, NULL, 'initial_tuition_setup'
  );
  PERFORM public.submit_consultant_payment_declaration(v_init);
  PERFORM _cw2_t11_confirm(f.org_id, acct.accountant_auth, v_init, f.consultant_a_auth);
  v_teacher := _cw2_t11_teacher(f.org_id);
  FOR v_i IN 1..1 LOOP
    v_sess := _cw2_t11_session(f.org_id, b.class_id, v_teacher, 'completed');
    PERFORM _cw2_t11_as_postgres();
    INSERT INTO attendance (organization_id, teaching_session_id, enrollment_id, status)
      VALUES (f.org_id, v_sess, b.enrollment_id, 'present');
  END LOOP;
  PERFORM _cw2_t05_add_portfolio_entry(f.org_id, f.consultant_a_user, 1141, NULL, b.student_id);
  PERFORM _cw2_t11_as_auth(f.consultant_a_auth);
  r := public.list_consultant_workspace_portfolio();
  PERFORM _cw2_t11_record(
    41, 'lesson block depleted het_hoc_phi',
    (r->'rows'->0->>'tuition_payment_state') = 'het_hoc_phi'
  );
  SELECT * INTO b FROM _cw2_t11_bare_student(f.org_id, f.consultant_a_auth);
  PERFORM _cw2_t11_as_auth(f.consultant_a_auth);
  v_init := public.save_consultant_payment_declaration_draft(
    NULL, CURRENT_DATE, 2500000, 'credit', NULL, b.student_id, b.course_id, b.class_id,
    b.enrollment_id, b.terms_id, b.guardian_id, NULL, 't11-credit-init', NULL,
    'periodic', NULL, 'month', 1, 2000000, NULL, NULL, 'initial_tuition_setup'
  );
  PERFORM public.submit_consultant_payment_declaration(v_init);
  PERFORM _cw2_t11_confirm(f.org_id, acct.accountant_auth, v_init, f.consultant_a_auth);
  PERFORM _cw2_t11_record(
    42, 'carry credit co_so_du',
    public._cw2_derive_tuition_payment_state(f.org_id, b.enrollment_id, 0, 0, 0, 0) = 'co_so_du'
  );
END $$;

-- 43–50: adversarial GUC spoof + teacher-only periodic read gate + internal mutation still works
DROP FUNCTION IF EXISTS _cw2_t11_periodic_seed(uuid, uuid);
CREATE OR REPLACE FUNCTION _cw2_t11_periodic_seed(
  p_org uuid,
  p_enrollment uuid,
  OUT billing_id uuid,
  OUT obligation_id uuid
)
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM _cw2_t11_as_postgres();
  INSERT INTO enrollment_tuition_billing (
    organization_id, enrollment_id, enrollment_financial_terms_id, billing_mode,
    period_unit, period_quantity, amount_per_period, established_at
  )
  SELECT p_org, p_enrollment, t.id, 'periodic', 'month', 1, 1500000, now()
  FROM enrollment_financial_terms t
  WHERE t.enrollment_id = p_enrollment AND t.organization_id = p_org
  LIMIT 1
  RETURNING id INTO billing_id;
  INSERT INTO enrollment_periodic_tuition_balance (organization_id, enrollment_id, carry_forward_credit)
  VALUES (p_org, p_enrollment, 0)
  ON CONFLICT (organization_id, enrollment_id) DO NOTHING;
  INSERT INTO enrollment_periodic_period_obligation (
    organization_id, enrollment_id, period_key, obligation_amount, satisfied_amount, status
  ) VALUES (p_org, p_enrollment, '2026-01', 1500000, 500000, 'underpaid')
  RETURNING id INTO obligation_id;
END;
$$;

CREATE OR REPLACE FUNCTION _cw2_t11_teacher_only_auth(p_org uuid)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_auth uuid := gen_random_uuid(); v_user uuid;
BEGIN
  PERFORM _cw2_t11_as_postgres();
  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at, is_sso_user, is_anonymous
  ) VALUES (
    v_auth, (SELECT id FROM auth.instances LIMIT 1), 'authenticated', 'authenticated',
    't11-teacher-only-' || substr(p_org::text, 1, 8) || '@olli.local', '', now(), now(), now(), false, false
  );
  v_user := public.test_fixture_insert_app_user(
    p_org, 't11-teacher-only-' || substr(p_org::text, 1, 8) || '@olli.local', 'T11 Teacher', v_auth
  );
  INSERT INTO user_role (organization_id, user_id, role_id, effective_from, status)
  SELECT p_org, v_user, r.id, CURRENT_DATE, 'active'
  FROM role r WHERE r.organization_id = p_org AND r.canonical_code = 'teacher';
  RETURN v_auth;
END;
$$;

DO $$
DECLARE
  f record; f2 record; b record; b2 record; acct record; p record;
  v_teacher_auth uuid; v_cnt integer; ok_ins boolean := false; ok_upd boolean := false;
  v_init uuid; v_bal bigint;
BEGIN
  SELECT * INTO f FROM _cw2_t05_org();
  SELECT * INTO f2 FROM _cw2_t05_org();
  SELECT * INTO b FROM _cw2_t11_bare_student(f.org_id, f.consultant_a_auth);
  SELECT * INTO b2 FROM _cw2_t11_bare_student(f2.org_id, f2.consultant_a_auth);
  SELECT * INTO p FROM _cw2_t11_periodic_seed(f2.org_id, b2.enrollment_id);
  PERFORM _cw2_t11_as_auth(f.consultant_a_auth);
  PERFORM set_config('cw2.periodic_internal_depth', '1', true);
  PERFORM set_config('cw2.periodic_internal_org', f2.org_id::text, true);
  SELECT count(*) INTO v_cnt FROM enrollment_periodic_tuition_balance WHERE organization_id = f2.org_id;
  PERFORM _cw2_t11_record(43, 'GUC spoof cross-org balance select denied', v_cnt = 0);
  SELECT count(*) INTO v_cnt FROM enrollment_periodic_period_obligation WHERE organization_id = f2.org_id;
  PERFORM _cw2_t11_record(44, 'GUC spoof cross-org obligation select denied', v_cnt = 0);
  SELECT count(*) INTO v_cnt FROM enrollment_periodic_session_consumption WHERE organization_id = f2.org_id;
  PERFORM _cw2_t11_record(45, 'GUC spoof cross-org consumption select denied', v_cnt = 0);
  BEGIN
    INSERT INTO enrollment_periodic_period_obligation (
      organization_id, enrollment_id, period_key, obligation_amount, satisfied_amount, status
    ) VALUES (f2.org_id, b2.enrollment_id, '2099-01', 1000, 0, 'open');
  EXCEPTION WHEN OTHERS THEN ok_ins := true; END;
  PERFORM _cw2_t11_record(46, 'GUC spoof cross-org obligation insert denied', ok_ins);
  BEGIN
    UPDATE enrollment_periodic_tuition_balance SET carry_forward_credit = 999999
    WHERE organization_id = f2.org_id AND enrollment_id = b2.enrollment_id;
    GET DIAGNOSTICS v_cnt = ROW_COUNT;
    IF v_cnt = 0 THEN ok_upd := true; END IF;
  EXCEPTION WHEN OTHERS THEN ok_upd := true; END;
  PERFORM _cw2_t11_record(47, 'GUC spoof cross-org balance update denied', ok_upd);
  v_teacher_auth := _cw2_t11_teacher_only_auth(f.org_id);
  PERFORM _cw2_t11_as_auth(v_teacher_auth);
  PERFORM set_config('cw2.periodic_internal_depth', '1', true);
  PERFORM set_config('cw2.periodic_internal_org', f.org_id::text, true);
  PERFORM _cw2_t11_periodic_seed(f.org_id, b.enrollment_id);
  PERFORM _cw2_t11_as_auth(v_teacher_auth);
  SELECT count(*) INTO v_cnt
  FROM enrollment_periodic_tuition_balance
  WHERE organization_id = f.org_id AND enrollment_id = b.enrollment_id;
  PERFORM _cw2_t11_record(48, 'teacher-only same-org periodic select denied', v_cnt = 0);
  SELECT * INTO acct FROM _cw2_t05_accountant_for_org(f.org_id);
  PERFORM _cw2_t11_as_auth(f.consultant_a_auth);
  v_init := public.save_consultant_payment_declaration_draft(
    NULL, CURRENT_DATE, 1000000, 'int', NULL, b.student_id, b.course_id, b.class_id,
    b.enrollment_id, b.terms_id, b.guardian_id, NULL, 't11-int-mut', NULL,
    'periodic', NULL, 'month', 1, 1500000, NULL, NULL, 'initial_tuition_setup'
  );
  PERFORM public.submit_consultant_payment_declaration(v_init);
  PERFORM _cw2_t11_confirm(f.org_id, acct.accountant_auth, v_init, f.consultant_a_auth);
  SELECT count(*) INTO v_bal FROM enrollment_periodic_tuition_balance WHERE organization_id = f.org_id AND enrollment_id = b.enrollment_id;
  PERFORM _cw2_t11_record(49, 'internal confirm creates periodic balance row', v_bal = 1);
  PERFORM _cw2_t11_as_auth(acct.accountant_auth);
  SELECT count(*) INTO v_cnt FROM enrollment_periodic_period_obligation WHERE organization_id = f.org_id AND enrollment_id = b.enrollment_id;
  PERFORM _cw2_t11_record(50, 'accountant same-org periodic obligation readable', v_cnt >= 1);
END $$;

-- 51–54: consultant lead intake tuition entry (no enrollment / official code)
DO $$
DECLARE f record; j jsonb; r jsonb; v_ctx jsonb; v_decl uuid;
BEGIN
  SELECT * INTO f FROM _cw2_t05_org();
  PERFORM _cw2_t11_as_auth(f.consultant_a_auth);
  j := public.create_consultant_workspace_portfolio_intake(
    'MAI TRONG', 'HOANG', '2017-06-01', 'MAI', 'Parent', '0901234567', '[]'::jsonb
  );
  r := public.list_consultant_workspace_portfolio();
  PERFORM _cw2_t11_record(
    51, 'intake row chua_nop_phi',
    (r->'rows'->0->>'tuition_payment_state') = 'chua_nop_phi'
  );
  PERFORM _cw2_t11_record(
    52, 'tiem_nang allows tuition open',
    (r->'rows'->0->>'lifecycle_status') = 'tiem_nang'
    AND (r->'rows'->0->'capabilities'->>'can_open_payment_declaration')::boolean = true
  );
  v_ctx := public.get_cw2_tuition_declaration_context_for_portfolio((j->>'portfolio_entry_id')::uuid);
  PERFORM _cw2_t11_record(
    53, 'portfolio context without enrollment',
    (v_ctx->>'enrollment_id') IS NULL AND (v_ctx->>'can_change_billing_mode')::boolean = true
  );
  v_decl := public.save_consultant_payment_declaration_draft(
    NULL, CURRENT_DATE, 2000000, 'init', (j->>'lead_id')::uuid, NULL, NULL, NULL,
    NULL, NULL, NULL, NULL, 't11-lead-init', NULL,
    'course_lump_sum', 10000000, NULL, NULL, NULL, NULL, NULL, 'initial_tuition_setup'
  );
  PERFORM public.submit_consultant_payment_declaration(v_decl);
  r := public.list_consultant_workspace_portfolio();
  PERFORM _cw2_t11_record(
    54, 'lead initial submit coc_cho_xac_nhan',
    (r->'rows'->0->>'tuition_payment_state') = 'coc_cho_xac_nhan'
  );
END $$;

DO $$
DECLARE v_fail integer; v_total integer;
BEGIN
  SELECT count(*) FILTER (WHERE result = 'FAIL'), count(*) INTO v_fail, v_total FROM _cw2_t11_results;
  IF v_fail > 0 THEN
    RAISE EXCEPTION 'CW2-T11 tests failed: % / % (%)',
      v_fail, v_total,
      (SELECT string_agg(test_no::text || ':' || test_name, '; ') FROM _cw2_t11_results WHERE result = 'FAIL');
  END IF;
  IF v_total <> 54 THEN
    RAISE EXCEPTION 'CW2-T11 expected 54 scenarios, recorded %', v_total;
  END IF;
  RAISE NOTICE 'CW2-T11: all % tests passed', v_total;
END $$;
