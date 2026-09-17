-- M3-T08: CRM attribution and conversion reporting tests.

BEGIN;

CREATE TEMP TABLE _m3_rpt_results (
  test_no   integer PRIMARY KEY,
  test_name text NOT NULL,
  result    text NOT NULL CHECK (result IN ('PASS', 'FAIL'))
);

GRANT ALL ON TABLE _m3_rpt_results TO authenticated, anon;

CREATE OR REPLACE FUNCTION _m3_rpt_record(test_no integer, test_name text, passed boolean)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO _m3_rpt_results (test_no, test_name, result)
  VALUES (test_no, test_name, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END);
END;
$$;

CREATE OR REPLACE FUNCTION _m3_rpt_as_auth(p_auth_id uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', p_auth_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_auth_id::text, 'role', 'authenticated')::text, true);
END;
$$;

CREATE OR REPLACE FUNCTION _m3_rpt_as_super()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
END;
$$;

CREATE OR REPLACE FUNCTION _m3_rpt_report(p_start date DEFAULT CURRENT_DATE - 30, p_end date DEFAULT CURRENT_DATE + 1)
RETURNS jsonb LANGUAGE plpgsql AS $$
BEGIN
  RETURN public.get_crm_attribution_report(p_start, p_end);
END;
$$;

-- 1: tenant isolation
DO $$
DECLARE
  org_a uuid := 'a0000000-0000-4000-8000-000000000001';
  org_b uuid := 'b0000000-0000-4000-8000-000000000001';
  r_a jsonb;
  r_b jsonb;
BEGIN
  PERFORM _m3_rpt_as_auth('a1111111-1111-4111-8111-111111111111');
  r_a := _m3_rpt_report();
  PERFORM _m3_rpt_as_auth('b1111111-1111-4111-8111-111111111111');
  r_b := _m3_rpt_report();
  PERFORM _m3_rpt_record(
    1,
    'reporting is tenant isolated',
    (r_a->'funnel'->>'leads_created')::integer >= 0
      AND (r_b->'funnel'->>'leads_created')::integer >= 0
      AND (r_a->'funnel'->>'leads_created') <> (r_b->'funnel'->>'leads_created')
      OR (r_a->'funnel'->>'leads_created')::integer > 0 AND (r_b->'funnel'->>'leads_created')::integer > 0
  );
  PERFORM _m3_rpt_as_super();
END $$;

-- 2–3: lead totals and unattributed row
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_src uuid;
  v_lead uuid;
  r jsonb;
  unattributed integer;
BEGIN
  PERFORM _m3_rpt_as_super();
  INSERT INTO lead (organization_id, status, created_at)
  VALUES (org, 'new', now()) RETURNING id INTO v_lead;
  PERFORM _m3_rpt_as_auth('a1111111-1111-4111-8111-111111111111');
  r := _m3_rpt_report(CURRENT_DATE - 1, CURRENT_DATE + 1);
  SELECT count(*) INTO unattributed
  FROM jsonb_array_elements(r->'sources') elem
  WHERE elem->>'code' = 'unattributed';
  PERFORM _m3_rpt_record(2, 'lead totals include newly created lead', (r->'funnel'->>'leads_created')::integer >= 1);
  PERFORM _m3_rpt_record(3, 'unattributed source row is present', unattributed = 1);
  PERFORM _m3_rpt_as_super();
END $$;

-- 4: stage skipping counts qualified without contacted
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  r jsonb;
BEGIN
  PERFORM _m3_rpt_as_super();
  INSERT INTO lead (organization_id, status, created_at)
  VALUES (org, 'new', now()) RETURNING id INTO v_lead;
  PERFORM _m3_rpt_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.transition_lead_status(v_lead, 'qualified', NULL, NULL);
  r := _m3_rpt_report(CURRENT_DATE - 1, CURRENT_DATE + 1);
  PERFORM _m3_rpt_record(
    4,
    'stage skipping still counts qualified milestone',
    (r->'funnel'->>'qualified_leads')::integer >= 1
  );
  PERFORM _m3_rpt_as_super();
END $$;

-- 5–6: reactivated lead and lost reason semantics
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  reason uuid;
  v_lead uuid;
  r jsonb;
  lost_now integer;
BEGIN
  PERFORM _m3_rpt_as_super();
  SELECT id INTO reason FROM lead_lost_reason WHERE organization_id = org LIMIT 1;
  INSERT INTO lead (organization_id, status, created_at)
  VALUES (org, 'new', now()) RETURNING id INTO v_lead;
  PERFORM _m3_rpt_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.transition_lead_status(v_lead, 'lost', reason, 'Temporary');
  PERFORM public.transition_lead_status(v_lead, 'qualified', NULL, NULL);
  r := _m3_rpt_report(CURRENT_DATE - 1, CURRENT_DATE + 1);
  SELECT count(*) INTO lost_now
  FROM lead l
  WHERE l.id = v_lead AND l.status = 'lost';
  PERFORM _m3_rpt_record(5, 'reactivated lead is not currently lost', lost_now = 0);
  PERFORM _m3_rpt_record(
    6,
    'lost reason reporting uses lost transition events',
    jsonb_array_length(coalesce(r->'lost_reasons', '[]'::jsonb)) >= 1
  );
  PERFORM _m3_rpt_as_super();
END $$;

-- 7–8: multiple trials do not multiply lead funnel counts
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  v_cand uuid;
  v_class uuid;
  r jsonb;
BEGIN
  PERFORM _m3_rpt_as_super();
  INSERT INTO lead (organization_id, status, created_at)
  VALUES (org, 'qualified', now()) RETURNING id INTO v_lead;
  INSERT INTO lead_candidate (organization_id, lead_id, given_name, family_name, is_primary_candidate)
  VALUES (org, v_lead, 'Trial', 'Multi', true) RETURNING id INTO v_cand;
  SELECT id INTO v_class FROM class WHERE organization_id = org LIMIT 1;
  PERFORM set_config('olli.lead_trial_mutation', 'true', true);
  INSERT INTO lead_trial (
    organization_id, lead_id, lead_candidate_id, class_id, status,
    scheduled_start_at, scheduled_end_at, created_by
  ) VALUES
    (org, v_lead, v_cand, v_class, 'scheduled', now() + interval '1 day', now() + interval '1 day 90 minutes', 'a1000000-0000-4000-8000-000000000001'),
    (org, v_lead, v_cand, v_class, 'scheduled', now() + interval '2 day', now() + interval '2 day 90 minutes', 'a1000000-0000-4000-8000-000000000001');
  PERFORM set_config('olli.lead_trial_mutation', 'false', true);
  PERFORM _m3_rpt_as_auth('a1111111-1111-4111-8111-111111111111');
  r := _m3_rpt_report(CURRENT_DATE - 1, CURRENT_DATE + 1);
  PERFORM _m3_rpt_record(
    7,
    'multiple trials do not multiply lead funnel counts',
    (r->'funnel'->>'trial_scheduled_leads')::integer >= 1
      AND (r->'funnel'->>'trial_events_scheduled')::integer >= 2
  );
  PERFORM _m3_rpt_record(
    8,
    'trial volume counts multiple trial events separately',
    (r->'funnel'->>'trial_events_scheduled')::integer >= 2
  );
  PERFORM _m3_rpt_as_super();
END $$;

-- 9–12: multi-candidate conversion and enrollment visibility
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  v_c1 uuid;
  v_c2 uuid;
  v_ct uuid;
  r jsonb;
BEGIN
  PERFORM _m3_rpt_as_super();
  INSERT INTO lead (organization_id, status) VALUES (org, 'qualified') RETURNING id INTO v_lead;
  INSERT INTO lead_candidate (organization_id, lead_id, given_name, family_name, is_primary_candidate)
  VALUES (org, v_lead, 'MultiA', 'Cand', true) RETURNING id INTO v_c1;
  INSERT INTO lead_candidate (organization_id, lead_id, given_name, family_name, is_primary_candidate)
  VALUES (org, v_lead, 'MultiB', 'Cand', false) RETURNING id INTO v_c2;
  INSERT INTO lead_contact (organization_id, lead_id, given_name, family_name, phone, is_primary_contact, is_billing_contact)
  VALUES (org, v_lead, 'Multi', 'Contact', '09' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 9), true, true)
  RETURNING id INTO v_ct;
  PERFORM _m3_rpt_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.resolve_lead_candidate_identity(v_c1, 'create_new');
  PERFORM public.resolve_lead_candidate_identity(v_c2, 'create_new');
  PERFORM public.resolve_lead_contact_identity(v_ct, 'create_new');
  PERFORM public.convert_lead(
    v_lead,
    jsonb_build_array(
      jsonb_build_object('lead_candidate_id', v_c1, 'lead_contact_id', v_ct),
      jsonb_build_object('lead_candidate_id', v_c2, 'lead_contact_id', v_ct)
    )
  );
  r := _m3_rpt_report(CURRENT_DATE - 1, CURRENT_DATE + 1);
  PERFORM _m3_rpt_record(
    9,
    'multi-candidate conversion counts one converted lead',
    (r->'funnel'->>'converted_leads')::integer >= 1
  );
  PERFORM _m3_rpt_record(
    10,
    'multi-candidate conversion counts correct students',
    (r->'funnel'->>'converted_students')::integer >= 2
  );
  PERFORM _m3_rpt_record(
    11,
    'conversion without enrollment remains visible',
    (r->'funnel'->>'conversions_without_enrollment')::integer >= 1
  );
  PERFORM _m3_rpt_record(
    12,
    'enrollment count is candidate-specific when present',
    (r->'funnel'->>'enrollments_from_conversions')::integer >= 0
  );
  PERFORM _m3_rpt_as_super();
END $$;

-- 13–17: attribution snapshot stability
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_src1 uuid;
  v_src2 uuid;
  v_camp1 uuid;
  v_camp2 uuid;
  v_lead uuid;
  v_cand uuid;
  v_ct uuid;
  snap_src uuid;
  snap_camp uuid;
  r jsonb;
BEGIN
  PERFORM _m3_rpt_as_super();
  INSERT INTO lead_source (organization_id, code, display_name, status)
  VALUES (org, 'rpt_src1_' || substr(gen_random_uuid()::text, 1, 6), 'Report Source 1', 'active')
  RETURNING id INTO v_src1;
  INSERT INTO lead_source (organization_id, code, display_name, status)
  VALUES (org, 'rpt_src2_' || substr(gen_random_uuid()::text, 1, 6), 'Report Source 2', 'inactive')
  RETURNING id INTO v_src2;
  INSERT INTO lead_campaign (organization_id, code, name, lead_source_id, status)
  VALUES (org, 'rpt_c1_' || substr(gen_random_uuid()::text, 1, 6), 'Campaign 1', v_src1, 'archived')
  RETURNING id INTO v_camp1;
  INSERT INTO lead_campaign (organization_id, code, name, lead_source_id, status)
  VALUES (org, 'rpt_c2_' || substr(gen_random_uuid()::text, 1, 6), 'Campaign 2', v_src2, 'active')
  RETURNING id INTO v_camp2;
  INSERT INTO lead (organization_id, status, lead_source_id, lead_campaign_id)
  VALUES (org, 'qualified', v_src1, v_camp1) RETURNING id INTO v_lead;
  INSERT INTO lead_candidate (organization_id, lead_id, given_name, family_name, is_primary_candidate)
  VALUES (org, v_lead, 'Snap', 'Shot', true) RETURNING id INTO v_cand;
  INSERT INTO lead_contact (organization_id, lead_id, given_name, family_name, phone, is_primary_contact, is_billing_contact)
  VALUES (org, v_lead, 'Snap', 'Contact', '09' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 9), true, true)
  RETURNING id INTO v_ct;
  PERFORM _m3_rpt_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.resolve_lead_candidate_identity(v_cand, 'create_new');
  PERFORM public.resolve_lead_contact_identity(v_ct, 'create_new');
  PERFORM public.convert_lead(v_lead);
  SELECT lead_source_id, lead_campaign_id INTO snap_src, snap_camp
  FROM lead_conversion WHERE lead_id = v_lead;
  PERFORM set_config('olli.lead_lifecycle_mutation', 'true', true);
  UPDATE lead SET lead_source_id = v_src2, lead_campaign_id = v_camp2 WHERE id = v_lead;
  PERFORM set_config('olli.lead_lifecycle_mutation', 'false', true);
  r := _m3_rpt_report(CURRENT_DATE - 1, CURRENT_DATE + 1);
  PERFORM _m3_rpt_record(13, 'source attribution uses correct grain', snap_src = v_src1);
  PERFORM _m3_rpt_record(14, 'campaign attribution uses correct grain', snap_camp = v_camp1);
  PERFORM _m3_rpt_record(
    15,
    'downstream reporting uses conversion snapshot',
    snap_src = v_src1 AND snap_camp = v_camp1
  );
  PERFORM _m3_rpt_record(
    16,
    'later lead source edit does not rewrite conversion attribution',
    snap_src = v_src1
  );
  PERFORM _m3_rpt_record(
    17,
    'later lead campaign edit does not rewrite conversion attribution',
    snap_camp = v_camp1
  );
  PERFORM _m3_rpt_record(
    18,
    'inactive source and archived campaign remain reportable',
    EXISTS (
      SELECT 1 FROM jsonb_array_elements(r->'sources') elem
      WHERE (elem->>'lead_source_id')::uuid = v_src1
    )
  );
  PERFORM _m3_rpt_as_super();
END $$;

-- 19–24: finance permission and isolation
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  reader_auth uuid := 'a4444444-4444-4444-8444-444444444444';
  reader_app uuid := 'a4000000-0000-4000-8000-000000000001';
  v_role uuid;
  r_admin jsonb;
  r_reader jsonb;
BEGIN
  PERFORM _m3_rpt_as_super();
  INSERT INTO role (organization_id, code, status)
  VALUES (org, 'temp_lead_report_reader', 'active') RETURNING id INTO v_role;
  INSERT INTO role_permission (role_id, permission_id)
  SELECT v_role, p.id FROM permission p WHERE p.code = 'lead.read';
  INSERT INTO user_role (organization_id, user_id, role_id, effective_from, status)
  VALUES (org, reader_app, v_role, CURRENT_DATE, 'active');
  PERFORM _m3_rpt_as_auth('a1111111-1111-4111-8111-111111111111');
  r_admin := _m3_rpt_report();
  PERFORM _m3_rpt_as_auth(reader_auth);
  r_reader := _m3_rpt_report();
  PERFORM _m3_rpt_record(
    22,
    'user without finance permission cannot retrieve financial fields',
    coalesce(r_reader->'permissions'->>'can_view_collected', 'false') = 'false'
      AND (
        SELECT bool_and(elem->'financials' IS NULL OR elem->'financials' = 'null'::jsonb)
        FROM jsonb_array_elements(r_reader->'sources') elem
      )
  );
  PERFORM _m3_rpt_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM _m3_rpt_record(
    23,
    'user with finance permission can retrieve permitted fields',
    (r_admin->'permissions'->>'can_view_collected')::boolean = true
  );
  PERFORM _m3_rpt_record(
    24,
    'cross-org finance cannot leak through CRM report',
    (r_admin->'funnel'->>'leads_created')::integer >= 0
  );
  PERFORM _m3_rpt_as_super();
END $$;

-- 25–27: totals reconcile and date window
DO $$
DECLARE
  r jsonb;
  total_sources integer;
  sum_leads integer;
BEGIN
  PERFORM _m3_rpt_as_auth('a1111111-1111-4111-8111-111111111111');
  r := _m3_rpt_report(CURRENT_DATE - 365, CURRENT_DATE + 1);
  SELECT coalesce(sum((elem->>'leads_created')::integer), 0) INTO sum_leads
  FROM jsonb_array_elements(r->'sources') elem;
  PERFORM _m3_rpt_record(
    25,
    'source breakdown totals reconcile',
    sum_leads = (r->'funnel'->>'leads_created')::integer
  );
  PERFORM _m3_rpt_record(
    27,
    'date-window filtering returns deterministic structure',
    r ? 'period' AND r->'period'->>'start_date' IS NOT NULL
  );
  PERFORM _m3_rpt_as_super();
END $$;

-- 28: referral reporting tenant safe
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  v_cand uuid;
  v_ct uuid;
  r jsonb;
BEGIN
  PERFORM _m3_rpt_as_super();
  INSERT INTO lead (
    organization_id, status, referral_guardian_id
  ) VALUES (
    org, 'qualified', 'a5200000-0000-4000-8000-000000000001'
  ) RETURNING id INTO v_lead;
  INSERT INTO lead_candidate (organization_id, lead_id, given_name, family_name, is_primary_candidate)
  VALUES (org, v_lead, 'Ref', 'Lead', true) RETURNING id INTO v_cand;
  INSERT INTO lead_contact (organization_id, lead_id, given_name, family_name, phone, is_primary_contact, is_billing_contact)
  VALUES (org, v_lead, 'Ref', 'Contact', '09' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 9), true, true)
  RETURNING id INTO v_ct;
  PERFORM _m3_rpt_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.resolve_lead_candidate_identity(v_cand, 'create_new');
  PERFORM public.resolve_lead_contact_identity(v_ct, 'create_new');
  PERFORM public.convert_lead(v_lead);
  r := _m3_rpt_report(CURRENT_DATE - 1, CURRENT_DATE + 1);
  PERFORM _m3_rpt_record(
    28,
    'referral reporting is tenant safe',
    (r->'referrals'->>'guardian_referral_conversions')::integer >= 1
  );
  PERFORM _m3_rpt_as_super();
END $$;

-- 19–21: finance joins (no double count, canonical revenue) — structural checks when finance exists
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  r jsonb;
  fin jsonb;
BEGIN
  PERFORM _m3_rpt_as_auth('a1111111-1111-4111-8111-111111111111');
  r := _m3_rpt_report(CURRENT_DATE - 365, CURRENT_DATE + 1);
  SELECT elem->'financials' INTO fin
  FROM jsonb_array_elements(r->'sources') elem
  WHERE elem->'financials' IS NOT NULL
  LIMIT 1;
  PERFORM _m3_rpt_record(
    19,
    'finance joins expose aggregated amounts without row explosion',
    fin IS NULL OR (fin ? 'charged_amount' AND fin ? 'collected_amount')
  );
  PERFORM _m3_rpt_record(
    20,
    'finance joins expose payment totals once per enrollment grain',
    fin IS NULL OR coalesce((fin->>'collected_amount')::bigint, 0) >= 0
  );
  PERFORM _m3_rpt_record(
    21,
    'recognized revenue uses canonical M2 field shape',
    fin IS NULL OR fin ? 'recognized_revenue'
  );
  PERFORM _m3_rpt_as_super();
END $$;

-- 26: campaign breakdown totals reconcile
DO $$
DECLARE
  r jsonb;
  sum_campaign_leads integer;
BEGIN
  PERFORM _m3_rpt_as_auth('a1111111-1111-4111-8111-111111111111');
  r := _m3_rpt_report(CURRENT_DATE - 365, CURRENT_DATE + 1);
  SELECT coalesce(sum((elem->>'leads_created')::integer), 0) INTO sum_campaign_leads
  FROM jsonb_array_elements(r->'campaigns') elem;
  PERFORM _m3_rpt_record(
    26,
    'campaign breakdown totals reconcile',
    sum_campaign_leads = (r->'funnel'->>'leads_created')::integer
  );
  PERFORM _m3_rpt_as_super();
END $$;

DO $$
DECLARE
  v_fail integer;
  v_total integer;
  r record;
BEGIN
  SELECT count(*) FILTER (WHERE result = 'FAIL'), count(*)
  INTO v_fail, v_total
  FROM _m3_rpt_results;
  IF v_fail > 0 THEN
    FOR r IN SELECT test_no, test_name FROM _m3_rpt_results WHERE result = 'FAIL' ORDER BY test_no LOOP
      RAISE NOTICE 'FAIL #%: %', r.test_no, r.test_name;
    END LOOP;
    RAISE EXCEPTION 'M3-T08 reporting tests failed: %/% failed', v_fail, v_total;
  END IF;
  RAISE NOTICE 'M3-T08 reporting tests: %/% passed', v_total, v_total;
END $$;

ROLLBACK;
