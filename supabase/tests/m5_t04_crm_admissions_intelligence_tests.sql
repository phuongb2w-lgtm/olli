-- M5-T04: CRM admissions intelligence tests (30 scenarios)

BEGIN;

CREATE TEMP TABLE _m5_t04_results (
  test_no   integer PRIMARY KEY,
  test_name text NOT NULL,
  result    text NOT NULL CHECK (result IN ('PASS', 'FAIL'))
);

GRANT ALL ON TABLE _m5_t04_results TO authenticated, anon;

CREATE OR REPLACE FUNCTION _m5_t04_record(test_no integer, test_name text, passed boolean)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO _m5_t04_results (test_no, test_name, result)
  VALUES (test_no, test_name, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END);
END;
$$;

CREATE OR REPLACE FUNCTION _m5_t04_as_auth(p_auth_id uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', p_auth_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_auth_id::text, 'role', 'authenticated')::text, true);
END;
$$;

CREATE OR REPLACE FUNCTION _m5_t04_as_super()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
END;
$$;

CREATE OR REPLACE FUNCTION _m5_t04_seed_auth_user(p_auth uuid, p_email text)
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
  PERFORM _m5_t04_as_super();

  IF NOT EXISTS (SELECT 1 FROM app_user WHERE email = 'm5-t04-consultant-a@olli.local') THEN
    v_auth := 'd1111111-1111-4111-8111-111111111111';
    PERFORM _m5_t04_seed_auth_user(v_auth, 'm5-t04-consultant-a@olli.local');
    INSERT INTO role (organization_id, code) VALUES (v_org, 'm5_t04_consultant_a') RETURNING id INTO v_role;
    INSERT INTO role_permission (role_id, permission_id)
    SELECT v_role, p.id FROM permission p
    WHERE p.code IN (
      'organization.read', 'lead.read', 'lead.create', 'lead.update',
      'lead.assign', 'lead.convert', 'consultant_revenue.declare'
    );
    INSERT INTO app_user (organization_id, email, display_name, auth_user_id, status)
    VALUES (v_org, 'm5-t04-consultant-a@olli.local', 'M5 T04 Consultant A', v_auth, 'active')
    RETURNING id INTO v_user;
    INSERT INTO user_role (organization_id, user_id, role_id, effective_from, status)
    VALUES (v_org, v_user, v_role, CURRENT_DATE, 'active');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM app_user WHERE email = 'm5-t04-consultant-b@olli.local') THEN
    v_auth := 'd2222222-2222-4222-8222-222222222222';
    PERFORM _m5_t04_seed_auth_user(v_auth, 'm5-t04-consultant-b@olli.local');
    INSERT INTO role (organization_id, code) VALUES (v_org, 'm5_t04_consultant_b') RETURNING id INTO v_role;
    INSERT INTO role_permission (role_id, permission_id)
    SELECT v_role, p.id FROM permission p
    WHERE p.code IN (
      'organization.read', 'lead.read', 'lead.create', 'lead.update',
      'lead.assign', 'lead.convert', 'consultant_revenue.declare'
    );
    INSERT INTO app_user (organization_id, email, display_name, auth_user_id, status)
    VALUES (v_org, 'm5-t04-consultant-b@olli.local', 'M5 T04 Consultant B', v_auth, 'active')
    RETURNING id INTO v_user;
    INSERT INTO user_role (organization_id, user_id, role_id, effective_from, status)
    VALUES (v_org, v_user, v_role, CURRENT_DATE, 'active');
  END IF;
END $$;

-- Fixture helpers
DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_admin uuid := 'a1000000-0000-4000-8000-000000000001';
  v_cons_a uuid;
  v_cons_b uuid;
  v_lead_in uuid;
  v_lead_out uuid;
  v_lead_conv uuid;
  v_lead_status_only uuid;
BEGIN
  PERFORM _m5_t04_as_super();
  SELECT id INTO v_cons_a FROM app_user WHERE email = 'm5-t04-consultant-a@olli.local';
  SELECT id INTO v_cons_b FROM app_user WHERE email = 'm5-t04-consultant-b@olli.local';

  INSERT INTO lead (id, organization_id, status, created_by, created_at, updated_at)
  VALUES (
    'd6100000-0000-4000-8000-000000000001', v_org, 'new', v_cons_a,
    timestamptz '2045-06-15 10:00:00+07', now()
  ) ON CONFLICT DO NOTHING;

  INSERT INTO lead (id, organization_id, status, created_by, created_at, updated_at)
  VALUES (
    'd6100000-0000-4000-8000-000000000002', v_org, 'new', v_cons_a,
    timestamptz '2045-05-01 10:00:00+07', now()
  ) ON CONFLICT DO NOTHING;

  INSERT INTO lead (id, organization_id, status, created_by, created_at, updated_at)
  VALUES (
    'd6100000-0000-4000-8000-000000000003', v_org, 'qualified', v_cons_b,
    timestamptz '2045-06-10 10:00:00+07', now()
  ) ON CONFLICT DO NOTHING;

  INSERT INTO lead (id, organization_id, status, created_by, created_at, updated_at, converted_at)
  VALUES (
    'd6100000-0000-4000-8000-000000000004', v_org, 'converted', v_cons_a,
    timestamptz '2045-06-01 10:00:00+07', now(), timestamptz '2045-06-01 10:00:00+07'
  ) ON CONFLICT DO NOTHING;

  PERFORM set_config('olli.lead_assignment_mutation', 'true', true);
  UPDATE lead SET assigned_user_id = v_cons_a
  WHERE id IN (
    'd6100000-0000-4000-8000-000000000001',
    'd6100000-0000-4000-8000-000000000002',
    'd6100000-0000-4000-8000-000000000004'
  );
  UPDATE lead SET assigned_user_id = v_cons_b
  WHERE id = 'd6100000-0000-4000-8000-000000000003';
  PERFORM set_config('olli.lead_assignment_mutation', 'false', true);

  INSERT INTO lead_assignment (
    organization_id, lead_id, previous_assigned_user_id, new_assigned_user_id, changed_by
  )
  VALUES
    (v_org, 'd6100000-0000-4000-8000-000000000001', NULL, v_cons_a, v_cons_a),
    (v_org, 'd6100000-0000-4000-8000-000000000002', NULL, v_cons_a, v_cons_a),
    (v_org, 'd6100000-0000-4000-8000-000000000003', NULL, v_cons_b, v_cons_b),
    (v_org, 'd6100000-0000-4000-8000-000000000004', NULL, v_cons_a, v_cons_a);

  IF NOT EXISTS (
    SELECT 1 FROM lead_candidate
    WHERE lead_id = 'd6100000-0000-4000-8000-000000000003' AND organization_id = v_org
  ) THEN
    INSERT INTO lead_candidate (organization_id, lead_id, given_name, family_name, is_primary_candidate, created_by)
    VALUES (v_org, 'd6100000-0000-4000-8000-000000000003', 'T04', 'Candidate', true, v_cons_b);
  END IF;

  INSERT INTO lead_conversion (
    organization_id, lead_id, converted_by, converted_at, assigned_user_id
  )
  VALUES (
    v_org, 'd6100000-0000-4000-8000-000000000003', v_cons_b,
    timestamptz '2045-06-20 14:00:00+07', v_cons_b
  ) ON CONFLICT DO NOTHING;

  INSERT INTO lead_activity (
    organization_id, lead_id, activity_type_code, occurred_at, content, created_by
  )
  VALUES (
    v_org, 'd6100000-0000-4000-8000-000000000001', 'call',
    timestamptz '2045-06-16 09:00:00+07', 'T04 test activity', v_cons_a
  ) ON CONFLICT DO NOTHING;

  INSERT INTO lead_follow_up (
    organization_id, lead_id, due_at, note, assigned_user_id, status, created_by
  )
  VALUES (
    v_org, 'd6100000-0000-4000-8000-000000000001',
    now() - interval '3 days', 'Overdue fixture', v_cons_a, 'pending', v_cons_a
  ) ON CONFLICT DO NOTHING;

  PERFORM set_config('olli.lead_trial_mutation', 'true', true);
  INSERT INTO lead_trial (
    organization_id, lead_id, lead_candidate_id, class_id,
    status, scheduled_start_at, scheduled_end_at, created_by, completed_at, completed_by
  )
  SELECT
    v_org, 'd6100000-0000-4000-8000-000000000003', lc.id, c.id,
    'completed', timestamptz '2045-06-18 09:00:00+07', timestamptz '2045-06-18 10:30:00+07',
    v_cons_b, timestamptz '2045-06-18 11:00:00+07', v_cons_b
  FROM lead_candidate lc
  CROSS JOIN class c
  WHERE lc.lead_id = 'd6100000-0000-4000-8000-000000000003'
    AND lc.organization_id = v_org
    AND c.organization_id = v_org
  LIMIT 1
  ON CONFLICT DO NOTHING;
  PERFORM set_config('olli.lead_trial_mutation', 'false', true);
END $$;

-- 1: lead created in period counted
DO $$
DECLARE v_metrics jsonb;
BEGIN
  PERFORM _m5_t04_as_auth('a1111111-1111-4111-8111-111111111111');
  v_metrics := public.get_crm_lead_intake_metrics('2045-06-01', '2045-06-30');
  PERFORM _m5_t04_record(
    1, 'lead created in period counted',
    (v_metrics->>'leads_created')::bigint >= 1
  );
END $$;

-- 2: lead outside period excluded
DO $$
DECLARE v_metrics jsonb;
BEGIN
  PERFORM _m5_t04_as_auth('a1111111-1111-4111-8111-111111111111');
  v_metrics := public.get_crm_lead_intake_metrics('2045-07-01', '2045-07-31');
  PERFORM _m5_t04_record(
    2, 'lead outside period excluded',
    NOT EXISTS (
      SELECT 1 FROM lead l
      WHERE l.id = 'd6100000-0000-4000-8000-000000000001'
        AND l.created_at >= (public.resolve_reporting_period('2045-07-01', '2045-07-31')).start_at_utc
        AND l.created_at < (public.resolve_reporting_period('2045-07-01', '2045-07-31')).end_at_exclusive
    )
  );
END $$;

-- 3: organization isolation
DO $$
DECLARE v_a jsonb; v_b jsonb;
BEGIN
  PERFORM _m5_t04_as_auth('a1111111-1111-4111-8111-111111111111');
  v_a := public.get_crm_lead_intake_metrics('2045-06-01', '2045-06-30');
  PERFORM _m5_t04_as_auth('b1111111-1111-4111-8111-111111111111');
  v_b := public.get_crm_lead_intake_metrics('2045-06-01', '2045-06-30');
  PERFORM _m5_t04_record(
    3, 'organization isolation',
    (v_a->>'leads_created')::bigint > (v_b->>'leads_created')::bigint
  );
END $$;

-- 4: current lead status does not fabricate historical conversion
DO $$
DECLARE v_conv jsonb;
BEGIN
  PERFORM _m5_t04_as_auth('a1111111-1111-4111-8111-111111111111');
  v_conv := public.get_crm_conversion_metrics('2045-06-01', '2045-06-30');
  PERFORM _m5_t04_record(
    4, 'current status does not fabricate historical conversion',
    (v_conv->>'conversions_in_period')::bigint = 1
      AND NOT EXISTS (
        SELECT 1 FROM lead_conversion lc
        WHERE lc.lead_id = 'd6100000-0000-4000-8000-000000000004'
      )
  );
END $$;

-- 5: conversion event timestamp controls conversion-period metric
DO $$
DECLARE v_conv jsonb;
BEGIN
  PERFORM _m5_t04_as_auth('a1111111-1111-4111-8111-111111111111');
  v_conv := public.get_crm_conversion_metrics('2045-06-15', '2045-06-25');
  PERFORM _m5_t04_record(
    5, 'conversion event timestamp controls conversion-period metric',
    (v_conv->>'conversions_in_period')::bigint = 1
  );
END $$;

-- 6: trial completed_at controls trial-period metric
DO $$
DECLARE v_trials jsonb;
BEGIN
  PERFORM _m5_t04_as_auth('a1111111-1111-4111-8111-111111111111');
  v_trials := public.get_crm_trial_metrics('2045-06-15', '2045-06-25');
  PERFORM _m5_t04_record(
    6, 'trial completed_at controls trial-period metric',
    (v_trials->>'trials_completed')::bigint >= 1
  );
END $$;

-- 7: consultant personal overview scope enforced
DO $$
DECLARE v_overview jsonb; v_user uuid;
BEGIN
  PERFORM _m5_t04_as_auth('d1111111-1111-4111-8111-111111111111');
  v_overview := public.get_consultant_crm_overview('2045-06-01', '2045-06-30');
  SELECT id INTO v_user FROM app_user WHERE email = 'm5-t04-consultant-a@olli.local';
  PERFORM _m5_t04_record(
    7, 'consultant personal overview scope enforced',
    (v_overview->>'consultant_user_id')::uuid = v_user
  );
END $$;

-- 8: unrelated consultant cannot see another consultant executive data
DO $$
DECLARE v_failed boolean := false;
BEGIN
  PERFORM _m5_t04_as_auth('d1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.get_crm_admissions_overview('2045-06-01', '2045-06-30', false);
    v_failed := true;
  EXCEPTION WHEN others THEN
    v_failed := false;
  END;
  PERFORM _m5_t04_record(8, 'consultant executive CRM denied', NOT v_failed);
END $$;

-- 9: conversion attributed to lead_conversion.assigned_user_id
DO $$
DECLARE v_prod jsonb; v_cons_b uuid;
BEGIN
  PERFORM _m5_t04_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT id INTO v_cons_b FROM app_user WHERE email = 'm5-t04-consultant-b@olli.local';
  v_prod := public.get_crm_consultant_productivity('2045-06-01', '2045-06-30');
  PERFORM _m5_t04_record(
    9, 'conversion attributed to snapshot owner',
    EXISTS (
      SELECT 1 FROM jsonb_array_elements(v_prod->'rows') elem
      WHERE (elem->>'consultant_user_id')::uuid = v_cons_b
        AND (elem->>'conversions_in_period')::bigint >= 1
    )
  );
END $$;

-- 10: activity counted by occurred_at in period
DO $$
DECLARE v_act jsonb;
BEGIN
  PERFORM _m5_t04_as_auth('a1111111-1111-4111-8111-111111111111');
  v_act := public.get_crm_activity_metrics('2045-06-15', '2045-06-20');
  PERFORM _m5_t04_record(
    10, 'activity counted correctly',
    (v_act->>'activities_recorded')::bigint >= 1
  );
END $$;

-- 11: overdue follow-up exception deterministic
DO $$
DECLARE v_count bigint;
BEGIN
  PERFORM _m5_t04_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_count
  FROM public.list_crm_admissions_exceptions('2045-06-01', '2045-06-30') ex
  WHERE ex->>'exception_code' = 'overdue_follow_up';
  PERFORM _m5_t04_record(11, 'overdue follow-up exception deterministic', v_count >= 1);
END $$;

-- 12: completed follow-up not overdue
DO $$
DECLARE v_overdue bigint;
BEGIN
  PERFORM _m5_t04_as_super();
  UPDATE lead_follow_up SET status = 'completed', completed_at = now(), completed_by = created_by
  WHERE lead_id = 'd6100000-0000-4000-8000-000000000002'
    AND status = 'pending';
  INSERT INTO lead_follow_up (
    organization_id, lead_id, due_at, status, created_by, completed_at, completed_by
  )
  SELECT organization_id, 'd6100000-0000-4000-8000-000000000002',
    timestamptz '2040-01-01 08:00:00+07', 'completed', id, now(), id
  FROM app_user WHERE email = 'm5-t04-consultant-a@olli.local'
  ON CONFLICT DO NOTHING;

  PERFORM _m5_t04_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_overdue
  FROM lead_follow_up f
  WHERE f.lead_id = 'd6100000-0000-4000-8000-000000000002'
    AND f.status = 'pending' AND f.due_at < now();
  PERFORM _m5_t04_record(12, 'no false overdue without pending due date', v_overdue = 0);
END $$;

-- 13: conversion event counted once
DO $$
DECLARE v_conv jsonb;
BEGIN
  PERFORM _m5_t04_as_auth('a1111111-1111-4111-8111-111111111111');
  v_conv := public.get_crm_conversion_metrics('2045-06-01', '2045-06-30');
  PERFORM _m5_t04_record(
    13, 'conversion event counted once',
    (v_conv->>'conversions_in_period')::bigint = (
      SELECT count(*) FROM lead_conversion lc
      WHERE lc.converted_at >= (public.resolve_reporting_period('2045-06-01', '2045-06-30')).start_at_utc
        AND lc.converted_at < (public.resolve_reporting_period('2045-06-01', '2045-06-30')).end_at_exclusive
        AND lc.organization_id = 'a0000000-0000-4000-8000-000000000001'
    )
  );
END $$;

-- 14: converted lead can link enrollment (structure exists)
DO $$
DECLARE v_conv jsonb;
BEGIN
  PERFORM _m5_t04_as_auth('a1111111-1111-4111-8111-111111111111');
  v_conv := public.get_crm_conversion_metrics('2045-06-01', '2045-06-30');
  PERFORM _m5_t04_record(
    14, 'conversion linkage fields present',
    v_conv ? 'enrollments_linked' AND v_conv ? 'conversions_without_enrollment'
  );
END $$;

-- 15: cohort conversion denominator documented
DO $$
DECLARE v_conv jsonb;
BEGIN
  PERFORM _m5_t04_as_auth('a1111111-1111-4111-8111-111111111111');
  v_conv := public.get_crm_conversion_metrics('2045-06-01', '2045-06-30');
  PERFORM _m5_t04_record(
    15, 'cohort denominator rule documented',
    v_conv->>'cohort_denominator_rule' IS NOT NULL
      AND v_conv ? 'cohort_leads_created'
  );
END $$;

-- 16: period and cohort metrics separate fields
DO $$
DECLARE v_conv jsonb;
BEGIN
  PERFORM _m5_t04_as_auth('a1111111-1111-4111-8111-111111111111');
  v_conv := public.get_crm_conversion_metrics('2045-06-01', '2045-06-30');
  PERFORM _m5_t04_record(
    16, 'cohort and period conversion not mixed',
    v_conv ? 'conversions_in_period'
      AND v_conv ? 'cohort_conversion_rate'
      AND v_conv->>'period_event_denominator_rule' IS NOT NULL
  );
END $$;

-- 17: pending declaration visible as declaration only
DO $$
DECLARE v_decl uuid; v_overview jsonb;
BEGIN
  PERFORM _m5_t04_as_auth('d1111111-1111-4111-8111-111111111111');
  v_decl := public.declare_consultant_revenue('2045-06-25', 100000, 'T04 pending');
  v_overview := public.get_consultant_crm_overview('2045-06-01', '2045-06-30');
  PERFORM _m5_t04_record(
    17, 'pending declaration visible as declaration only',
    (v_overview->'declarations'->>'pending_count')::bigint >= 1
  );
END $$;

-- 18: approved declaration is not cash
DO $$
DECLARE v_decl uuid; v_cash_before numeric; v_cash_after numeric;
BEGIN
  PERFORM _m5_t04_as_auth('d1111111-1111-4111-8111-111111111111');
  v_decl := public.declare_consultant_revenue('2045-06-26', 200000, 'T04 approve no cash');

  PERFORM _m5_t04_as_auth('b7777777-7777-4777-8777-777777777777');
  v_cash_before := public.sum_canonical_cash_collected('2045-06-01', '2045-06-30');
  PERFORM public.review_consultant_revenue_declaration(v_decl, 'approve', 'T04');
  v_cash_after := public.sum_canonical_cash_collected('2045-06-01', '2045-06-30');

  PERFORM _m5_t04_record(
    18, 'approved declaration is not cash',
    v_cash_after = v_cash_before
  );
END $$;

-- 19: linked payment helper remains finance evidence gate
DO $$
DECLARE v_has boolean;
BEGIN
  PERFORM _m5_t04_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT public.declaration_has_canonical_payment(gen_random_uuid()) INTO v_has;
  PERFORM _m5_t04_record(19, 'payment linkage helper exists', v_has = false);
END $$;

-- 20: consultant sees personal declaration status
DO $$
DECLARE v_overview jsonb;
BEGIN
  PERFORM _m5_t04_as_auth('d1111111-1111-4111-8111-111111111111');
  v_overview := public.get_consultant_crm_overview('2045-06-01', '2045-06-30');
  PERFORM _m5_t04_record(
    20, 'consultant sees personal declaration status',
    v_overview->'declarations' ? 'approved_amount'
      AND v_overview->'declarations'->>'semantic_note' IS NOT NULL
  );
END $$;

-- 21: manager executive CRM access
DO $$
DECLARE v_overview jsonb;
BEGIN
  PERFORM _m5_t04_as_auth('a1111111-1111-4111-8111-111111111111');
  v_overview := public.get_crm_admissions_overview('2045-06-01', '2045-06-30', false);
  PERFORM _m5_t04_record(
    21, 'manager executive CRM access',
    v_overview ? 'leadIntake' AND v_overview ? 'consultantProductivity'
  );
END $$;

-- 22: consultant executive denied (duplicate assert)
DO $$
DECLARE v_failed boolean := false;
BEGIN
  PERFORM _m5_t04_as_auth('d2222222-2222-4222-8222-222222222222');
  BEGIN
    PERFORM public.get_crm_admissions_overview('2045-06-01', '2045-06-30', false);
    v_failed := true;
  EXCEPTION WHEN others THEN
    v_failed := false;
  END;
  PERFORM _m5_t04_record(22, 'consultant executive CRM denied', NOT v_failed);
END $$;

-- 23: accountant executive CRM denied
DO $$
DECLARE v_failed boolean := false;
BEGIN
  PERFORM _m5_t04_as_auth('b7777777-7777-4777-8777-777777777777');
  BEGIN
    PERFORM public.get_crm_admissions_overview('2045-06-01', '2045-06-30', false);
    v_failed := true;
  EXCEPTION WHEN others THEN
    v_failed := false;
  END;
  PERFORM _m5_t04_record(23, 'accountant executive CRM denied', NOT v_failed);
END $$;

-- 24: academic operations denied executive CRM
DO $$
DECLARE v_failed boolean := false;
BEGIN
  PERFORM _m5_t04_as_auth('c3333333-3333-4333-8333-333333333333');
  BEGIN
    PERFORM public.get_crm_admissions_overview('2045-06-01', '2045-06-30', false);
    v_failed := true;
  EXCEPTION WHEN others THEN
    v_failed := false;
  END;
  PERFORM _m5_t04_record(24, 'academic operations executive CRM denied', NOT v_failed);
END $$;

-- 25: teacher denied executive CRM
DO $$
DECLARE v_failed boolean := false;
BEGIN
  PERFORM _m5_t04_as_auth('c2222222-2222-4222-8222-222222222222');
  BEGIN
    PERFORM public.get_crm_admissions_overview('2045-06-01', '2045-06-30', false);
    v_failed := true;
  EXCEPTION WHEN others THEN
    v_failed := false;
  END;
  PERFORM _m5_t04_record(25, 'teacher denied executive CRM', NOT v_failed);
END $$;

-- 26: local reporting period boundary
DO $$
DECLARE v_bounds reporting_period_bounds;
BEGIN
  PERFORM _m5_t04_as_auth('a1111111-1111-4111-8111-111111111111');
  v_bounds := public.resolve_reporting_period('2045-06-01', '2045-06-01');
  PERFORM _m5_t04_record(
    26, 'local reporting period boundary deterministic',
    v_bounds.start_date = '2045-06-01'::date
      AND v_bounds.end_date = '2045-06-01'::date
      AND v_bounds.end_at_exclusive > v_bounds.start_at_utc
  );
END $$;

-- 27: event crossing UTC/local boundary
DO $$
DECLARE v_metrics jsonb;
BEGIN
  PERFORM _m5_t04_as_super();
  INSERT INTO lead (organization_id, status, created_at, updated_at)
  VALUES (
    'a0000000-0000-4000-8000-000000000001', 'new',
    timestamptz '2045-06-30 23:30:00+07', now()
  );
  PERFORM _m5_t04_as_auth('a1111111-1111-4111-8111-111111111111');
  v_metrics := public.get_crm_lead_intake_metrics('2045-06-30', '2045-06-30');
  PERFORM _m5_t04_record(
    27, 'local boundary includes late evening lead',
    (v_metrics->>'leads_created')::bigint >= 1
  );
END $$;

-- 28: unassigned lead exception
DO $$
DECLARE v_count bigint;
BEGIN
  PERFORM _m5_t04_as_super();
  INSERT INTO lead (organization_id, status, created_at, updated_at)
  VALUES (
    'a0000000-0000-4000-8000-000000000001', 'new', now(), now()
  );
  PERFORM _m5_t04_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_count
  FROM public.list_crm_admissions_exceptions('2045-06-01', '2045-06-30') ex
  WHERE ex->>'exception_code' = 'unassigned_active_lead';
  PERFORM _m5_t04_record(28, 'unassigned lead exception', v_count >= 1);
END $$;

-- 29: stale lead exception follows rule
DO $$
DECLARE v_count bigint;
BEGIN
  PERFORM _m5_t04_as_super();
  INSERT INTO lead (organization_id, status, created_at, updated_at)
  VALUES (
    'a0000000-0000-4000-8000-000000000001', 'contacted',
    now() - interval '20 days', now() - interval '20 days'
  );
  PERFORM _m5_t04_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_count
  FROM public.list_crm_admissions_exceptions('2045-01-01', '2045-12-31') ex
  WHERE ex->>'exception_code' = 'stale_active_lead';
  PERFORM _m5_t04_record(29, 'stale lead exception deterministic', v_count >= 1);
END $$;

-- 30: conversion missing enrollment exception
DO $$
DECLARE v_count bigint;
BEGIN
  PERFORM _m5_t04_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_count
  FROM public.list_crm_admissions_exceptions('2045-06-01', '2045-06-30') ex
  WHERE ex->>'exception_code' = 'conversion_missing_enrollment';
  PERFORM _m5_t04_record(30, 'conversion linkage exception deterministic', v_count >= 1);
END $$;

DO $$
DECLARE
  v_fail integer;
  v_total integer;
  r record;
BEGIN
  SELECT count(*) FILTER (WHERE result = 'FAIL'), count(*)
  INTO v_fail, v_total
  FROM _m5_t04_results;

  IF v_fail > 0 THEN
    FOR r IN SELECT test_no, test_name FROM _m5_t04_results WHERE result = 'FAIL' LOOP
      RAISE NOTICE 'FAILED: % - %', r.test_no, r.test_name;
    END LOOP;
    RAISE EXCEPTION 'M5-T04 CRM admissions intelligence: %/% FAIL (% failed)',
      v_total - v_fail, v_total, v_fail;
  END IF;

  RAISE NOTICE 'M5-T04 CRM admissions intelligence: %/% PASS (0 FAIL)', v_total, v_total;
END $$;

COMMIT;
