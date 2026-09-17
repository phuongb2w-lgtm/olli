-- M3-T10: cross-domain milestone acceptance (5 scenarios)

BEGIN;

CREATE TEMP TABLE _m3_acc_results (
  test_no   integer PRIMARY KEY,
  test_name text NOT NULL,
  result    text NOT NULL CHECK (result IN ('PASS', 'FAIL'))
);

GRANT ALL ON TABLE _m3_acc_results TO authenticated, anon;

CREATE OR REPLACE FUNCTION _m3_acc_record(test_no integer, test_name text, passed boolean)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO _m3_acc_results (test_no, test_name, result)
  VALUES (test_no, test_name, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END);
END;
$$;

CREATE OR REPLACE FUNCTION _m3_acc_as_super() RETURNS void LANGUAGE plpgsql AS $$
BEGIN RESET ROLE; SET LOCAL ROLE postgres; END; $$;

CREATE OR REPLACE FUNCTION _m3_acc_as_auth(p_auth_id uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE; SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', p_auth_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_auth_id::text, 'role', 'authenticated')::text, true);
END; $$;

CREATE OR REPLACE FUNCTION _m3_acc_grant_perms(p_org uuid, p_user uuid, p_codes text[])
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_role uuid;
BEGIN
  INSERT INTO role (organization_id, code, status)
  VALUES (p_org, 'acc_' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 8), 'active')
  RETURNING id INTO v_role;
  INSERT INTO role_permission (role_id, permission_id)
  SELECT v_role, p.id FROM permission p WHERE p.code = ANY(p_codes);
  INSERT INTO user_role (organization_id, user_id, role_id, effective_from, status)
  VALUES (p_org, p_user, v_role, CURRENT_DATE, 'active');
END; $$;

-- Case 1: full end-to-end RPC journey on one lead
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  v_c uuid;
  v_ct uuid;
  v_class uuid;
  v_trial uuid;
  chg_before integer;
  chg_after integer;
  pay_before integer;
  pay_after integer;
  r jsonb;
  ok boolean := false;
BEGIN
  PERFORM _m3_acc_as_super();
  SELECT id INTO v_class FROM class WHERE organization_id = org AND status IN ('planned', 'trial', 'active') LIMIT 1;
  SELECT count(*) INTO chg_before FROM charge WHERE organization_id = org;
  SELECT count(*) INTO pay_before FROM payment WHERE organization_id = org;
  PERFORM _m3_acc_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT (public.create_lead_with_people(
    jsonb_build_object('notes_summary', 'M3 acc journey'),
    jsonb_build_array(jsonb_build_object('given_name', 'Journey', 'family_name', 'Cand', 'is_primary_candidate', true)),
    jsonb_build_array(jsonb_build_object('given_name', 'Journey', 'family_name', 'Contact', 'phone', '09' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 9), 'is_primary_contact', true, 'is_billing_contact', true))
  )->>'lead_id')::uuid INTO v_lead;
  SELECT id INTO v_c FROM lead_candidate WHERE lead_id = v_lead LIMIT 1;
  SELECT id INTO v_ct FROM lead_contact WHERE lead_id = v_lead LIMIT 1;
  PERFORM public.assign_lead(v_lead, 'a1000000-0000-4000-8000-000000000001', 'acc assign');
  PERFORM public.transition_lead_status(v_lead, 'contacted', NULL, 'acc');
  PERFORM public.transition_lead_status(v_lead, 'qualified', NULL, 'acc');
  PERFORM public.add_lead_activity(v_lead, 'note', now(), 'acc note');
  v_trial := (public.schedule_lead_trial(
    v_lead, v_c, v_class, NULL,
    now() + interval '3 days', now() + interval '3 days 90 minutes', 'acc trial'
  )->>'trial_id')::uuid;
  PERFORM public.complete_lead_trial(v_trial, 'acc complete');
  PERFORM public.resolve_lead_candidate_identity(v_c, 'create_new');
  PERFORM public.resolve_lead_contact_identity(v_ct, 'create_new');
  PERFORM public.convert_lead(
    v_lead,
    jsonb_build_array(jsonb_build_object(
      'lead_candidate_id', v_c, 'lead_contact_id', v_ct,
      'relationship_type', 'mother', 'is_primary_contact', true, 'is_billing_contact', true
    )),
    '[]'::jsonb
  );
  PERFORM _m3_acc_as_super();
  SELECT count(*) INTO chg_after FROM charge WHERE organization_id = org;
  SELECT count(*) INTO pay_after FROM payment WHERE organization_id = org;
  PERFORM _m3_acc_as_auth('a1111111-1111-4111-8111-111111111111');
  r := public.get_crm_attribution_report(CURRENT_DATE - 1, CURRENT_DATE + 1);
  ok := chg_after = chg_before AND pay_after = pay_before
    AND EXISTS (SELECT 1 FROM lead WHERE id = v_lead AND status = 'converted')
    AND (r->'funnel'->>'converted_leads')::integer >= 1;
  PERFORM _m3_acc_record(1, 'full end-to-end CRM journey with finance isolation', ok);
  PERFORM _m3_acc_as_super();
END $$;

-- Case 2: multi-candidate conversion with explicit relationship mapping
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  v_c1 uuid;
  v_c2 uuid;
  v_ct1 uuid;
  v_ct2 uuid;
  sg_cnt integer;
  stu_cnt integer;
  conv_cnt integer;
BEGIN
  PERFORM _m3_acc_as_super();
  INSERT INTO lead (organization_id, status) VALUES (org, 'qualified') RETURNING id INTO v_lead;
  INSERT INTO lead_candidate (organization_id, lead_id, given_name, family_name, is_primary_candidate)
  VALUES (org, v_lead, 'MultiAcc', 'A', true) RETURNING id INTO v_c1;
  INSERT INTO lead_candidate (organization_id, lead_id, given_name, family_name, is_primary_candidate)
  VALUES (org, v_lead, 'MultiAcc', 'B', false) RETURNING id INTO v_c2;
  INSERT INTO lead_contact (organization_id, lead_id, given_name, family_name, phone, is_primary_contact, is_billing_contact)
  VALUES (org, v_lead, 'Parent', 'One', '09' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 9), true, true)
  RETURNING id INTO v_ct1;
  INSERT INTO lead_contact (organization_id, lead_id, given_name, family_name, phone, is_primary_contact, is_billing_contact)
  VALUES (org, v_lead, 'Parent', 'Two', '09' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 9), false, false)
  RETURNING id INTO v_ct2;
  PERFORM _m3_acc_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.resolve_lead_candidate_identity(v_c1, 'create_new');
  PERFORM public.resolve_lead_candidate_identity(v_c2, 'create_new');
  PERFORM public.resolve_lead_contact_identity(v_ct1, 'create_new');
  PERFORM public.resolve_lead_contact_identity(v_ct2, 'create_new');
  PERFORM public.convert_lead(
    v_lead,
    jsonb_build_array(
      jsonb_build_object('lead_candidate_id', v_c1, 'lead_contact_id', v_ct1, 'relationship_type', 'mother', 'is_primary_contact', true, 'is_billing_contact', true),
      jsonb_build_object('lead_candidate_id', v_c2, 'lead_contact_id', v_ct2, 'relationship_type', 'father', 'is_primary_contact', false, 'is_billing_contact', false)
    ),
    '[]'::jsonb
  );
  PERFORM _m3_acc_as_super();
  SELECT count(*) INTO conv_cnt FROM lead_conversion WHERE lead_id = v_lead;
  SELECT count(*) INTO sg_cnt
  FROM lead_conversion_student_guardian sg
  JOIN lead_conversion lc ON lc.id = sg.lead_conversion_id
  WHERE lc.lead_id = v_lead;
  SELECT count(*) INTO stu_cnt
  FROM lead_conversion_candidate cc
  JOIN lead_conversion lc ON lc.id = cc.lead_conversion_id
  WHERE lc.lead_id = v_lead;
  PERFORM _m3_acc_record(
    2,
    'multi-candidate explicit mapping without all-to-all',
    conv_cnt = 1 AND sg_cnt = 2 AND stu_cnt = 2
  );
END $$;

-- Case 3: permission matrix negative paths (isolated users per permission)
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  v_user uuid;
  v_auth uuid;
  ok_read_only boolean := false;
  ok_create_only boolean := false;
  ok_update_only boolean := false;
  ok_assign_only boolean := false;
  ok_catalog_only boolean := false;
BEGIN
  PERFORM _m3_acc_as_super();
  INSERT INTO lead (organization_id, status) VALUES (org, 'new') RETURNING id INTO v_lead;

  v_auth := gen_random_uuid();
  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at, is_sso_user, is_anonymous)
  VALUES (v_auth, (SELECT id FROM auth.instances LIMIT 1), 'authenticated', 'authenticated', 'acc-read-' || replace(v_auth::text, '-', '') || '@test.local', '', now(), now(), now(), false, false);
  INSERT INTO app_user (organization_id, email, display_name, auth_user_id, status)
  VALUES (org, 'acc-read@test.local', 'Acc Read', v_auth, 'active') RETURNING id INTO v_user;
  PERFORM _m3_acc_grant_perms(org, v_user, ARRAY['lead.read']);
  PERFORM _m3_acc_as_auth(v_auth);
  BEGIN PERFORM public.assign_lead(v_lead, v_user, 'denied'); EXCEPTION WHEN OTHERS THEN ok_read_only := true; END;

  PERFORM _m3_acc_as_super();
  v_auth := gen_random_uuid();
  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at, is_sso_user, is_anonymous)
  VALUES (v_auth, (SELECT id FROM auth.instances LIMIT 1), 'authenticated', 'authenticated', 'acc-create-' || replace(v_auth::text, '-', '') || '@test.local', '', now(), now(), now(), false, false);
  INSERT INTO app_user (organization_id, email, display_name, auth_user_id, status)
  VALUES (org, 'acc-create@test.local', 'Acc Create', v_auth, 'active') RETURNING id INTO v_user;
  PERFORM _m3_acc_grant_perms(org, v_user, ARRAY['lead.create']);
  PERFORM _m3_acc_as_auth(v_auth);
  BEGIN PERFORM public.assign_lead(v_lead, v_user, 'denied'); EXCEPTION WHEN OTHERS THEN ok_create_only := true; END;

  PERFORM _m3_acc_as_super();
  v_auth := gen_random_uuid();
  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at, is_sso_user, is_anonymous)
  VALUES (v_auth, (SELECT id FROM auth.instances LIMIT 1), 'authenticated', 'authenticated', 'acc-update-' || replace(v_auth::text, '-', '') || '@test.local', '', now(), now(), now(), false, false);
  INSERT INTO app_user (organization_id, email, display_name, auth_user_id, status)
  VALUES (org, 'acc-update@test.local', 'Acc Update', v_auth, 'active') RETURNING id INTO v_user;
  PERFORM _m3_acc_grant_perms(org, v_user, ARRAY['lead.read', 'lead.update']);
  PERFORM _m3_acc_as_auth(v_auth);
  BEGIN PERFORM public.convert_lead(v_lead); EXCEPTION WHEN OTHERS THEN ok_update_only := true; END;

  PERFORM _m3_acc_as_super();
  v_auth := gen_random_uuid();
  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at, is_sso_user, is_anonymous)
  VALUES (v_auth, (SELECT id FROM auth.instances LIMIT 1), 'authenticated', 'authenticated', 'acc-assign-' || replace(v_auth::text, '-', '') || '@test.local', '', now(), now(), now(), false, false);
  INSERT INTO app_user (organization_id, email, display_name, auth_user_id, status)
  VALUES (org, 'acc-assign@test.local', 'Acc Assign', v_auth, 'active') RETURNING id INTO v_user;
  PERFORM _m3_acc_grant_perms(org, v_user, ARRAY['lead.read', 'lead.assign']);
  PERFORM _m3_acc_as_auth(v_auth);
  BEGIN PERFORM public.convert_lead(v_lead); EXCEPTION WHEN OTHERS THEN ok_assign_only := true; END;

  PERFORM _m3_acc_as_super();
  v_auth := gen_random_uuid();
  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at, is_sso_user, is_anonymous)
  VALUES (v_auth, (SELECT id FROM auth.instances LIMIT 1), 'authenticated', 'authenticated', 'acc-catalog-' || replace(v_auth::text, '-', '') || '@test.local', '', now(), now(), now(), false, false);
  INSERT INTO app_user (organization_id, email, display_name, auth_user_id, status)
  VALUES (org, 'acc-catalog@test.local', 'Acc Catalog', v_auth, 'active') RETURNING id INTO v_user;
  PERFORM _m3_acc_grant_perms(org, v_user, ARRAY['lead.manage_sources']);
  PERFORM _m3_acc_as_auth(v_auth);
  BEGIN PERFORM public.add_lead_activity(v_lead, 'note', now(), 'denied'); EXCEPTION WHEN OTHERS THEN ok_catalog_only := true; END;

  PERFORM _m3_acc_record(
    3,
    'permission matrix negative paths',
    ok_read_only AND ok_create_only AND ok_update_only AND ok_assign_only AND ok_catalog_only
  );
END $$;

-- Case 4: cross-org tenant isolation
DO $$
DECLARE
  org_a uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead_a uuid := 'a6100000-0000-4000-8000-000000000001';
  read_cnt integer;
  mutate_cnt integer;
  ok_rpc boolean := false;
BEGIN
  PERFORM _m3_acc_as_auth('b1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO read_cnt FROM lead WHERE id = v_lead_a;
  UPDATE lead SET notes_summary = 'cross-org' WHERE id = v_lead_a;
  GET DIAGNOSTICS mutate_cnt = ROW_COUNT;
  BEGIN
    PERFORM public.transition_lead_status(v_lead_a, 'contacted', NULL, 'cross');
    ok_rpc := false;
  EXCEPTION WHEN OTHERS THEN ok_rpc := true;
  END;
  PERFORM _m3_acc_record(
    4,
    'cross-org isolation on lead reads and mutations',
    read_cnt = 0 AND mutate_cnt = 0 AND ok_rpc
  );
END $$;

-- Case 5: attribution snapshot stable after post-conversion catalog change
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_src uuid;
  v_lead uuid;
  v_c uuid;
  v_ct uuid;
  snap_before uuid;
  snap_after uuid;
BEGIN
  PERFORM _m3_acc_as_super();
  SELECT id INTO v_src FROM lead_source WHERE organization_id = org AND code = 'walk_in' LIMIT 1;
  INSERT INTO lead (organization_id, status, lead_source_id) VALUES (org, 'qualified', v_src) RETURNING id INTO v_lead;
  INSERT INTO lead_candidate (organization_id, lead_id, given_name, family_name, is_primary_candidate)
  VALUES (org, v_lead, 'Snap', 'Shot', true) RETURNING id INTO v_c;
  INSERT INTO lead_contact (organization_id, lead_id, given_name, family_name, phone, is_primary_contact, is_billing_contact)
  VALUES (org, v_lead, 'Snap', 'Contact', '09' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 9), true, true)
  RETURNING id INTO v_ct;
  PERFORM _m3_acc_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.resolve_lead_candidate_identity(v_c, 'create_new');
  PERFORM public.resolve_lead_contact_identity(v_ct, 'create_new');
  PERFORM public.convert_lead(v_lead);
  SELECT lead_source_id INTO snap_before FROM lead_conversion WHERE lead_id = v_lead;
  PERFORM _m3_acc_as_super();
  UPDATE lead_source SET display_name = 'Renamed After Conversion' WHERE id = v_src;
  SELECT lead_source_id INTO snap_after FROM lead_conversion WHERE lead_id = v_lead;
  PERFORM _m3_acc_record(
    5,
    'conversion attribution snapshot stable after catalog rename',
    snap_before = v_src AND snap_after = v_src AND snap_before = snap_after
  );
END $$;

DO $$
DECLARE total integer; passed integer; failed integer;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE result = 'PASS'), count(*) FILTER (WHERE result = 'FAIL')
    INTO total, passed, failed FROM _m3_acc_results;
  RAISE NOTICE 'M3 milestone acceptance Tests: % / % passed (% failed)', passed, total, failed;
  IF failed > 0 OR total <> 5 THEN
    RAISE EXCEPTION 'M3 milestone acceptance tests failed: % of % (expected 5)', failed, total;
  END IF;
END $$;

ROLLBACK;
