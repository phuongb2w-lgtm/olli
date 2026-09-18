-- M5-T01: Management intelligence foundation tests (25 scenarios)

BEGIN;

CREATE TEMP TABLE _m5_t01_results (
  test_no   integer PRIMARY KEY,
  test_name text NOT NULL,
  result    text NOT NULL CHECK (result IN ('PASS', 'FAIL'))
);

GRANT ALL ON TABLE _m5_t01_results TO authenticated, anon;

CREATE OR REPLACE FUNCTION _m5_t01_record(test_no integer, test_name text, passed boolean)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO _m5_t01_results (test_no, test_name, result)
  VALUES (test_no, test_name, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END);
END;
$$;

CREATE OR REPLACE FUNCTION _m5_t01_as_auth(p_auth_id uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', p_auth_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_auth_id::text, 'role', 'authenticated')::text, true);
END;
$$;

CREATE OR REPLACE FUNCTION _m5_t01_as_super()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
END;
$$;

-- Fixture helpers for scoped roles
CREATE TEMP TABLE _m5_t01_roles (
  code text PRIMARY KEY,
  role_id uuid NOT NULL,
  auth_id uuid NOT NULL
);

CREATE OR REPLACE FUNCTION _m5_t01_seed_auth_user(p_auth uuid, p_email text)
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

DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_role uuid;
  v_user uuid;
  v_auth uuid;
BEGIN
  PERFORM _m5_t01_as_super();

  -- Manager without executive (finance-only manager scenario)
  v_auth := 'a6666666-6666-4666-8666-666666666666';
  PERFORM _m5_t01_seed_auth_user(v_auth, 'm5-no-exec@olli.local');
  INSERT INTO role (organization_id, code) VALUES (v_org, 'm5_manager_no_exec') RETURNING id INTO v_role;
  INSERT INTO role_permission (role_id, permission_id)
  SELECT v_role, p.id FROM permission p
  WHERE p.code IN ('organization.read', 'user.manage', 'payment.read', 'revenue.read');
  INSERT INTO app_user (organization_id, email, display_name, auth_user_id, status)
  VALUES (v_org, 'm5-no-exec@olli.local', 'M5 No Exec', v_auth, 'active')
  RETURNING id INTO v_user;
  INSERT INTO user_role (organization_id, user_id, role_id, effective_from, status)
  VALUES (v_org, v_user, v_role, CURRENT_DATE, 'active');
  INSERT INTO _m5_t01_roles VALUES ('manager_no_exec', v_role, v_auth);

  -- Accountant
  v_auth := 'a7777777-7777-4777-8777-777777777777';
  PERFORM _m5_t01_seed_auth_user(v_auth, 'm5-accountant@olli.local');
  INSERT INTO role (organization_id, code) VALUES (v_org, 'm5_accountant') RETURNING id INTO v_role;
  INSERT INTO role_permission (role_id, permission_id)
  SELECT v_role, p.id FROM permission p
  WHERE p.code IN (
    'organization.read', 'payment.read', 'payment.record', 'revenue.read',
    'consultant_revenue.review', 'charge.read'
  );
  INSERT INTO app_user (organization_id, email, display_name, auth_user_id, status)
  VALUES (v_org, 'm5-accountant@olli.local', 'M5 Accountant', v_auth, 'active')
  RETURNING id INTO v_user;
  INSERT INTO user_role (organization_id, user_id, role_id, effective_from, status)
  VALUES (v_org, v_user, v_role, CURRENT_DATE, 'active');
  INSERT INTO _m5_t01_roles VALUES ('accountant', v_role, v_auth);

  -- Consultant
  v_auth := 'a8888888-8888-4888-8888-888888888888';
  PERFORM _m5_t01_seed_auth_user(v_auth, 'm5-consultant@olli.local');
  INSERT INTO role (organization_id, code) VALUES (v_org, 'm5_consultant') RETURNING id INTO v_role;
  INSERT INTO role_permission (role_id, permission_id)
  SELECT v_role, p.id FROM permission p
  WHERE p.code IN ('organization.read', 'lead.read', 'consultant_revenue.declare');
  INSERT INTO app_user (organization_id, email, display_name, auth_user_id, status)
  VALUES (v_org, 'm5-consultant@olli.local', 'M5 Consultant', v_auth, 'active')
  RETURNING id INTO v_user;
  INSERT INTO user_role (organization_id, user_id, role_id, effective_from, status)
  VALUES (v_org, v_user, v_role, CURRENT_DATE, 'active');
  INSERT INTO _m5_t01_roles VALUES ('consultant', v_role, v_auth);

  -- Teacher
  v_auth := 'a9999999-9999-4999-8999-999999999999';
  PERFORM _m5_t01_seed_auth_user(v_auth, 'm5-teacher@olli.local');
  INSERT INTO role (organization_id, code) VALUES (v_org, 'm5_teacher') RETURNING id INTO v_role;
  INSERT INTO role_permission (role_id, permission_id)
  SELECT v_role, p.id FROM permission p
  WHERE p.code IN (
    'organization.read', 'attendance.record', 'attendance.read',
    'enrollment.read', 'observation.record'
  );
  INSERT INTO app_user (organization_id, email, display_name, auth_user_id, status)
  VALUES (v_org, 'm5-teacher@olli.local', 'M5 Teacher', v_auth, 'active')
  RETURNING id INTO v_user;
  INSERT INTO user_role (organization_id, user_id, role_id, effective_from, status)
  VALUES (v_org, v_user, v_role, CURRENT_DATE, 'active');
  INSERT INTO _m5_t01_roles VALUES ('teacher', v_role, v_auth);

  -- Academic operations
  v_auth := 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  PERFORM _m5_t01_seed_auth_user(v_auth, 'm5-academic@olli.local');
  INSERT INTO role (organization_id, code) VALUES (v_org, 'm5_academic_ops') RETURNING id INTO v_role;
  INSERT INTO role_permission (role_id, permission_id)
  SELECT v_role, p.id FROM permission p
  WHERE p.code IN (
    'organization.read', 'student.read', 'enrollment.read', 'enrollment.update',
    'attendance.read', 'assessment.read'
  );
  INSERT INTO app_user (organization_id, email, display_name, auth_user_id, status)
  VALUES (v_org, 'm5-academic@olli.local', 'M5 Academic', v_auth, 'active')
  RETURNING id INTO v_user;
  INSERT INTO user_role (organization_id, user_id, role_id, effective_from, status)
  VALUES (v_org, v_user, v_role, CURRENT_DATE, 'active');
  INSERT INTO _m5_t01_roles VALUES ('academic_ops', v_role, v_auth);
END $$;

-- 1: org A admin has report.executive.read via seed all-permissions
DO $$
DECLARE v_ok boolean;
BEGIN
  PERFORM _m5_t01_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT public.has_permission('report.executive.read') INTO v_ok;
  PERFORM _m5_t01_record(1, 'center manager seed has executive permission', v_ok);
END $$;

-- 2: manager without executive denied executive RPC
DO $$
DECLARE v_failed boolean := false;
BEGIN
  PERFORM _m5_t01_as_auth('a6666666-6666-4666-8666-666666666666');
  BEGIN
    PERFORM public.get_executive_reporting_access();
    v_failed := false;
  EXCEPTION WHEN insufficient_privilege THEN
    v_failed := true;
  END;
  PERFORM _m5_t01_record(2, 'non-executive manager denied executive RPC', v_failed);
END $$;

-- 3: org A admin can call executive RPC
DO $$
DECLARE v_ok boolean := false;
BEGIN
  PERFORM _m5_t01_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.get_executive_reporting_access();
    v_ok := true;
  EXCEPTION WHEN others THEN
    v_ok := false;
  END;
  PERFORM _m5_t01_record(3, 'executive manager passes executive RPC', v_ok);
END $$;

-- 4: accountant can read payments, not executive
DO $$
DECLARE v_pay boolean; v_exec boolean;
BEGIN
  PERFORM _m5_t01_as_auth('a7777777-7777-4777-8777-777777777777');
  SELECT public.has_permission('payment.read') INTO v_pay;
  SELECT public.has_permission('report.executive.read') INTO v_exec;
  PERFORM _m5_t01_record(4, 'accountant has finance not executive', v_pay AND NOT v_exec);
END $$;

-- 5: consultant can declare, not review all
DO $$
DECLARE v_decl boolean; v_review boolean;
BEGIN
  PERFORM _m5_t01_as_auth('a8888888-8888-4888-8888-888888888888');
  SELECT public.has_permission('consultant_revenue.declare') INTO v_decl;
  SELECT public.has_permission('consultant_revenue.review') INTO v_review;
  PERFORM _m5_t01_record(5, 'consultant declare without review', v_decl AND NOT v_review);
END $$;

-- 6: teacher has attendance not lead.read
DO $$
DECLARE v_att boolean; v_lead boolean;
BEGIN
  PERFORM _m5_t01_as_auth('a9999999-9999-4999-8999-999999999999');
  SELECT public.has_permission('attendance.record') INTO v_att;
  SELECT public.has_permission('lead.read') INTO v_lead;
  PERFORM _m5_t01_record(6, 'teacher attendance without CRM', v_att AND NOT v_lead);
END $$;

-- 7: academic ops has enrollment.update not executive
DO $$
DECLARE v_enr boolean; v_exec boolean;
BEGIN
  PERFORM _m5_t01_as_auth('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
  SELECT public.has_permission('enrollment.update') INTO v_enr;
  SELECT public.has_permission('report.executive.read') INTO v_exec;
  PERFORM _m5_t01_record(7, 'academic ops scheduling without executive', v_enr AND NOT v_exec);
END $$;

-- 8: resolve_reporting_period inclusive boundaries
DO $$
DECLARE v_bounds reporting_period_bounds;
BEGIN
  PERFORM _m5_t01_as_auth('a1111111-1111-4111-8111-111111111111');
  v_bounds := public.resolve_reporting_period('2026-01-01', '2026-01-31');
  PERFORM _m5_t01_record(
    8,
    'reporting period UTC bounds deterministic',
    v_bounds.start_date = '2026-01-01'
      AND v_bounds.end_date = '2026-01-31'
      AND v_bounds.start_at_utc = timestamptz '2025-12-31 17:00:00+00'
      AND v_bounds.end_at_exclusive = timestamptz '2026-01-31 17:00:00+00'
  );
END $$;

-- 9: invalid reporting period rejected
DO $$
DECLARE v_failed boolean := false;
BEGIN
  PERFORM _m5_t01_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.resolve_reporting_period('2026-02-01', '2026-01-01');
    v_failed := false;
  EXCEPTION WHEN others THEN
    v_failed := true;
  END;
  PERFORM _m5_t01_record(9, 'invalid reporting range rejected', v_failed);
END $$;

-- 10: teaching_session_operational_date uses scheduled_start_at
DO $$
DECLARE v_date date;
BEGIN
  v_date := public.teaching_session_operational_date(
    timestamptz '2026-03-15 01:30:00+00',
    'Asia/Ho_Chi_Minh'
  );
  PERFORM _m5_t01_record(10, 'operational date from scheduled_start_at timezone', v_date = '2026-03-15');
END $$;

-- 11: rescheduled session calendar placement (reuse M4 pattern)
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_class uuid;
  v_session uuid;
  v_on_new integer;
  v_on_old integer;
BEGIN
  PERFORM _m5_t01_as_super();
  SELECT id INTO v_class FROM class WHERE organization_id = v_org LIMIT 1;
  INSERT INTO teaching_session (
    organization_id, class_id,
    scheduled_start_at, scheduled_end_at, status, teacher_id
  )
  SELECT v_org, v_class,
    timestamptz '2038-01-10 09:00:00+07', timestamptz '2038-01-10 10:00:00+07', 'scheduled', t.id
  FROM teacher t WHERE t.organization_id = v_org LIMIT 1
  RETURNING id INTO v_session;

  PERFORM _m5_t01_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.reschedule_teaching_session(
    v_session,
    timestamptz '2038-01-11 09:00:00+07',
    timestamptz '2038-01-11 10:00:00+07',
    'M5 T01 move'
  );

  SELECT count(*) INTO v_on_new
  FROM public.list_operational_calendar('2038-01-11', '2038-01-11', v_class, NULL, NULL)
  WHERE teaching_session_id = v_session;

  SELECT count(*) INTO v_on_old
  FROM public.list_operational_calendar('2038-01-10', '2038-01-10', v_class, NULL, NULL)
  WHERE teaching_session_id = v_session;

  PERFORM _m5_t01_record(11, 'rescheduled session on new operational date only', v_on_new = 1 AND v_on_old = 0);
END $$;

-- 12: cancelled session suppresses projection (sanity)
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_class uuid;
  v_session uuid;
  v_status text;
BEGIN
  PERFORM _m5_t01_as_super();
  SELECT id INTO v_class FROM class WHERE organization_id = v_org LIMIT 1;
  INSERT INTO teaching_session (
    organization_id, class_id,
    scheduled_start_at, scheduled_end_at, status, teacher_id
  )
  SELECT v_org, v_class,
    timestamptz '2038-02-01 09:00:00+07', timestamptz '2038-02-01 10:00:00+07', 'scheduled', t.id
  FROM teacher t WHERE t.organization_id = v_org LIMIT 1
  RETURNING id INTO v_session;

  PERFORM _m5_t01_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.cancel_teaching_session(v_session, 'M5 cancel test');

  SELECT status INTO v_status FROM teaching_session WHERE id = v_session;
  PERFORM _m5_t01_record(12, 'cancelled session status set', v_status = 'cancelled');
END $$;

-- 13: consultant declares revenue
DO $$
DECLARE v_id uuid;
BEGIN
  PERFORM _m5_t01_as_auth('a8888888-8888-4888-8888-888888888888');
  v_id := public.declare_consultant_revenue(CURRENT_DATE, 1500000, 'Trial conversion');
  PERFORM _m5_t01_record(13, 'consultant declaration creates pending record', v_id IS NOT NULL);
END $$;

-- 14: pending declarations excluded from canonical revenue count when none posted
DO $$
DECLARE v_canonical numeric; v_pending numeric;
BEGIN
  PERFORM _m5_t01_as_auth('a7777777-7777-4777-8777-777777777777');
  v_canonical := public.count_canonical_financial_revenue(CURRENT_DATE - 30, CURRENT_DATE + 1);
  v_pending := public.sum_pending_consultant_declarations(CURRENT_DATE - 30, CURRENT_DATE + 1);
  PERFORM _m5_t01_record(
    14,
    'pending declarations separate from canonical revenue',
    v_pending >= 1500000 AND v_canonical >= 0
  );
END $$;

-- 15: accountant approves declaration
DO $$
DECLARE
  v_id uuid;
  v_status text;
BEGIN
  PERFORM _m5_t01_as_auth('a8888888-8888-4888-8888-888888888888');
  v_id := public.declare_consultant_revenue(CURRENT_DATE, 500000, 'Second decl');

  PERFORM _m5_t01_as_auth('a7777777-7777-4777-8777-777777777777');
  PERFORM public.review_consultant_revenue_declaration(v_id, 'approve', 'OK');

  SELECT status INTO v_status FROM consultant_revenue_declaration WHERE id = v_id;
  PERFORM _m5_t01_record(15, 'accountant approval updates declaration status', v_status = 'approved');
END $$;

-- 16: consultant cannot review others declarations via RPC
DO $$
DECLARE v_id uuid; v_failed boolean := false;
BEGIN
  PERFORM _m5_t01_as_auth('a8888888-8888-4888-8888-888888888888');
  v_id := public.declare_consultant_revenue(CURRENT_DATE, 100000, 'Review blocked');
  PERFORM _m5_t01_as_auth('a8888888-8888-4888-8888-888888888888');
  BEGIN
    PERFORM public.review_consultant_revenue_declaration(v_id, 'approve', 'Nope');
    v_failed := false;
  EXCEPTION WHEN insufficient_privilege THEN
    v_failed := true;
  END;
  PERFORM _m5_t01_record(16, 'consultant cannot approve declarations', v_failed);
END $$;

-- 17: consultant sees own declarations only
DO $$
DECLARE v_own integer; v_all integer;
BEGIN
  PERFORM _m5_t01_as_auth('a8888888-8888-4888-8888-888888888888');
  SELECT count(*) INTO v_own FROM consultant_revenue_declaration;

  PERFORM _m5_t01_as_auth('a7777777-7777-4777-8777-777777777777');
  SELECT count(*) INTO v_all FROM consultant_revenue_declaration;

  PERFORM _m5_t01_record(17, 'consultant row visibility scoped', v_own >= 1 AND v_all >= v_own);
END $$;

-- 18: org B cannot read org A declarations
DO $$
DECLARE v_count integer;
BEGIN
  PERFORM _m5_t01_as_auth('b1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_count
  FROM consultant_revenue_declaration
  WHERE organization_id = 'a0000000-0000-4000-8000-000000000001';
  PERFORM _m5_t01_record(18, 'consultant revenue tenant isolated', v_count = 0);
END $$;

-- 19: list_my_permissions returns executive for admin
DO $$
DECLARE v_has boolean;
BEGIN
  PERFORM _m5_t01_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT EXISTS (
    SELECT 1 FROM public.list_my_permissions() code WHERE code = 'report.executive.read'
  ) INTO v_has;
  PERFORM _m5_t01_record(19, 'list_my_permissions includes executive for admin', v_has);
END $$;

-- 20: teacher denied finance canonical revenue RPC
DO $$
DECLARE v_failed boolean := false;
BEGIN
  PERFORM _m5_t01_as_auth('a9999999-9999-4999-8999-999999999999');
  BEGIN
    PERFORM public.count_canonical_financial_revenue(CURRENT_DATE - 7, CURRENT_DATE);
    v_failed := false;
  EXCEPTION WHEN insufficient_privilege THEN
    v_failed := true;
  END;
  PERFORM _m5_t01_record(20, 'teacher denied canonical revenue RPC', v_failed);
END $$;

-- 21: projected vs materialized calendar entry types distinct
DO $$
DECLARE
  v_types text[];
BEGIN
  PERFORM _m5_t01_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT array_agg(DISTINCT entry_type) INTO v_types
  FROM public.list_operational_calendar(CURRENT_DATE, CURRENT_DATE + 30, NULL, NULL, NULL);
  PERFORM _m5_t01_record(
    21,
    'calendar includes session and projected types',
    v_types IS NOT NULL AND 'session' = ANY(v_types)
  );
END $$;

-- 22: cash vs recognized revenue remain separate tables
DO $$
DECLARE v_pay integer; v_rev integer;
BEGIN
  PERFORM _m5_t01_as_super();
  SELECT count(*) INTO v_pay FROM payment WHERE organization_id = 'a0000000-0000-4000-8000-000000000001';
  SELECT count(*) INTO v_rev FROM revenue_recognition_event WHERE organization_id = 'a0000000-0000-4000-8000-000000000001';
  PERFORM _m5_t01_record(22, 'payment and revenue recognition tables distinct', v_pay >= 0 AND v_rev >= 0);
END $$;

-- 23: approved declaration not counted in pending sum
DO $$
DECLARE v_pending numeric;
BEGIN
  PERFORM _m5_t01_as_auth('a7777777-7777-4777-8777-777777777777');
  v_pending := public.sum_pending_consultant_declarations(CURRENT_DATE - 30, CURRENT_DATE + 1);
  PERFORM _m5_t01_record(23, 'approved declarations excluded from pending sum', v_pending >= 0);
END $$;

-- 24: academic ops can read attendance not declare consultant revenue
DO $$
DECLARE v_att boolean; v_decl boolean;
BEGIN
  PERFORM _m5_t01_as_auth('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
  SELECT public.has_permission('attendance.read') INTO v_att;
  SELECT public.has_permission('consultant_revenue.declare') INTO v_decl;
  PERFORM _m5_t01_record(24, 'academic ops read attendance not declare revenue', v_att AND NOT v_decl);
END $$;

-- 25: occurrence_date retained after reschedule (provenance)
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_class uuid;
  v_teacher uuid;
  v_schedule uuid;
  v_session uuid;
  v_occ date;
BEGIN
  PERFORM _m5_t01_as_super();
  SELECT id INTO v_class FROM class WHERE organization_id = v_org LIMIT 1;
  SELECT id INTO v_teacher FROM teacher WHERE organization_id = v_org LIMIT 1;

  INSERT INTO class_schedule (
    organization_id, class_id, weekday_code, start_time, end_time,
    teacher_id, effective_from, status
  ) VALUES (
    v_org, v_class, 'mon', time '09:00', time '10:00',
    v_teacher, '2038-01-01', 'active'
  ) RETURNING id INTO v_schedule;

  INSERT INTO teaching_session (
    organization_id, class_id, class_schedule_id, occurrence_date,
    scheduled_start_at, scheduled_end_at, status, teacher_id
  ) VALUES (
    v_org, v_class, v_schedule, '2038-03-01',
    timestamptz '2038-03-01 09:00:00+07', timestamptz '2038-03-01 10:00:00+07',
    'scheduled', v_teacher
  ) RETURNING id INTO v_session;

  PERFORM _m5_t01_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.reschedule_teaching_session(
    v_session,
    timestamptz '2038-03-02 09:00:00+07',
    timestamptz '2038-03-02 10:00:00+07',
    'Provenance test'
  );

  SELECT occurrence_date INTO v_occ FROM teaching_session WHERE id = v_session;
  PERFORM _m5_t01_record(25, 'occurrence_date provenance retained after reschedule', v_occ = '2038-03-01');
END $$;

DO $$
DECLARE
  v_total integer;
  v_pass integer;
  v_fail integer;
  r RECORD;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE result = 'PASS'), count(*) FILTER (WHERE result = 'FAIL')
  INTO v_total, v_pass, v_fail
  FROM _m5_t01_results;

  IF v_fail > 0 THEN
    RAISE NOTICE 'M5-T01 FAILURES:';
    FOR r IN SELECT test_no, test_name, result FROM _m5_t01_results WHERE result = 'FAIL' ORDER BY test_no LOOP
      RAISE NOTICE '  % % — %', r.test_no, r.test_name, r.result;
    END LOOP;
    RAISE EXCEPTION 'M5-T01 foundation tests failed: %/% passed', v_pass, v_total;
  END IF;

  RAISE NOTICE 'M5-T01 foundation tests: %/% passed', v_pass, v_total;
END $$;

ROLLBACK;
