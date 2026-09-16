-- M3-T04: Lead assignment, ownership history, and security tests.

BEGIN;

CREATE TEMP TABLE _m3_as_results (
  test_no   integer PRIMARY KEY,
  test_name text NOT NULL,
  result    text NOT NULL CHECK (result IN ('PASS', 'FAIL'))
);

GRANT ALL ON TABLE _m3_as_results TO authenticated, anon;

CREATE OR REPLACE FUNCTION _m3_as_record(test_no integer, test_name text, passed boolean)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO _m3_as_results (test_no, test_name, result)
  VALUES (test_no, test_name, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END);
END;
$$;

CREATE OR REPLACE FUNCTION _m3_as_expect_fail(test_no integer, test_name text, sql_text text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE sql_text;
    PERFORM _m3_as_record(test_no, test_name, false);
  EXCEPTION WHEN OTHERS THEN
    PERFORM _m3_as_record(test_no, test_name, true);
  END;
END;
$$;

CREATE OR REPLACE FUNCTION _m3_as_as_auth(p_auth_id uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', p_auth_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_auth_id::text, 'role', 'authenticated')::text, true);
END;
$$;

CREATE OR REPLACE FUNCTION _m3_as_as_super()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
END;
$$;

-- 1: assignment history table exists
DO $$
DECLARE cnt integer;
BEGIN
  SELECT count(*) INTO cnt FROM information_schema.tables
  WHERE table_schema = 'public' AND table_name = 'lead_assignment';
  PERFORM _m3_as_record(1, 'lead_assignment table exists', cnt = 1);
END $$;

-- 2: FORCE RLS active
DO $$
DECLARE cnt integer;
BEGIN
  SELECT count(*) INTO cnt FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relname = 'lead_assignment'
    AND c.relrowsecurity AND c.relforcerowsecurity;
  PERFORM _m3_as_record(2, 'FORCE RLS on lead_assignment', cnt = 1);
END $$;

-- 3: assign to same-org eligible user succeeds
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  assignee uuid := 'a1000000-0000-4000-8000-000000000001';
  v_lead uuid;
  v_owner uuid;
BEGIN
  PERFORM _m3_as_as_super();
  INSERT INTO lead (organization_id, status) VALUES (org, 'new') RETURNING id INTO v_lead;
  PERFORM _m3_as_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.assign_lead(v_lead, assignee, 'Initial assign');
  SELECT assigned_user_id INTO v_owner FROM lead WHERE id = v_lead;
  PERFORM _m3_as_record(3, 'assign same-org eligible user', v_owner = assignee);
  PERFORM _m3_as_as_super();
END $$;

-- 4: exactly one history event on assign
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  assignee uuid := 'a1000000-0000-4000-8000-000000000001';
  v_lead uuid;
  hist_cnt integer;
BEGIN
  PERFORM _m3_as_as_super();
  INSERT INTO lead (organization_id, status) VALUES (org, 'new') RETURNING id INTO v_lead;
  PERFORM _m3_as_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.assign_lead(v_lead, assignee, NULL);
  SELECT count(*) INTO hist_cnt FROM lead_assignment WHERE lead_id = v_lead;
  PERFORM _m3_as_record(4, 'assign appends one history event', hist_cnt = 1);
  PERFORM _m3_as_as_super();
END $$;

-- 5: reassignment records previous/new users
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  user_a uuid := 'a1000000-0000-4000-8000-000000000001';
  user_b uuid := 'a2000000-0000-4000-8000-000000000001';
  v_role uuid;
  v_lead uuid;
  prev uuid;
  nxt uuid;
BEGIN
  PERFORM _m3_as_as_super();
  INSERT INTO role (organization_id, code, status) VALUES (org, 'temp_lead_reader_5', 'active')
  RETURNING id INTO v_role;
  INSERT INTO role_permission (role_id, permission_id)
  SELECT v_role, p.id FROM permission p WHERE p.code = 'lead.read';
  INSERT INTO user_role (organization_id, user_id, role_id, effective_from, status)
  VALUES (org, user_b, v_role, CURRENT_DATE, 'active');
  INSERT INTO lead (organization_id, status) VALUES (org, 'new') RETURNING id INTO v_lead;
  PERFORM set_config('olli.lead_assignment_mutation', 'true', true);
  UPDATE lead SET assigned_user_id = user_a WHERE id = v_lead;
  PERFORM set_config('olli.lead_assignment_mutation', 'false', true);
  PERFORM _m3_as_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.assign_lead(v_lead, user_b, 'Reassign');
  SELECT previous_assigned_user_id, new_assigned_user_id
  INTO prev, nxt
  FROM lead_assignment
  WHERE lead_id = v_lead
  ORDER BY changed_at DESC
  LIMIT 1;
  PERFORM _m3_as_record(5, 'reassignment records previous/new', prev = user_a AND nxt = user_b);
  PERFORM _m3_as_as_super();
END $$;

-- 6: unassign records user to NULL
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  assignee uuid := 'a1000000-0000-4000-8000-000000000001';
  v_lead uuid;
  prev uuid;
  nxt uuid;
  v_owner uuid;
BEGIN
  PERFORM _m3_as_as_super();
  INSERT INTO lead (organization_id, status) VALUES (org, 'new') RETURNING id INTO v_lead;
  PERFORM _m3_as_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.assign_lead(v_lead, assignee, NULL);
  PERFORM public.assign_lead(v_lead, NULL, 'Unassign');
  SELECT previous_assigned_user_id, new_assigned_user_id
  INTO prev, nxt
  FROM lead_assignment
  WHERE lead_id = v_lead AND new_assigned_user_id IS NULL
  ORDER BY changed_at DESC
  LIMIT 1;
  SELECT assigned_user_id INTO v_owner FROM lead WHERE id = v_lead;
  PERFORM _m3_as_record(
    6,
    'unassign records user to NULL',
    prev = assignee AND nxt IS NULL AND v_owner IS NULL
  );
  PERFORM _m3_as_as_super();
END $$;

-- 7: actor is server-derived on history
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  assignee uuid := 'a1000000-0000-4000-8000-000000000001';
  actor uuid := 'a1000000-0000-4000-8000-000000000001';
  v_lead uuid;
  changed uuid;
BEGIN
  PERFORM _m3_as_as_super();
  INSERT INTO lead (organization_id, status) VALUES (org, 'new') RETURNING id INTO v_lead;
  PERFORM _m3_as_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.assign_lead(v_lead, assignee, NULL);
  SELECT changed_by INTO changed FROM lead_assignment WHERE lead_id = v_lead LIMIT 1;
  PERFORM _m3_as_record(7, 'actor server-derived on history', changed = actor);
  PERFORM _m3_as_as_super();
END $$;

-- 8: actor spoofing blocked on history insert
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  spoof uuid := 'a5000000-0000-4000-8000-000000000001';
BEGIN
  PERFORM _m3_as_as_super();
  INSERT INTO lead (organization_id, status) VALUES (org, 'new') RETURNING id INTO v_lead;
  PERFORM _m3_as_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM _m3_as_expect_fail(
    8,
    'actor spoofing blocked on history insert',
    format(
      $sql$INSERT INTO lead_assignment (
         organization_id, lead_id, previous_assigned_user_id, new_assigned_user_id, changed_by
       ) VALUES (%L, %L, NULL, %L, %L)$sql$,
      org,
      v_lead,
      'a1000000-0000-4000-8000-000000000001',
      spoof
    )
  );
  PERFORM _m3_as_as_super();
END $$;

-- 9: cross-org target assignee rejected
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  user_b uuid := 'b1000000-0000-4000-8000-000000000001';
  v_lead uuid;
BEGIN
  PERFORM _m3_as_as_super();
  INSERT INTO lead (organization_id, status) VALUES (org, 'new') RETURNING id INTO v_lead;
  PERFORM _m3_as_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM _m3_as_expect_fail(
    9,
    'cross-org target assignee rejected',
    format($sql$SELECT public.assign_lead(%L, %L, NULL)$sql$, v_lead, user_b)
  );
  PERFORM _m3_as_as_super();
END $$;

-- 10: cross-org lead assignment rejected
DO $$
DECLARE
  org_b uuid := 'b0000000-0000-4000-8000-000000000001';
  assignee uuid := 'a1000000-0000-4000-8000-000000000001';
  v_lead uuid;
BEGIN
  PERFORM _m3_as_as_super();
  INSERT INTO lead (organization_id, status) VALUES (org_b, 'new') RETURNING id INTO v_lead;
  PERFORM _m3_as_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM _m3_as_expect_fail(
    10,
    'cross-org lead assignment rejected',
    format($sql$SELECT public.assign_lead(%L, %L, NULL)$sql$, v_lead, assignee)
  );
  PERFORM _m3_as_as_super();
END $$;

-- 11: lead.update without lead.assign cannot assign
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_role uuid;
  v_lead uuid;
  assignee uuid := 'a1000000-0000-4000-8000-000000000001';
BEGIN
  PERFORM _m3_as_as_super();
  INSERT INTO role (organization_id, code, status) VALUES (org, 'crm_updater_only', 'active')
  RETURNING id INTO v_role;
  INSERT INTO role_permission (role_id, permission_id)
  SELECT v_role, p.id FROM permission p WHERE p.code IN ('lead.read', 'lead.update');
  INSERT INTO user_role (organization_id, user_id, role_id, effective_from, status)
  VALUES (org, 'a2000000-0000-4000-8000-000000000001', v_role, CURRENT_DATE, 'active');
  INSERT INTO lead (organization_id, status) VALUES (org, 'new') RETURNING id INTO v_lead;
  PERFORM _m3_as_as_auth('a2222222-2222-4222-8222-222222222222');
  PERFORM _m3_as_expect_fail(
    11,
    'lead.update without lead.assign cannot assign',
    format($sql$SELECT public.assign_lead(%L, %L, NULL)$sql$, v_lead, assignee)
  );
  PERFORM _m3_as_as_super();
END $$;

-- 12: lead.assign works without sales role
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_role uuid;
  v_lead uuid;
  assignee uuid := 'a1000000-0000-4000-8000-000000000001';
  staff_user uuid := 'a2000000-0000-4000-8000-000000000001';
  v_owner uuid;
BEGIN
  PERFORM _m3_as_as_super();
  INSERT INTO role (organization_id, code, status) VALUES (org, 'crm_assign_only', 'active')
  RETURNING id INTO v_role;
  INSERT INTO role_permission (role_id, permission_id)
  SELECT v_role, p.id FROM permission p WHERE p.code IN ('lead.read', 'lead.assign');
  INSERT INTO user_role (organization_id, user_id, role_id, effective_from, status)
  VALUES (org, staff_user, v_role, CURRENT_DATE, 'active');
  INSERT INTO lead (organization_id, status) VALUES (org, 'new') RETURNING id INTO v_lead;
  PERFORM _m3_as_as_auth('a2222222-2222-4222-8222-222222222222');
  PERFORM public.assign_lead(v_lead, assignee, NULL);
  PERFORM _m3_as_as_super();
  SELECT assigned_user_id INTO v_owner FROM lead WHERE id = v_lead;
  PERFORM _m3_as_record(12, 'lead.assign without sales role', v_owner = assignee);
END $$;

-- 13: direct assigned_user_id update bypass blocked
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  assignee uuid := 'a1000000-0000-4000-8000-000000000001';
  v_lead uuid;
BEGIN
  PERFORM _m3_as_as_super();
  INSERT INTO lead (organization_id, status) VALUES (org, 'new') RETURNING id INTO v_lead;
  PERFORM _m3_as_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM _m3_as_expect_fail(
    13,
    'direct assigned_user_id update bypass blocked',
    format($sql$UPDATE lead SET assigned_user_id = %L WHERE id = %L$sql$, assignee, v_lead)
  );
  PERFORM _m3_as_as_super();
END $$;

-- 14: ordinary non-assignment lead.update still works
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  v_notes text;
BEGIN
  PERFORM _m3_as_as_super();
  INSERT INTO lead (organization_id, status) VALUES (org, 'new') RETURNING id INTO v_lead;
  PERFORM _m3_as_as_auth('a1111111-1111-4111-8111-111111111111');
  UPDATE lead SET notes_summary = 'Updated notes' WHERE id = v_lead;
  SELECT notes_summary INTO v_notes FROM lead WHERE id = v_lead;
  PERFORM _m3_as_record(14, 'ordinary lead.update still works', v_notes = 'Updated notes');
  PERFORM _m3_as_as_super();
END $$;

-- 15: no-op assignment succeeds without history
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  assignee uuid := 'a1000000-0000-4000-8000-000000000001';
  v_lead uuid;
  before_cnt integer;
  after_cnt integer;
  v_result jsonb;
BEGIN
  PERFORM _m3_as_as_super();
  INSERT INTO lead (organization_id, status) VALUES (org, 'new') RETURNING id INTO v_lead;
  PERFORM _m3_as_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.assign_lead(v_lead, assignee, NULL);
  SELECT count(*) INTO before_cnt FROM lead_assignment WHERE lead_id = v_lead;
  v_result := public.assign_lead(v_lead, assignee, 'No change');
  SELECT count(*) INTO after_cnt FROM lead_assignment WHERE lead_id = v_lead;
  PERFORM _m3_as_record(
    15,
    'no-op assignment succeeds without new history',
    before_cnt = after_cnt AND (v_result->>'no_op')::boolean = true
  );
  PERFORM _m3_as_as_super();
END $$;

-- 16: inactive assignee rejected
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  inactive uuid := 'a3000000-0000-4000-8000-000000000001';
  v_lead uuid;
BEGIN
  PERFORM _m3_as_as_super();
  INSERT INTO lead (organization_id, status) VALUES (org, 'new') RETURNING id INTO v_lead;
  PERFORM _m3_as_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM _m3_as_expect_fail(
    16,
    'inactive assignee rejected',
    format($sql$SELECT public.assign_lead(%L, %L, NULL)$sql$, v_lead, inactive)
  );
  PERFORM _m3_as_as_super();
END $$;

-- 17: initial lead create cannot bypass lead.assign
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  assignee uuid := 'a1000000-0000-4000-8000-000000000001';
BEGIN
  PERFORM _m3_as_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM _m3_as_expect_fail(
    17,
    'initial assignment on create blocked without assign_lead',
    format(
      $sql$INSERT INTO lead (organization_id, status, assigned_user_id)
         VALUES (%L, 'new', %L)$sql$,
      org,
      assignee
    )
  );
  PERFORM _m3_as_as_super();
END $$;

-- 18: history cannot be updated
DO $$
DECLARE pol integer;
BEGIN
  SELECT count(*) INTO pol FROM pg_policies
  WHERE schemaname = 'public' AND tablename = 'lead_assignment' AND cmd = 'UPDATE';
  PERFORM _m3_as_record(18, 'history has no update policy', pol = 0);
END $$;

-- 19: history cannot be deleted
DO $$
DECLARE pol integer;
BEGIN
  SELECT count(*) INTO pol FROM pg_policies
  WHERE schemaname = 'public' AND tablename = 'lead_assignment' AND cmd = 'DELETE';
  PERFORM _m3_as_record(19, 'history has no delete policy', pol = 0);
END $$;

-- 20: concurrent-safe previous owner semantics
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  user_a uuid := 'a1000000-0000-4000-8000-000000000001';
  user_b uuid := 'a2000000-0000-4000-8000-000000000001';
  v_role uuid;
  v_lead uuid;
  prev uuid;
BEGIN
  PERFORM _m3_as_as_super();
  INSERT INTO role (organization_id, code, status) VALUES (org, 'temp_lead_reader_20', 'active')
  RETURNING id INTO v_role;
  INSERT INTO role_permission (role_id, permission_id)
  SELECT v_role, p.id FROM permission p WHERE p.code = 'lead.read';
  INSERT INTO user_role (organization_id, user_id, role_id, effective_from, status)
  VALUES (org, user_b, v_role, CURRENT_DATE, 'active');
  INSERT INTO lead (organization_id, status) VALUES (org, 'new') RETURNING id INTO v_lead;
  PERFORM set_config('olli.lead_assignment_mutation', 'true', true);
  UPDATE lead SET assigned_user_id = user_a WHERE id = v_lead;
  PERFORM set_config('olli.lead_assignment_mutation', 'false', true);
  PERFORM _m3_as_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.assign_lead(v_lead, user_b, 'Observed previous');
  SELECT previous_assigned_user_id INTO prev
  FROM lead_assignment WHERE lead_id = v_lead ORDER BY changed_at DESC LIMIT 1;
  PERFORM _m3_as_record(20, 'history reflects locked previous owner', prev = user_a);
  PERFORM _m3_as_as_super();
END $$;

-- 21: assignment does not change lifecycle status
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  assignee uuid := 'a1000000-0000-4000-8000-000000000001';
  v_lead uuid;
  v_status text;
BEGIN
  PERFORM _m3_as_as_super();
  INSERT INTO lead (organization_id, status) VALUES (org, 'qualified') RETURNING id INTO v_lead;
  PERFORM _m3_as_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.assign_lead(v_lead, assignee, NULL);
  SELECT status INTO v_status FROM lead WHERE id = v_lead;
  PERFORM _m3_as_record(21, 'assignment does not change status', v_status = 'qualified');
  PERFORM _m3_as_as_super();
END $$;

-- 22: assignment does not change lost fields
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  reason uuid;
  assignee uuid := 'a1000000-0000-4000-8000-000000000001';
  v_lead uuid;
  v_reason uuid;
  v_notes text;
BEGIN
  PERFORM _m3_as_as_super();
  SELECT id INTO reason FROM lead_lost_reason WHERE organization_id = org LIMIT 1;
  INSERT INTO lead (organization_id, status, lost_reason_id, lost_notes, lost_at, lost_by)
  VALUES (org, 'lost', reason, 'Price', now(), 'a1000000-0000-4000-8000-000000000001')
  RETURNING id INTO v_lead;
  PERFORM _m3_as_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.assign_lead(v_lead, assignee, NULL);
  SELECT lost_reason_id, lost_notes INTO v_reason, v_notes FROM lead WHERE id = v_lead;
  PERFORM _m3_as_record(
    22,
    'assignment does not change lost fields',
    v_reason = reason AND v_notes = 'Price'
  );
  PERFORM _m3_as_as_super();
END $$;

-- 23: follow-up owner not silently rewritten
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  user_a uuid := 'a1000000-0000-4000-8000-000000000001';
  user_b uuid := 'a2000000-0000-4000-8000-000000000001';
  v_role uuid;
  v_lead uuid;
  v_fu uuid;
  fu_owner uuid;
BEGIN
  PERFORM _m3_as_as_super();
  INSERT INTO role (organization_id, code, status) VALUES (org, 'temp_lead_reader_23', 'active')
  RETURNING id INTO v_role;
  INSERT INTO role_permission (role_id, permission_id)
  SELECT v_role, p.id FROM permission p WHERE p.code = 'lead.read';
  INSERT INTO user_role (organization_id, user_id, role_id, effective_from, status)
  VALUES (org, user_b, v_role, CURRENT_DATE, 'active');
  INSERT INTO lead (organization_id, status) VALUES (org, 'new') RETURNING id INTO v_lead;
  PERFORM _m3_as_as_auth('a1111111-1111-4111-8111-111111111111');
  v_fu := public.create_lead_follow_up(v_lead, now() + interval '1 day', 'Follow-up', user_a);
  PERFORM public.assign_lead(v_lead, user_b, 'Lead owner changed');
  SELECT assigned_user_id INTO fu_owner FROM lead_follow_up WHERE id = v_fu;
  PERFORM _m3_as_record(23, 'follow-up owner not rewritten', fu_owner = user_a);
  PERFORM _m3_as_as_super();
END $$;

-- 24: assignment has no M1 side effects
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  assignee uuid := 'a1000000-0000-4000-8000-000000000001';
  v_lead uuid;
  before_s integer;
  after_s integer;
BEGIN
  PERFORM _m3_as_as_super();
  SELECT count(*) INTO before_s FROM student WHERE organization_id = org;
  INSERT INTO lead (organization_id, status) VALUES (org, 'new') RETURNING id INTO v_lead;
  PERFORM _m3_as_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.assign_lead(v_lead, assignee, NULL);
  PERFORM _m3_as_as_super();
  SELECT count(*) INTO after_s FROM student WHERE organization_id = org;
  PERFORM _m3_as_record(24, 'assignment no M1 side effects', before_s = after_s);
END $$;

-- 25: assignment has no M2 side effects
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  assignee uuid := 'a1000000-0000-4000-8000-000000000001';
  v_lead uuid;
  before_c integer;
  after_c integer;
BEGIN
  PERFORM _m3_as_as_super();
  SELECT count(*) INTO before_c FROM charge WHERE organization_id = org;
  INSERT INTO lead (organization_id, status) VALUES (org, 'new') RETURNING id INTO v_lead;
  PERFORM _m3_as_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.assign_lead(v_lead, assignee, NULL);
  PERFORM _m3_as_as_super();
  SELECT count(*) INTO after_c FROM charge WHERE organization_id = org;
  PERFORM _m3_as_record(25, 'assignment no M2 side effects', before_c = after_c);
END $$;

-- 26: non-eligible user without lead.read rejected
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  no_lead_read uuid := 'a5000000-0000-4000-8000-000000000001';
  v_lead uuid;
BEGIN
  PERFORM _m3_as_as_super();
  INSERT INTO lead (organization_id, status) VALUES (org, 'new') RETURNING id INTO v_lead;
  PERFORM _m3_as_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM _m3_as_expect_fail(
    26,
    'user without lead.read rejected as assignee',
    format($sql$SELECT public.assign_lead(%L, %L, NULL)$sql$, v_lead, no_lead_read)
  );
  PERFORM _m3_as_as_super();
END $$;

-- 27: cross-org assignment history access blocked
DO $$
DECLARE
  org_b uuid := 'b0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  cnt integer;
BEGIN
  PERFORM _m3_as_as_super();
  INSERT INTO lead (organization_id, status) VALUES (org_b, 'new') RETURNING id INTO v_lead;
  INSERT INTO lead_assignment (
    organization_id, lead_id, previous_assigned_user_id, new_assigned_user_id, changed_by
  )
  SELECT org_b, v_lead, NULL, id, id FROM app_user WHERE email = 'org-b-admin@olli.local';
  PERFORM _m3_as_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO cnt FROM lead_assignment WHERE lead_id = v_lead;
  PERFORM _m3_as_record(27, 'cross-org assignment history blocked', cnt = 0);
  PERFORM _m3_as_as_super();
END $$;

DO $$
DECLARE total integer; passed integer; failed integer;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE result = 'PASS'), count(*) FILTER (WHERE result = 'FAIL')
  INTO total, passed, failed FROM _m3_as_results;
  IF failed > 0 THEN
    RAISE EXCEPTION 'M3 Lead Assignment Tests: % / % passed (% failed)', passed, total, failed;
  END IF;
  RAISE NOTICE 'M3 Lead Assignment Tests: % / % passed (0 failed)', passed, total;
END $$;

-- Restore seed fixture permission state (tests above add temporary CRM roles).
DELETE FROM user_role
WHERE role_id IN (
  SELECT id FROM role
  WHERE code IN (
    'crm_updater_only',
    'crm_assign_only',
    'temp_lead_reader_5',
    'temp_lead_reader_20',
    'temp_lead_reader_23'
  )
);
DELETE FROM role_permission
WHERE role_id IN (
  SELECT id FROM role
  WHERE code IN (
    'crm_updater_only',
    'crm_assign_only',
    'temp_lead_reader_5',
    'temp_lead_reader_20',
    'temp_lead_reader_23'
  )
);
DELETE FROM role
WHERE code IN (
  'crm_updater_only',
  'crm_assign_only',
  'temp_lead_reader_5',
  'temp_lead_reader_20',
  'temp_lead_reader_23'
);

COMMIT;
