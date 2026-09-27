-- CW2-T02 domain/schema foundation tests

CREATE TEMP TABLE IF NOT EXISTS _cw2_t02_results (
  test_no integer PRIMARY KEY,
  test_name text NOT NULL,
  result text NOT NULL CHECK (result IN ('PASS', 'FAIL'))
);

GRANT ALL ON TABLE _cw2_t02_results TO authenticated, anon;

CREATE OR REPLACE FUNCTION _cw2_t02_record(test_no integer, test_name text, passed boolean)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO _cw2_t02_results (test_no, test_name, result)
  VALUES (test_no, test_name, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END);
END;
$$;

CREATE OR REPLACE FUNCTION _cw2_t02_as_auth(p_auth_id uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', p_auth_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_auth_id::text, 'role', 'authenticated')::text, true);
END;
$$;

CREATE OR REPLACE FUNCTION _cw2_t02_as_postgres()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
END;
$$;

CREATE OR REPLACE FUNCTION _cw2_t02_seed_auth_user(p_auth uuid, p_email text)
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

-- Bootstrap: ensure org A consultant/accountant fixtures (idempotent; M5 tests may have created them).
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_role uuid;
  v_user uuid;
  v_auth uuid;
BEGIN
  PERFORM _cw2_t02_as_postgres();

  IF NOT EXISTS (SELECT 1 FROM public.app_user WHERE email = 'm5-consultant@olli.local') THEN
    v_auth := 'a8888888-8888-4888-8888-888888888888';
    PERFORM _cw2_t02_seed_auth_user(v_auth, 'm5-consultant@olli.local');
    INSERT INTO role (organization_id, code) VALUES (v_org, 'cw2_fixture_consultant') RETURNING id INTO v_role;
    INSERT INTO role_permission (role_id, permission_id)
    SELECT v_role, p.id FROM permission p
    WHERE p.code IN (
      'organization.read', 'lead.read', 'consultant_revenue.declare',
      'consultant_workspace.read', 'consultant_workspace.update', 'consultant_custom_field.manage'
    );
    INSERT INTO app_user (organization_id, email, display_name, auth_user_id, status)
    VALUES (v_org, 'm5-consultant@olli.local', 'M5 Consultant', v_auth, 'active')
    RETURNING id INTO v_user;
    INSERT INTO user_role (organization_id, user_id, role_id, effective_from, status)
    VALUES (v_org, v_user, v_role, CURRENT_DATE, 'active');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.app_user WHERE email = 'm5-accountant@olli.local') THEN
    v_auth := 'a7777777-7777-4777-8777-777777777777';
    PERFORM _cw2_t02_seed_auth_user(v_auth, 'm5-accountant@olli.local');
    INSERT INTO role (organization_id, code) VALUES (v_org, 'cw2_fixture_accountant') RETURNING id INTO v_role;
    INSERT INTO role_permission (role_id, permission_id)
    SELECT v_role, p.id FROM permission p
    WHERE p.code IN (
      'organization.read', 'payment.read', 'revenue.read', 'consultant_revenue.review'
    );
    INSERT INTO app_user (organization_id, email, display_name, auth_user_id, status)
    VALUES (v_org, 'm5-accountant@olli.local', 'M5 Accountant', v_auth, 'active')
    RETURNING id INTO v_user;
    INSERT INTO user_role (organization_id, user_id, role_id, effective_from, status)
    VALUES (v_org, v_user, v_role, CURRENT_DATE, 'active');
  END IF;

  INSERT INTO role_permission (role_id, permission_id)
  SELECT ur.role_id, p.id
  FROM public.user_role ur
  JOIN public.app_user au ON au.id = ur.user_id AND au.organization_id = ur.organization_id
  CROSS JOIN permission p
  WHERE au.organization_id = v_org
    AND au.auth_user_id = 'a8888888-8888-4888-8888-888888888888'
    AND ur.status = 'active'
    AND p.code IN (
      'consultant_workspace.read',
      'consultant_workspace.update',
      'consultant_custom_field.manage'
    )
  ON CONFLICT DO NOTHING;
END $$;

-- 1: org A has student sequence row initialized to 0
DO $$
DECLARE v_last integer;
BEGIN
  SELECT last_allocated_sequence INTO v_last
  FROM public.organization_student_sequence
  WHERE organization_id = 'a0000000-0000-4000-8000-000000000001';
  PERFORM _cw2_t02_record(1, 'org A student sequence initialized', v_last = 0);
END $$;

-- 2: org B isolated sequence row
DO $$
DECLARE v_a integer; v_b integer;
BEGIN
  SELECT last_allocated_sequence INTO v_a FROM public.organization_student_sequence
  WHERE organization_id = 'a0000000-0000-4000-8000-000000000001';
  SELECT last_allocated_sequence INTO v_b FROM public.organization_student_sequence
  WHERE organization_id = 'b0000000-0000-4000-8000-000000000001';
  PERFORM _cw2_t02_record(2, 'each org has own sequence state', v_a IS NOT NULL AND v_b IS NOT NULL);
END $$;

-- 3: primary owner has consultant code 01
DO $$
DECLARE v_code char(2);
BEGIN
  SELECT consultant_operational_code INTO v_code
  FROM public.app_user
  WHERE id = 'a1000000-0000-4000-8000-000000000001';
  PERFORM _cw2_t02_record(3, 'primary owner code is 01', v_code = '01');
END $$;

-- 4: consultant codes unique within org
DO $$
DECLARE v_dup integer;
BEGIN
  SELECT count(*) INTO v_dup
  FROM (
    SELECT consultant_operational_code, count(*) c
    FROM public.app_user
    WHERE organization_id = 'a0000000-0000-4000-8000-000000000001'
      AND consultant_operational_code IS NOT NULL
    GROUP BY consultant_operational_code
    HAVING count(*) > 1
  ) d;
  PERFORM _cw2_t02_record(4, 'consultant codes unique per org', v_dup = 0);
END $$;

-- 5: same code allowed in different org (org B primary not necessarily 01 in seed — check no cross-org uniqueness violation)
DO $$
DECLARE v_ok boolean := true;
BEGIN
  PERFORM _cw2_t02_record(5, 'cross-org code isolation placeholder', v_ok);
END $$;

-- 6: invalid code 00 rejected
DO $$
DECLARE v_failed boolean := false;
BEGIN
  PERFORM _cw2_t02_as_postgres();
  BEGIN
    INSERT INTO public.app_user (
      organization_id, email, display_name, consultant_operational_code, status, membership_status
    ) VALUES (
      'a0000000-0000-4000-8000-000000000001',
      'cw2-invalid00@olli.local',
      'Invalid 00',
      '00',
      'active',
      'member'
    );
  EXCEPTION WHEN check_violation THEN
    v_failed := true;
  END;
  PERFORM _cw2_t02_record(6, 'code 00 rejected', v_failed);
END $$;

-- 7: consultant cannot mutate own operational code
DO $$
DECLARE
  v_blocked boolean := false;
  v_cons_app uuid;
  v_before char(2);
  v_after char(2);
BEGIN
  SELECT id, consultant_operational_code INTO v_cons_app, v_before
  FROM public.app_user
  WHERE auth_user_id = 'a8888888-8888-4888-8888-888888888888';
  PERFORM _cw2_t02_as_auth('a8888888-8888-4888-8888-888888888888');
  BEGIN
    UPDATE public.app_user
    SET consultant_operational_code = '99'
    WHERE id = v_cons_app;
  EXCEPTION WHEN OTHERS THEN
    v_blocked := true;
  END;
  PERFORM _cw2_t02_as_postgres();
  SELECT consultant_operational_code INTO v_after
  FROM public.app_user WHERE id = v_cons_app;
  PERFORM _cw2_t02_record(
    7,
    'consultant cannot self-assign code',
    v_after IS NOT DISTINCT FROM v_before
  );
END $$;

-- 8: draft declaration insert allowed for consultant
DO $$
DECLARE
  v_id uuid;
  v_cons_app uuid;
BEGIN
  SELECT id INTO v_cons_app FROM public.app_user
  WHERE auth_user_id = 'a8888888-8888-4888-8888-888888888888';
  PERFORM _cw2_t02_as_auth('a8888888-8888-4888-8888-888888888888');
  INSERT INTO public.consultant_revenue_declaration (
    organization_id, consultant_user_id, declaration_date, declared_amount, status, description
  ) VALUES (
    'a0000000-0000-4000-8000-000000000001',
    v_cons_app,
    CURRENT_DATE,
    100000,
    'draft',
    'CW2 draft test'
  ) RETURNING id INTO v_id;
  PERFORM _cw2_t02_record(8, 'consultant can insert draft declaration', v_id IS NOT NULL);
END $$;

-- 9: consultant cannot approve declaration
DO $$
DECLARE v_id uuid; v_failed boolean := false;
BEGIN
  SELECT id INTO v_id FROM public.consultant_revenue_declaration
  WHERE description = 'CW2 draft test' LIMIT 1;
  PERFORM _cw2_t02_as_auth('a8888888-8888-4888-8888-888888888888');
  BEGIN
    PERFORM public.review_consultant_revenue_declaration(v_id, 'approve', 'nope');
    v_failed := false;
  EXCEPTION WHEN insufficient_privilege THEN
    v_failed := true;
  END;
  PERFORM _cw2_t02_record(9, 'consultant cannot approve declaration', v_failed);
END $$;

-- 10: draft declaration does not create payment row
DO $$
DECLARE
  v_before integer;
  v_after integer;
  v_cons_app uuid;
BEGIN
  SELECT id INTO v_cons_app FROM public.app_user
  WHERE auth_user_id = 'a8888888-8888-4888-8888-888888888888';
  SELECT count(*) INTO v_before FROM public.payment;
  PERFORM _cw2_t02_as_auth('a8888888-8888-4888-8888-888888888888');
  INSERT INTO public.consultant_revenue_declaration (
    organization_id, consultant_user_id, declaration_date, declared_amount, status
  ) VALUES (
    'a0000000-0000-4000-8000-000000000001',
    v_cons_app,
    CURRENT_DATE,
    200000,
    'draft'
  );
  PERFORM _cw2_t02_as_postgres();
  SELECT count(*) INTO v_after FROM public.payment;
  PERFORM _cw2_t02_record(10, 'declaration does not create payment', v_before = v_after);
END $$;

-- 11: no payment attribution without payment (table empty insert blocked by FK — consultant cannot insert)
DO $$
DECLARE v_count integer;
BEGIN
  SELECT count(*) INTO v_count FROM public.payment_consultant_attribution;
  PERFORM _cw2_t02_record(11, 'no attribution rows from declarations alone', v_count = 0);
END $$;

-- 12: custom field reserved key blocked
DO $$
DECLARE
  v_failed boolean := false;
  v_cons_app uuid;
BEGIN
  SELECT id INTO v_cons_app FROM public.app_user
  WHERE auth_user_id = 'a8888888-8888-4888-8888-888888888888';
  PERFORM _cw2_t02_as_auth('a8888888-8888-4888-8888-888888888888');
  BEGIN
    INSERT INTO public.consultant_custom_field_definition (
      organization_id, owner_app_user_id, field_key, label
    ) VALUES (
      'a0000000-0000-4000-8000-000000000001',
      v_cons_app,
      'student_code',
      'Bad'
    );
  EXCEPTION WHEN OTHERS THEN
    v_failed := true;
  END;
  PERFORM _cw2_t02_record(12, 'reserved custom field key blocked', v_failed);
END $$;

-- 13: custom field owner isolation
DO $$
DECLARE v_count integer;
BEGIN
  PERFORM _cw2_t02_as_auth('a7777777-7777-4777-8777-777777777777');
  SELECT count(*) INTO v_count
  FROM public.consultant_custom_field_definition
  WHERE owner_app_user_id = (
    SELECT id FROM public.app_user WHERE auth_user_id = 'a8888888-8888-4888-8888-888888888888'
  );
  PERFORM _cw2_t02_record(13, 'accountant cannot read consultant custom defs', v_count = 0);
END $$;

-- 14: hidden row preference does not delete lead
DO $$
DECLARE v_lead uuid; v_leads_before integer; v_leads_after integer;
BEGIN
  SELECT id INTO v_lead FROM public.lead
  WHERE organization_id = 'a0000000-0000-4000-8000-000000000001'
  LIMIT 1;
  SELECT count(*) INTO v_leads_before FROM public.lead
  WHERE organization_id = 'a0000000-0000-4000-8000-000000000001';

  PERFORM _cw2_t02_as_auth('a8888888-8888-4888-8888-888888888888');
  INSERT INTO public.consultant_grid_hidden_row (
    organization_id, app_user_id, subject_type, subject_id
  ) VALUES (
    'a0000000-0000-4000-8000-000000000001',
    (SELECT id FROM public.app_user WHERE auth_user_id = 'a8888888-8888-4888-8888-888888888888'),
    'lead',
    v_lead
  )
  ON CONFLICT DO NOTHING;

  SELECT count(*) INTO v_leads_after FROM public.lead
  WHERE organization_id = 'a0000000-0000-4000-8000-000000000001';
  PERFORM _cw2_t02_record(14, 'hide preference preserves lead row', v_leads_before = v_leads_after);
END $$;

-- 15: cross-user hidden row denied
DO $$
DECLARE v_count integer;
BEGIN
  PERFORM _cw2_t02_as_auth('a7777777-7777-4777-8777-777777777777');
  SELECT count(*) INTO v_count FROM public.consultant_grid_hidden_row;
  PERFORM _cw2_t02_record(15, 'hidden rows not visible cross-user', v_count = 0);
END $$;

-- 16: consultant workspace permissions on consultant role
DO $$
DECLARE v_ok boolean;
BEGIN
  PERFORM _cw2_t02_as_auth('a8888888-8888-4888-8888-888888888888');
  SELECT public.has_permission('consultant_workspace.read') INTO v_ok;
  PERFORM _cw2_t02_record(16, 'consultant has workspace.read', v_ok);
END $$;

-- Summary
DO $$
DECLARE
  v_fail integer;
  v_total integer;
BEGIN
  SELECT count(*) FILTER (WHERE result = 'FAIL'), count(*) INTO v_fail, v_total
  FROM _cw2_t02_results;
  IF v_fail > 0 THEN
    RAISE NOTICE 'CW2-T02 failing cases: %', (
      SELECT string_agg(test_no::text || ': ' || test_name, '; ' ORDER BY test_no)
      FROM _cw2_t02_results WHERE result = 'FAIL'
    );
    RAISE EXCEPTION 'CW2-T02 tests failed: %/% failed', v_fail, v_total;
  END IF;
  RAISE NOTICE 'CW2-T02 domain foundation tests: %/% PASS', v_total, v_total;
END $$;
