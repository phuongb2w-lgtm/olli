-- M3-T05: Lead trial workflow and security tests.

BEGIN;

CREATE TEMP TABLE _m3_tr_results (
  test_no   integer PRIMARY KEY,
  test_name text NOT NULL,
  result    text NOT NULL CHECK (result IN ('PASS', 'FAIL'))
);

GRANT ALL ON TABLE _m3_tr_results TO authenticated, anon;

CREATE OR REPLACE FUNCTION _m3_tr_record(test_no integer, test_name text, passed boolean)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO _m3_tr_results (test_no, test_name, result)
  VALUES (test_no, test_name, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END);
END;
$$;

CREATE OR REPLACE FUNCTION _m3_tr_expect_fail(test_no integer, test_name text, sql_text text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE sql_text;
    PERFORM _m3_tr_record(test_no, test_name, false);
  EXCEPTION WHEN OTHERS THEN
    PERFORM _m3_tr_record(test_no, test_name, true);
  END;
END;
$$;

CREATE OR REPLACE FUNCTION _m3_tr_as_auth(p_auth_id uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', p_auth_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_auth_id::text, 'role', 'authenticated')::text, true);
END;
$$;

CREATE OR REPLACE FUNCTION _m3_tr_as_super()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
END;
$$;

-- 1–2: tables exist
DO $$
DECLARE cnt integer;
BEGIN
  SELECT count(*) INTO cnt FROM information_schema.tables
  WHERE table_schema = 'public' AND table_name = 'lead_trial';
  PERFORM _m3_tr_record(1, 'lead_trial table exists', cnt = 1);
  SELECT count(*) INTO cnt FROM information_schema.tables
  WHERE table_schema = 'public' AND table_name = 'lead_trial_event';
  PERFORM _m3_tr_record(2, 'lead_trial_event table exists', cnt = 1);
END $$;

-- 3–4: FORCE RLS
DO $$
DECLARE cnt integer;
BEGIN
  SELECT count(*) INTO cnt FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relname = 'lead_trial'
    AND c.relrowsecurity AND c.relforcerowsecurity;
  PERFORM _m3_tr_record(3, 'FORCE RLS on lead_trial', cnt = 1);
  SELECT count(*) INTO cnt FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relname = 'lead_trial_event'
    AND c.relrowsecurity AND c.relforcerowsecurity;
  PERFORM _m3_tr_record(4, 'FORCE RLS on lead_trial_event', cnt = 1);
END $$;

-- 5: same-org schedule succeeds
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  v_candidate uuid;
  v_class uuid;
  v_trial uuid;
BEGIN
  PERFORM _m3_tr_as_super();
  INSERT INTO lead (organization_id, status) VALUES (org, 'qualified') RETURNING id INTO v_lead;
  INSERT INTO lead_candidate (organization_id, lead_id, given_name, family_name, is_primary_candidate)
  VALUES (org, v_lead, 'Trial', 'Candidate', true) RETURNING id INTO v_candidate;
  SELECT id INTO v_class FROM class WHERE organization_id = org AND name = 'Class A1' LIMIT 1;
  PERFORM _m3_tr_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT (public.schedule_lead_trial(
    v_lead, v_candidate, v_class, NULL,
    now() + interval '3 days', now() + interval '3 days 90 minutes', 'Initial trial'
  )->>'trial_id')::uuid INTO v_trial;
  PERFORM _m3_tr_record(5, 'same-org candidate trial schedule succeeds', v_trial IS NOT NULL);
  PERFORM _m3_tr_as_super();
END $$;

-- 6: candidate from another lead rejected
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead_a uuid;
  v_lead_b uuid;
  v_candidate_b uuid;
  v_class uuid;
  ok boolean := false;
BEGIN
  PERFORM _m3_tr_as_super();
  INSERT INTO lead (organization_id, status) VALUES (org, 'qualified') RETURNING id INTO v_lead_a;
  INSERT INTO lead (organization_id, status) VALUES (org, 'qualified') RETURNING id INTO v_lead_b;
  INSERT INTO lead_candidate (organization_id, lead_id, given_name, family_name, is_primary_candidate)
  VALUES (org, v_lead_b, 'Other', 'Lead', true) RETURNING id INTO v_candidate_b;
  SELECT id INTO v_class FROM class WHERE organization_id = org AND name = 'Class A1' LIMIT 1;
  PERFORM _m3_tr_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.schedule_lead_trial(
      v_lead_a, v_candidate_b, v_class, NULL,
      now() + interval '2 days', now() + interval '2 days 90 minutes', NULL
    );
  EXCEPTION WHEN OTHERS THEN ok := true;
  END;
  PERFORM _m3_tr_record(6, 'candidate from another lead rejected', ok);
  PERFORM _m3_tr_as_super();
END $$;

-- 7: cross-org candidate rejected
DO $$
DECLARE
  org_a uuid := 'a0000000-0000-4000-8000-000000000001';
  org_b uuid := 'b0000000-0000-4000-8000-000000000002';
  v_lead uuid;
  v_candidate uuid;
  v_class uuid;
  ok boolean := false;
BEGIN
  PERFORM _m3_tr_as_super();
  INSERT INTO lead (organization_id, status) VALUES (org_a, 'qualified') RETURNING id INTO v_lead;
  SELECT id INTO v_candidate FROM lead_candidate WHERE organization_id = org_b LIMIT 1;
  SELECT id INTO v_class FROM class WHERE organization_id = org_a AND name = 'Class A1' LIMIT 1;
  PERFORM _m3_tr_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.schedule_lead_trial(
      v_lead, v_candidate, v_class, NULL,
      now() + interval '2 days', now() + interval '2 days 90 minutes', NULL
    );
  EXCEPTION WHEN OTHERS THEN ok := true;
  END;
  PERFORM _m3_tr_record(7, 'cross-org candidate rejected', ok);
  PERFORM _m3_tr_as_super();
END $$;

-- 8: cross-org class rejected
DO $$
DECLARE
  org_a uuid := 'a0000000-0000-4000-8000-000000000001';
  org_b uuid := 'b0000000-0000-4000-8000-000000000002';
  v_lead uuid;
  v_candidate uuid;
  v_class uuid;
  ok boolean := false;
BEGIN
  PERFORM _m3_tr_as_super();
  INSERT INTO lead (organization_id, status) VALUES (org_a, 'qualified') RETURNING id INTO v_lead;
  INSERT INTO lead_candidate (organization_id, lead_id, given_name, family_name, is_primary_candidate)
  VALUES (org_a, v_lead, 'X', 'Y', true) RETURNING id INTO v_candidate;
  SELECT id INTO v_class FROM class WHERE organization_id = org_b LIMIT 1;
  PERFORM _m3_tr_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.schedule_lead_trial(
      v_lead, v_candidate, v_class, NULL,
      now() + interval '2 days', now() + interval '2 days 90 minutes', NULL
    );
  EXCEPTION WHEN OTHERS THEN ok := true;
  END;
  PERFORM _m3_tr_record(8, 'cross-org class rejected', ok);
  PERFORM _m3_tr_as_super();
END $$;

-- 9: cross-org teaching session rejected
DO $$
DECLARE
  org_a uuid := 'a0000000-0000-4000-8000-000000000001';
  org_b uuid := 'b0000000-0000-4000-8000-000000000002';
  v_lead uuid;
  v_candidate uuid;
  v_class uuid;
  v_session uuid;
  ok boolean := false;
BEGIN
  PERFORM _m3_tr_as_super();
  INSERT INTO lead (organization_id, status) VALUES (org_a, 'qualified') RETURNING id INTO v_lead;
  INSERT INTO lead_candidate (organization_id, lead_id, given_name, family_name, is_primary_candidate)
  VALUES (org_a, v_lead, 'X', 'Y', true) RETURNING id INTO v_candidate;
  SELECT id INTO v_class FROM class WHERE organization_id = org_a AND name = 'Class A1' LIMIT 1;
  SELECT id INTO v_session FROM teaching_session WHERE organization_id = org_b LIMIT 1;
  PERFORM _m3_tr_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.schedule_lead_trial(v_lead, v_candidate, v_class, v_session, NULL, NULL, NULL);
  EXCEPTION WHEN OTHERS THEN ok := true;
  END;
  PERFORM _m3_tr_record(9, 'cross-org teaching session rejected', ok);
  PERFORM _m3_tr_as_super();
END $$;

-- 10: session/class mismatch rejected
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  v_candidate uuid;
  v_class_a uuid;
  v_class_b uuid;
  v_session uuid;
  ok boolean := false;
BEGIN
  PERFORM _m3_tr_as_super();
  INSERT INTO lead (organization_id, status) VALUES (org, 'qualified') RETURNING id INTO v_lead;
  INSERT INTO lead_candidate (organization_id, lead_id, given_name, family_name, is_primary_candidate)
  VALUES (org, v_lead, 'X', 'Y', true) RETURNING id INTO v_candidate;
  SELECT id INTO v_class_a FROM class WHERE organization_id = org AND name = 'Class A1' LIMIT 1;
  INSERT INTO class (organization_id, course_id, name, status)
  SELECT org, course_id, 'Temp Class B', 'active' FROM class WHERE id = v_class_a
  RETURNING id INTO v_class_b;
  SELECT id INTO v_session FROM teaching_session WHERE organization_id = org AND class_id = v_class_a LIMIT 1;
  PERFORM _m3_tr_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.schedule_lead_trial(v_lead, v_candidate, v_class_b, v_session, NULL, NULL, NULL);
  EXCEPTION WHEN OTHERS THEN ok := true;
  END;
  PERFORM _m3_tr_record(10, 'teaching session class mismatch rejected', ok);
  PERFORM _m3_tr_as_super();
END $$;

-- 11: invalid trial state rejected at DB level
DO $$
DECLARE ok boolean := false;
BEGIN
  PERFORM _m3_tr_as_super();
  BEGIN
    PERFORM set_config('olli.lead_trial_mutation', 'true', true);
    INSERT INTO lead_trial (
      organization_id, lead_id, lead_candidate_id, class_id,
      status, scheduled_start_at, scheduled_end_at, created_by
    )
    SELECT
      l.organization_id, l.id, c.id, cl.id,
      'rescheduled', now(), now() + interval '1 hour', u.id
    FROM lead l
    JOIN lead_candidate c ON c.lead_id = l.id
    JOIN class cl ON cl.organization_id = l.organization_id
    JOIN app_user u ON u.organization_id = l.organization_id
    LIMIT 1;
    PERFORM set_config('olli.lead_trial_mutation', 'false', true);
  EXCEPTION WHEN check_violation THEN
    PERFORM set_config('olli.lead_trial_mutation', 'false', true);
    ok := true;
  END;
  PERFORM _m3_tr_record(11, 'invalid trial state rejected', ok);
END $$;

-- 12: lost lead cannot schedule
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  v_candidate uuid;
  v_class uuid;
  v_reason uuid;
  ok boolean := false;
BEGIN
  PERFORM _m3_tr_as_super();
  INSERT INTO lead (organization_id, status) VALUES (org, 'qualified') RETURNING id INTO v_lead;
  INSERT INTO lead_candidate (organization_id, lead_id, given_name, family_name, is_primary_candidate)
  VALUES (org, v_lead, 'Lost', 'Lead', true) RETURNING id INTO v_candidate;
  SELECT id INTO v_class FROM class WHERE organization_id = org AND name = 'Class A1' LIMIT 1;
  SELECT id INTO v_reason FROM lead_lost_reason WHERE organization_id = org AND code = 'other' LIMIT 1;
  PERFORM _m3_tr_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.transition_lead_status(v_lead, 'lost', v_reason, 'Lost for trial test');
  BEGIN
    PERFORM public.schedule_lead_trial(
      v_lead, v_candidate, v_class, NULL,
      now() + interval '2 days', now() + interval '2 days 90 minutes', NULL
    );
  EXCEPTION WHEN OTHERS THEN ok := true;
  END;
  PERFORM _m3_tr_record(12, 'lost lead cannot schedule until reactivated', ok);
  PERFORM _m3_tr_as_super();
END $$;

-- 13: converted lead cannot schedule
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  v_candidate uuid;
  v_class uuid;
  ok boolean := false;
BEGIN
  PERFORM _m3_tr_as_super();
  INSERT INTO lead (organization_id, status, converted_at) VALUES (org, 'converted', now()) RETURNING id INTO v_lead;
  ALTER TABLE lead_candidate DISABLE TRIGGER lead_candidate_protect_converted_edits;
  INSERT INTO lead_candidate (organization_id, lead_id, given_name, family_name, is_primary_candidate)
  VALUES (org, v_lead, 'Converted', 'Lead', true) RETURNING id INTO v_candidate;
  ALTER TABLE lead_candidate ENABLE TRIGGER lead_candidate_protect_converted_edits;
  SELECT id INTO v_class FROM class WHERE organization_id = org AND name = 'Class A1' LIMIT 1;
  PERFORM _m3_tr_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.schedule_lead_trial(
      v_lead, v_candidate, v_class, NULL,
      now() + interval '2 days', now() + interval '2 days 90 minutes', NULL
    );
  EXCEPTION WHEN OTHERS THEN ok := true;
  END;
  PERFORM _m3_tr_record(13, 'converted lead cannot schedule', ok);
  PERFORM _m3_tr_as_super();
END $$;

-- 14: scheduling appends exactly one trial event
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  v_candidate uuid;
  v_class uuid;
  v_trial uuid;
  evt_cnt integer;
BEGIN
  PERFORM _m3_tr_as_super();
  INSERT INTO lead (organization_id, status) VALUES (org, 'qualified') RETURNING id INTO v_lead;
  INSERT INTO lead_candidate (organization_id, lead_id, given_name, family_name, is_primary_candidate)
  VALUES (org, v_lead, 'Evt', 'One', true) RETURNING id INTO v_candidate;
  SELECT id INTO v_class FROM class WHERE organization_id = org AND name = 'Class A1' LIMIT 1;
  PERFORM _m3_tr_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT (public.schedule_lead_trial(
    v_lead, v_candidate, v_class, NULL,
    now() + interval '4 days', now() + interval '4 days 90 minutes', NULL
  )->>'trial_id')::uuid INTO v_trial;
  SELECT count(*) INTO evt_cnt FROM lead_trial_event WHERE lead_trial_id = v_trial;
  PERFORM _m3_tr_record(14, 'scheduling appends one trial event', evt_cnt = 1);
  PERFORM _m3_tr_as_super();
END $$;

-- 15: scheduling advances lifecycle to trial_scheduled
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  v_candidate uuid;
  v_class uuid;
  v_status text;
BEGIN
  PERFORM _m3_tr_as_super();
  INSERT INTO lead (organization_id, status) VALUES (org, 'new') RETURNING id INTO v_lead;
  INSERT INTO lead_candidate (organization_id, lead_id, given_name, family_name, is_primary_candidate)
  VALUES (org, v_lead, 'Life', 'Cycle', true) RETURNING id INTO v_candidate;
  SELECT id INTO v_class FROM class WHERE organization_id = org AND name = 'Class A1' LIMIT 1;
  PERFORM _m3_tr_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.schedule_lead_trial(
    v_lead, v_candidate, v_class, NULL,
    now() + interval '5 days', now() + interval '5 days 90 minutes', NULL
  );
  SELECT status INTO v_status FROM lead WHERE id = v_lead;
  PERFORM _m3_tr_record(15, 'scheduling advances lifecycle to trial_scheduled', v_status = 'trial_scheduled');
  PERFORM _m3_tr_as_super();
END $$;

-- 16–17: reschedule preserves history and appends event
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  v_candidate uuid;
  v_class uuid;
  v_trial uuid;
  evt_cnt integer;
  sched_cnt integer;
  resched_cnt integer;
BEGIN
  PERFORM _m3_tr_as_super();
  INSERT INTO lead (organization_id, status) VALUES (org, 'qualified') RETURNING id INTO v_lead;
  INSERT INTO lead_candidate (organization_id, lead_id, given_name, family_name, is_primary_candidate)
  VALUES (org, v_lead, 'Re', 'Schedule', true) RETURNING id INTO v_candidate;
  SELECT id INTO v_class FROM class WHERE organization_id = org AND name = 'Class A1' LIMIT 1;
  PERFORM _m3_tr_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT (public.schedule_lead_trial(
    v_lead, v_candidate, v_class, NULL,
    now() + interval '6 days', now() + interval '6 days 90 minutes', NULL
  )->>'trial_id')::uuid INTO v_trial;
  PERFORM public.reschedule_lead_trial(
    v_trial, NULL, NULL, now() + interval '7 days', now() + interval '7 days 90 minutes', 'Moved'
  );
  SELECT count(*) INTO evt_cnt FROM lead_trial_event WHERE lead_trial_id = v_trial;
  SELECT count(*) INTO sched_cnt FROM lead_trial_event
  WHERE lead_trial_id = v_trial AND event_type = 'scheduled';
  SELECT count(*) INTO resched_cnt FROM lead_trial_event
  WHERE lead_trial_id = v_trial AND event_type = 'rescheduled';
  PERFORM _m3_tr_record(16, 'reschedule preserves original history', sched_cnt = 1 AND resched_cnt = 1);
  PERFORM _m3_tr_record(17, 'reschedule appends new event', evt_cnt = 2);
  PERFORM _m3_tr_as_super();
END $$;

-- 18–19: completion appends event and advances lifecycle
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  v_candidate uuid;
  v_class uuid;
  v_trial uuid;
  evt_cnt integer;
  v_status text;
BEGIN
  PERFORM _m3_tr_as_super();
  INSERT INTO lead (organization_id, status) VALUES (org, 'trial_scheduled') RETURNING id INTO v_lead;
  INSERT INTO lead_candidate (organization_id, lead_id, given_name, family_name, is_primary_candidate)
  VALUES (org, v_lead, 'Complete', 'Me', true) RETURNING id INTO v_candidate;
  SELECT id INTO v_class FROM class WHERE organization_id = org AND name = 'Class A1' LIMIT 1;
  PERFORM _m3_tr_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT (public.schedule_lead_trial(
    v_lead, v_candidate, v_class, NULL,
    now() - interval '1 day', now() - interval '1 day' + interval '90 minutes', NULL
  )->>'trial_id')::uuid INTO v_trial;
  PERFORM public.complete_lead_trial(v_trial, 'Interested');
  SELECT count(*) INTO evt_cnt FROM lead_trial_event WHERE lead_trial_id = v_trial AND event_type = 'completed';
  SELECT status INTO v_status FROM lead WHERE id = v_lead;
  PERFORM _m3_tr_record(18, 'completion appends event', evt_cnt = 1);
  PERFORM _m3_tr_record(19, 'completion advances lifecycle to trial_completed', v_status = 'trial_completed');
  PERFORM _m3_tr_as_super();
END $$;

-- 20: cancellation appends event
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  v_candidate uuid;
  v_class uuid;
  v_trial uuid;
  evt_cnt integer;
BEGIN
  PERFORM _m3_tr_as_super();
  INSERT INTO lead (organization_id, status) VALUES (org, 'qualified') RETURNING id INTO v_lead;
  INSERT INTO lead_candidate (organization_id, lead_id, given_name, family_name, is_primary_candidate)
  VALUES (org, v_lead, 'Cancel', 'Me', true) RETURNING id INTO v_candidate;
  SELECT id INTO v_class FROM class WHERE organization_id = org AND name = 'Class A1' LIMIT 1;
  PERFORM _m3_tr_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT (public.schedule_lead_trial(
    v_lead, v_candidate, v_class, NULL,
    now() + interval '8 days', now() + interval '8 days 90 minutes', NULL
  )->>'trial_id')::uuid INTO v_trial;
  PERFORM public.cancel_lead_trial(v_trial, 'Family conflict');
  SELECT count(*) INTO evt_cnt FROM lead_trial_event WHERE lead_trial_id = v_trial AND event_type = 'cancelled';
  PERFORM _m3_tr_record(20, 'cancellation appends event', evt_cnt = 1);
  PERFORM _m3_tr_as_super();
END $$;

-- 21: no-show appends event
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  v_candidate uuid;
  v_class uuid;
  v_trial uuid;
  evt_cnt integer;
BEGIN
  PERFORM _m3_tr_as_super();
  INSERT INTO lead (organization_id, status) VALUES (org, 'qualified') RETURNING id INTO v_lead;
  INSERT INTO lead_candidate (organization_id, lead_id, given_name, family_name, is_primary_candidate)
  VALUES (org, v_lead, 'NoShow', 'Me', true) RETURNING id INTO v_candidate;
  SELECT id INTO v_class FROM class WHERE organization_id = org AND name = 'Class A1' LIMIT 1;
  PERFORM _m3_tr_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT (public.schedule_lead_trial(
    v_lead, v_candidate, v_class, NULL,
    now() - interval '2 hours', now() - interval '30 minutes', NULL
  )->>'trial_id')::uuid INTO v_trial;
  PERFORM public.mark_lead_trial_no_show(v_trial, 'Did not arrive');
  SELECT count(*) INTO evt_cnt FROM lead_trial_event WHERE lead_trial_id = v_trial AND event_type = 'no_show';
  PERFORM _m3_tr_record(21, 'no-show appends event', evt_cnt = 1);
  PERFORM _m3_tr_as_super();
END $$;

-- 22–23: cancelled/no-show cannot be completed
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  v_candidate uuid;
  v_class uuid;
  v_cancel uuid;
  v_noshow uuid;
  ok_cancel boolean := false;
  ok_noshow boolean := false;
BEGIN
  PERFORM _m3_tr_as_super();
  INSERT INTO lead (organization_id, status) VALUES (org, 'qualified') RETURNING id INTO v_lead;
  INSERT INTO lead_candidate (organization_id, lead_id, given_name, family_name, is_primary_candidate)
  VALUES (org, v_lead, 'Terminal', 'States', true) RETURNING id INTO v_candidate;
  SELECT id INTO v_class FROM class WHERE organization_id = org AND name = 'Class A1' LIMIT 1;
  PERFORM _m3_tr_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT (public.schedule_lead_trial(
    v_lead, v_candidate, v_class, NULL,
    now() + interval '9 days', now() + interval '9 days 90 minutes', NULL
  )->>'trial_id')::uuid INTO v_cancel;
  PERFORM public.cancel_lead_trial(v_cancel, NULL);
  BEGIN
    PERFORM public.complete_lead_trial(v_cancel, NULL);
  EXCEPTION WHEN OTHERS THEN ok_cancel := true;
  END;
  SELECT (public.schedule_lead_trial(
    v_lead, v_candidate, v_class, NULL,
    now() + interval '10 days', now() + interval '10 days 90 minutes', NULL
  )->>'trial_id')::uuid INTO v_noshow;
  PERFORM public.mark_lead_trial_no_show(v_noshow, NULL);
  BEGIN
    PERFORM public.complete_lead_trial(v_noshow, NULL);
  EXCEPTION WHEN OTHERS THEN ok_noshow := true;
  END;
  PERFORM _m3_tr_record(22, 'cancelled trial cannot be completed', ok_cancel);
  PERFORM _m3_tr_record(23, 'no-show trial cannot be completed', ok_noshow);
  PERFORM _m3_tr_as_super();
END $$;

-- 24: actor identity cannot be spoofed on event insert
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_trial uuid;
  ok boolean := false;
BEGIN
  PERFORM _m3_tr_as_super();
  SELECT id INTO v_trial FROM lead_trial WHERE organization_id = org LIMIT 1;
  PERFORM _m3_tr_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    INSERT INTO lead_trial_event (
      organization_id, lead_trial_id, event_type, changed_by
    ) VALUES (
      org, v_trial, 'scheduled', 'a2000000-0000-4000-8000-000000000001'
    );
  EXCEPTION WHEN OTHERS THEN ok := true;
  END;
  PERFORM _m3_tr_record(24, 'trial event actor spoofing blocked', ok);
  PERFORM _m3_tr_as_super();
END $$;

-- 25: direct protected-field mutation blocked
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_trial uuid;
  ok boolean := false;
BEGIN
  PERFORM _m3_tr_as_super();
  SELECT id INTO v_trial FROM lead_trial WHERE organization_id = org LIMIT 1;
  PERFORM _m3_tr_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    UPDATE lead_trial SET status = 'completed' WHERE id = v_trial;
  EXCEPTION WHEN OTHERS THEN ok := true;
  END;
  PERFORM _m3_tr_record(25, 'direct trial state mutation blocked', ok);
  PERFORM _m3_tr_as_super();
END $$;

-- 26–27: trial history update/delete blocked
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_event uuid;
  v_note_before text;
  v_note_after text;
  v_still_exists boolean;
  ok_upd boolean := false;
  ok_del boolean := false;
BEGIN
  PERFORM _m3_tr_as_super();
  SELECT id, note INTO v_event, v_note_before
  FROM lead_trial_event WHERE organization_id = org LIMIT 1;
  PERFORM _m3_tr_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    UPDATE lead_trial_event SET note = 'tampered' WHERE id = v_event;
    SELECT note INTO v_note_after FROM lead_trial_event WHERE id = v_event;
    ok_upd := v_note_after IS NOT DISTINCT FROM v_note_before;
  EXCEPTION WHEN OTHERS THEN ok_upd := true;
  END;
  BEGIN
    DELETE FROM lead_trial_event WHERE id = v_event;
    SELECT EXISTS (SELECT 1 FROM lead_trial_event WHERE id = v_event) INTO v_still_exists;
    ok_del := v_still_exists;
  EXCEPTION WHEN OTHERS THEN ok_del := true;
  END;
  PERFORM _m3_tr_record(26, 'trial history update blocked', ok_upd);
  PERFORM _m3_tr_record(27, 'trial history delete blocked', ok_del);
  PERFORM _m3_tr_as_super();
END $$;

-- 28: multiple trials per candidate over time
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  v_candidate uuid;
  v_class uuid;
  v_trial1 uuid;
  v_trial2 uuid;
  cnt integer;
BEGIN
  PERFORM _m3_tr_as_super();
  INSERT INTO lead (organization_id, status) VALUES (org, 'qualified') RETURNING id INTO v_lead;
  INSERT INTO lead_candidate (organization_id, lead_id, given_name, family_name, is_primary_candidate)
  VALUES (org, v_lead, 'Multi', 'Trial', true) RETURNING id INTO v_candidate;
  SELECT id INTO v_class FROM class WHERE organization_id = org AND name = 'Class A1' LIMIT 1;
  PERFORM _m3_tr_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT (public.schedule_lead_trial(
    v_lead, v_candidate, v_class, NULL,
    now() + interval '11 days', now() + interval '11 days 90 minutes', NULL
  )->>'trial_id')::uuid INTO v_trial1;
  PERFORM public.cancel_lead_trial(v_trial1, NULL);
  SELECT (public.schedule_lead_trial(
    v_lead, v_candidate, v_class, NULL,
    now() + interval '12 days', now() + interval '12 days 90 minutes', NULL
  )->>'trial_id')::uuid INTO v_trial2;
  SELECT count(*) INTO cnt FROM lead_trial WHERE lead_candidate_id = v_candidate;
  PERFORM _m3_tr_record(28, 'multiple trials per candidate work', cnt = 2 AND v_trial1 <> v_trial2);
  PERFORM _m3_tr_as_super();
END $$;

-- 29: sibling candidates can have independent trials
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  v_c1 uuid;
  v_c2 uuid;
  v_class uuid;
  cnt integer;
BEGIN
  PERFORM _m3_tr_as_super();
  INSERT INTO lead (organization_id, status) VALUES (org, 'qualified') RETURNING id INTO v_lead;
  INSERT INTO lead_candidate (organization_id, lead_id, given_name, family_name, is_primary_candidate)
  VALUES (org, v_lead, 'Sibling', 'One', true) RETURNING id INTO v_c1;
  INSERT INTO lead_candidate (organization_id, lead_id, given_name, family_name, is_primary_candidate)
  VALUES (org, v_lead, 'Sibling', 'Two', false) RETURNING id INTO v_c2;
  SELECT id INTO v_class FROM class WHERE organization_id = org AND name = 'Class A1' LIMIT 1;
  PERFORM _m3_tr_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.schedule_lead_trial(
    v_lead, v_c1, v_class, NULL,
    now() + interval '13 days', now() + interval '13 days 90 minutes', NULL
  );
  PERFORM public.schedule_lead_trial(
    v_lead, v_c2, v_class, NULL,
    now() + interval '14 days', now() + interval '14 days 90 minutes', NULL
  );
  SELECT count(*) INTO cnt FROM lead_trial WHERE lead_id = v_lead AND status = 'scheduled';
  PERFORM _m3_tr_record(29, 'sibling candidates independent trials', cnt = 2);
  PERFORM _m3_tr_as_super();
END $$;

-- 30–31: assignment and follow-up ownership unchanged
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  assignee uuid := 'a1000000-0000-4000-8000-000000000001';
  v_lead uuid;
  v_candidate uuid;
  v_class uuid;
  v_follow_up uuid;
  owner_before uuid;
  owner_after uuid;
  fu_owner uuid;
BEGIN
  PERFORM _m3_tr_as_super();
  INSERT INTO lead (organization_id, status) VALUES (org, 'qualified') RETURNING id INTO v_lead;
  INSERT INTO lead_candidate (organization_id, lead_id, given_name, family_name, is_primary_candidate)
  VALUES (org, v_lead, 'Owner', 'Check', true) RETURNING id INTO v_candidate;
  SELECT id INTO v_class FROM class WHERE organization_id = org AND name = 'Class A1' LIMIT 1;
  PERFORM set_config('olli.lead_assignment_mutation', 'true', true);
  UPDATE lead SET assigned_user_id = assignee WHERE id = v_lead;
  PERFORM set_config('olli.lead_assignment_mutation', 'false', true);
  PERFORM _m3_tr_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT public.create_lead_follow_up(
    v_lead, now() + interval '1 day', 'Follow-up owner check', assignee
  ) INTO v_follow_up;
  SELECT assigned_user_id INTO owner_before FROM lead WHERE id = v_lead;
  PERFORM public.schedule_lead_trial(
    v_lead, v_candidate, v_class, NULL,
    now() + interval '15 days', now() + interval '15 days 90 minutes', NULL
  );
  SELECT assigned_user_id INTO owner_after FROM lead WHERE id = v_lead;
  SELECT assigned_user_id INTO fu_owner FROM lead_follow_up WHERE id = v_follow_up;
  PERFORM _m3_tr_record(30, 'assignment unchanged by trial operations', owner_before = assignee AND owner_after = assignee);
  PERFORM _m3_tr_record(31, 'follow-up ownership unchanged by trial operations', fu_owner = assignee);
  PERFORM _m3_tr_as_super();
END $$;

-- 32–35: no M1/M2 side effects
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  v_candidate uuid;
  v_class uuid;
  students_before integer;
  students_after integer;
  enroll_before integer;
  enroll_after integer;
  attend_before integer;
  attend_after integer;
  charge_before integer;
  charge_after integer;
BEGIN
  PERFORM _m3_tr_as_super();
  SELECT count(*) INTO students_before FROM student WHERE organization_id = org;
  SELECT count(*) INTO enroll_before FROM enrollment WHERE organization_id = org;
  SELECT count(*) INTO attend_before FROM attendance WHERE organization_id = org;
  SELECT count(*) INTO charge_before FROM charge WHERE organization_id = org;
  INSERT INTO lead (organization_id, status) VALUES (org, 'qualified') RETURNING id INTO v_lead;
  INSERT INTO lead_candidate (organization_id, lead_id, given_name, family_name, is_primary_candidate)
  VALUES (org, v_lead, 'Side', 'Effect', true) RETURNING id INTO v_candidate;
  SELECT id INTO v_class FROM class WHERE organization_id = org AND name = 'Class A1' LIMIT 1;
  PERFORM _m3_tr_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.schedule_lead_trial(
    v_lead, v_candidate, v_class, NULL,
    now() + interval '16 days', now() + interval '16 days 90 minutes', NULL
  );
  PERFORM public.complete_lead_trial(
    (SELECT id FROM lead_trial WHERE lead_id = v_lead ORDER BY created_at DESC LIMIT 1),
    'No side effects'
  );
  PERFORM _m3_tr_as_super();
  SELECT count(*) INTO students_after FROM student WHERE organization_id = org;
  SELECT count(*) INTO enroll_after FROM enrollment WHERE organization_id = org;
  SELECT count(*) INTO attend_after FROM attendance WHERE organization_id = org;
  SELECT count(*) INTO charge_after FROM charge WHERE organization_id = org;
  PERFORM _m3_tr_record(32, 'no student created by trial workflow', students_before = students_after);
  PERFORM _m3_tr_record(33, 'no enrollment created by trial workflow', enroll_before = enroll_after);
  PERFORM _m3_tr_record(34, 'no attendance created by trial workflow', attend_before = attend_after);
  PERFORM _m3_tr_record(35, 'no charge side effect from trial workflow', charge_before = charge_after);
END $$;

DO $$
DECLARE
  total integer;
  passed integer;
  failed integer;
  r record;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE result = 'PASS'), count(*) FILTER (WHERE result = 'FAIL')
  INTO total, passed, failed FROM _m3_tr_results;
  IF failed > 0 THEN
    FOR r IN SELECT test_no, test_name FROM _m3_tr_results WHERE result = 'FAIL' ORDER BY test_no LOOP
      RAISE NOTICE 'FAIL test %: %', r.test_no, r.test_name;
    END LOOP;
    RAISE EXCEPTION 'M3 Lead Trial Tests: % / % passed (% failed)', passed, total, failed;
  END IF;
  RAISE NOTICE 'M3 Lead Trial Tests: % / % passed (0 failed)', passed, total;
END $$;

COMMIT;
