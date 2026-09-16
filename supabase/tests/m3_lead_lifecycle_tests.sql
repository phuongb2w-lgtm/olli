-- M3-T03: Lead lifecycle, activity, follow-up integrity and security tests.

BEGIN;

CREATE TEMP TABLE _m3_lc_results (
  test_no   integer PRIMARY KEY,
  test_name text NOT NULL,
  result    text NOT NULL CHECK (result IN ('PASS', 'FAIL'))
);

GRANT ALL ON TABLE _m3_lc_results TO authenticated, anon;

CREATE OR REPLACE FUNCTION _m3_lc_record(test_no integer, test_name text, passed boolean)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO _m3_lc_results (test_no, test_name, result)
  VALUES (test_no, test_name, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END);
END;
$$;

CREATE OR REPLACE FUNCTION _m3_lc_expect_fail(test_no integer, test_name text, sql_text text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE sql_text;
    PERFORM _m3_lc_record(test_no, test_name, false);
  EXCEPTION WHEN OTHERS THEN
    PERFORM _m3_lc_record(test_no, test_name, true);
  END;
END;
$$;

CREATE OR REPLACE FUNCTION _m3_lc_as_auth(p_auth_id uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', p_auth_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_auth_id::text, 'role', 'authenticated')::text, true);
END;
$$;

CREATE OR REPLACE FUNCTION _m3_lc_as_super()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
END;
$$;

-- 1: lifecycle history table exists
DO $$
DECLARE cnt integer;
BEGIN
  SELECT count(*) INTO cnt FROM information_schema.tables
  WHERE table_schema = 'public' AND table_name = 'lead_status_history';
  PERFORM _m3_lc_record(1, 'lead_status_history exists', cnt = 1);
END $$;

-- 2: activity table exists
DO $$
DECLARE cnt integer;
BEGIN
  SELECT count(*) INTO cnt FROM information_schema.tables
  WHERE table_schema = 'public' AND table_name = 'lead_activity';
  PERFORM _m3_lc_record(2, 'lead_activity exists', cnt = 1);
END $$;

-- 3: follow-up table exists
DO $$
DECLARE cnt integer;
BEGIN
  SELECT count(*) INTO cnt FROM information_schema.tables
  WHERE table_schema = 'public' AND table_name = 'lead_follow_up';
  PERFORM _m3_lc_record(3, 'lead_follow_up exists', cnt = 1);
END $$;

-- 4: FORCE RLS on new tables
DO $$
DECLARE cnt integer;
BEGIN
  SELECT count(*) INTO cnt FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public'
    AND c.relname IN ('lead_status_history', 'lead_activity', 'lead_follow_up')
    AND c.relrowsecurity AND c.relforcerowsecurity;
  PERFORM _m3_lc_record(4, 'FORCE RLS on lifecycle tables', cnt = 3);
END $$;

-- 5: valid lifecycle transition succeeds
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  v_status text;
BEGIN
  PERFORM _m3_lc_as_super();
  INSERT INTO lead (organization_id, status) VALUES (org, 'new') RETURNING id INTO v_lead;
  PERFORM _m3_lc_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.transition_lead_status(v_lead, 'contacted', NULL, 'Reached by phone');
  SELECT status INTO v_status FROM lead WHERE id = v_lead;
  PERFORM _m3_lc_record(5, 'valid lifecycle transition succeeds', v_status = 'contacted');
  PERFORM _m3_lc_as_super();
END $$;

-- 6: invalid lifecycle transition fails
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
BEGIN
  PERFORM _m3_lc_as_super();
  INSERT INTO lead (organization_id, status) VALUES (org, 'new') RETURNING id INTO v_lead;
  PERFORM _m3_lc_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM _m3_lc_expect_fail(
    6,
    'invalid lifecycle transition fails',
    format($sql$SELECT public.transition_lead_status(%L, 'trial_completed', NULL, NULL)$sql$, v_lead)
  );
  PERFORM _m3_lc_as_super();
END $$;

-- 7: lost transition without reason fails
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
BEGIN
  PERFORM _m3_lc_as_super();
  INSERT INTO lead (organization_id, status) VALUES (org, 'contacted') RETURNING id INTO v_lead;
  PERFORM _m3_lc_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM _m3_lc_expect_fail(
    7,
    'lost transition without reason fails',
    format($sql$SELECT public.transition_lead_status(%L, 'lost', NULL, NULL)$sql$, v_lead)
  );
  PERFORM _m3_lc_as_super();
END $$;

-- 8: lost transition with other-org reason fails
DO $$
DECLARE
  org_a uuid := 'a0000000-0000-4000-8000-000000000001';
  reason_b uuid;
  v_lead uuid;
BEGIN
  PERFORM _m3_lc_as_super();
  SELECT id INTO reason_b FROM lead_lost_reason WHERE organization_id = 'b0000000-0000-4000-8000-000000000001' LIMIT 1;
  INSERT INTO lead (organization_id, status) VALUES (org_a, 'contacted') RETURNING id INTO v_lead;
  PERFORM _m3_lc_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM _m3_lc_expect_fail(
    8,
    'lost transition with other-org reason fails',
    format($sql$SELECT public.transition_lead_status(%L, 'lost', %L, NULL)$sql$, v_lead, reason_b)
  );
  PERFORM _m3_lc_as_super();
END $$;

-- 9: lost transition with valid reason succeeds
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  reason uuid;
  v_lead uuid;
  v_status text;
BEGIN
  PERFORM _m3_lc_as_super();
  SELECT id INTO reason FROM lead_lost_reason WHERE organization_id = org AND code = 'no_response' LIMIT 1;
  INSERT INTO lead (organization_id, status) VALUES (org, 'qualified') RETURNING id INTO v_lead;
  PERFORM _m3_lc_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.transition_lead_status(v_lead, 'lost', reason, 'No callback');
  SELECT status INTO v_status FROM lead WHERE id = v_lead;
  PERFORM _m3_lc_record(9, 'lost transition with valid reason succeeds', v_status = 'lost');
  PERFORM _m3_lc_as_super();
END $$;

-- 10: lifecycle history appended atomically
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  hist_cnt integer;
BEGIN
  PERFORM _m3_lc_as_super();
  INSERT INTO lead (organization_id, status) VALUES (org, 'new') RETURNING id INTO v_lead;
  PERFORM _m3_lc_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.transition_lead_status(v_lead, 'contacted', NULL, NULL);
  SELECT count(*) INTO hist_cnt FROM lead_status_history WHERE lead_id = v_lead;
  PERFORM _m3_lc_record(10, 'lifecycle history appended', hist_cnt >= 1);
  PERFORM _m3_lc_as_super();
END $$;

-- 11: reactivation preserves lost history
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  reason uuid;
  v_lead uuid;
  lost_hist integer;
  v_status text;
  preserved_reason uuid;
BEGIN
  PERFORM _m3_lc_as_super();
  SELECT id INTO reason FROM lead_lost_reason WHERE organization_id = org LIMIT 1;
  INSERT INTO lead (organization_id, status) VALUES (org, 'qualified') RETURNING id INTO v_lead;
  PERFORM _m3_lc_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.transition_lead_status(v_lead, 'lost', reason, 'Lost once');
  PERFORM public.transition_lead_status(v_lead, 'contacted', NULL, 'Reactivated');
  SELECT count(*) INTO lost_hist FROM lead_status_history WHERE lead_id = v_lead AND to_status = 'lost';
  SELECT status, lost_reason_id INTO v_status, preserved_reason FROM lead WHERE id = v_lead;
  PERFORM _m3_lc_record(
    11,
    'reactivation preserves lost history',
    lost_hist = 1 AND v_status = 'contacted' AND preserved_reason = reason
  );
  PERFORM _m3_lc_as_super();
END $$;

-- 12: generic transition cannot set converted
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
BEGIN
  PERFORM _m3_lc_as_super();
  INSERT INTO lead (organization_id, status) VALUES (org, 'qualified') RETURNING id INTO v_lead;
  PERFORM _m3_lc_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM _m3_lc_expect_fail(
    12,
    'generic transition cannot set converted',
    format($sql$SELECT public.transition_lead_status(%L, 'converted', NULL, NULL)$sql$, v_lead)
  );
  PERFORM _m3_lc_as_super();
END $$;

-- 13: direct status bypass blocked
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
BEGIN
  PERFORM _m3_lc_as_super();
  INSERT INTO lead (organization_id, status) VALUES (org, 'new') RETURNING id INTO v_lead;
  PERFORM _m3_lc_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM _m3_lc_expect_fail(
    13,
    'direct status bypass blocked',
    format($sql$UPDATE lead SET status = 'contacted' WHERE id = %L$sql$, v_lead)
  );
  PERFORM _m3_lc_as_super();
END $$;

-- 14: add activity works
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  v_act uuid;
  cnt integer;
BEGIN
  PERFORM _m3_lc_as_super();
  INSERT INTO lead (organization_id, status) VALUES (org, 'new') RETURNING id INTO v_lead;
  PERFORM _m3_lc_as_auth('a1111111-1111-4111-8111-111111111111');
  v_act := public.add_lead_activity(v_lead, 'call', now(), 'Called parent', '{}'::jsonb);
  SELECT count(*) INTO cnt FROM lead_activity WHERE id = v_act;
  PERFORM _m3_lc_record(14, 'add activity works', cnt = 1);
  PERFORM _m3_lc_as_super();
END $$;

-- 15: activity append-only (no update policy)
DO $$
DECLARE pol integer;
BEGIN
  SELECT count(*) INTO pol FROM pg_policies
  WHERE schemaname = 'public' AND tablename = 'lead_activity' AND cmd = 'UPDATE';
  PERFORM _m3_lc_record(15, 'activity has no update policy', pol = 0);
END $$;

-- 16: follow-up creation works
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  v_fu uuid;
BEGIN
  PERFORM _m3_lc_as_super();
  INSERT INTO lead (organization_id, status) VALUES (org, 'new') RETURNING id INTO v_lead;
  PERFORM _m3_lc_as_auth('a1111111-1111-4111-8111-111111111111');
  v_fu := public.create_lead_follow_up(v_lead, now() + interval '1 day', 'Call back', NULL);
  PERFORM _m3_lc_record(16, 'follow-up creation works', v_fu IS NOT NULL);
  PERFORM _m3_lc_as_super();
END $$;

-- 17: follow-up completion works
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  v_fu uuid;
  v_status text;
BEGIN
  PERFORM _m3_lc_as_super();
  INSERT INTO lead (organization_id, status) VALUES (org, 'new') RETURNING id INTO v_lead;
  PERFORM _m3_lc_as_auth('a1111111-1111-4111-8111-111111111111');
  v_fu := public.create_lead_follow_up(v_lead, now() + interval '2 day', 'Reminder', NULL);
  PERFORM public.complete_lead_follow_up(v_fu, 'Done');
  SELECT status INTO v_status FROM lead_follow_up WHERE id = v_fu;
  PERFORM _m3_lc_record(17, 'follow-up completion works', v_status = 'completed');
  PERFORM _m3_lc_as_super();
END $$;

-- 18: cross-org responsible user rejected
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  user_b uuid := 'b1000000-0000-4000-8000-000000000001';
  v_lead uuid;
BEGIN
  PERFORM _m3_lc_as_super();
  INSERT INTO lead (organization_id, status) VALUES (org, 'new') RETURNING id INTO v_lead;
  PERFORM _m3_lc_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM _m3_lc_expect_fail(
    18,
    'cross-org responsible user rejected',
    format(
      $sql$SELECT public.create_lead_follow_up(%L, now() + interval '1 day', 'x', %L)$sql$,
      v_lead,
      user_b
    )
  );
  PERFORM _m3_lc_as_super();
END $$;

-- 19: cross-org activity access blocked
DO $$
DECLARE
  org_b uuid := 'b0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  cnt integer;
BEGIN
  PERFORM _m3_lc_as_super();
  INSERT INTO lead (organization_id, status) VALUES (org_b, 'new') RETURNING id INTO v_lead;
  INSERT INTO lead_activity (organization_id, lead_id, activity_type_code, occurred_at, content, created_by)
  SELECT org_b, v_lead, 'note', now(), 'secret', id FROM app_user WHERE email = 'org-b-admin@olli.local';
  PERFORM _m3_lc_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO cnt FROM lead_activity WHERE lead_id = v_lead;
  PERFORM _m3_lc_record(19, 'cross-org activity access blocked', cnt = 0);
  PERFORM _m3_lc_as_super();
END $$;

-- 20: cross-org follow-up access blocked
DO $$
DECLARE
  org_b uuid := 'b0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  cnt integer;
BEGIN
  PERFORM _m3_lc_as_super();
  INSERT INTO lead (organization_id, status) VALUES (org_b, 'new') RETURNING id INTO v_lead;
  INSERT INTO lead_follow_up (organization_id, lead_id, due_at, note, status, created_by)
  SELECT org_b, v_lead, now() + interval '1 day', 'org b', 'pending', id
  FROM app_user WHERE email = 'org-b-admin@olli.local';
  PERFORM _m3_lc_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO cnt FROM lead_follow_up WHERE lead_id = v_lead;
  PERFORM _m3_lc_record(20, 'cross-org follow-up access blocked', cnt = 0);
  PERFORM _m3_lc_as_super();
END $$;

-- 21: cross-org status history access blocked
DO $$
DECLARE
  org_b uuid := 'b0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  cnt integer;
BEGIN
  PERFORM _m3_lc_as_super();
  INSERT INTO lead (organization_id, status) VALUES (org_b, 'new') RETURNING id INTO v_lead;
  INSERT INTO lead_status_history (organization_id, lead_id, from_status, to_status, changed_by)
  SELECT org_b, v_lead, 'new', 'contacted', id FROM app_user WHERE email = 'org-b-admin@olli.local';
  PERFORM _m3_lc_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO cnt FROM lead_status_history WHERE lead_id = v_lead;
  PERFORM _m3_lc_record(21, 'cross-org status history access blocked', cnt = 0);
  PERFORM _m3_lc_as_super();
END $$;

-- 22: lifecycle transition has no M1 side effects
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  before_s integer;
  after_s integer;
BEGIN
  PERFORM _m3_lc_as_super();
  SELECT count(*) INTO before_s FROM student WHERE organization_id = org;
  INSERT INTO lead (organization_id, status) VALUES (org, 'new') RETURNING id INTO v_lead;
  PERFORM _m3_lc_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.transition_lead_status(v_lead, 'contacted', NULL, NULL);
  PERFORM _m3_lc_as_super();
  SELECT count(*) INTO after_s FROM student WHERE organization_id = org;
  PERFORM _m3_lc_record(22, 'lifecycle transition no M1 side effects', before_s = after_s);
END $$;

-- 23: activity has no M2 side effects
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  before_c integer;
  after_c integer;
BEGIN
  PERFORM _m3_lc_as_super();
  SELECT count(*) INTO before_c FROM charge WHERE organization_id = org;
  INSERT INTO lead (organization_id, status) VALUES (org, 'new') RETURNING id INTO v_lead;
  PERFORM _m3_lc_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.add_lead_activity(v_lead, 'note', now(), 'test', '{}'::jsonb);
  PERFORM _m3_lc_as_super();
  SELECT count(*) INTO after_c FROM charge WHERE organization_id = org;
  PERFORM _m3_lc_record(23, 'activity no M2 side effects', before_c = after_c);
END $$;

-- 24: actor identity cannot be spoofed on activity insert
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  spoof uuid := 'a5000000-0000-4000-8000-000000000001';
BEGIN
  PERFORM _m3_lc_as_super();
  INSERT INTO lead (organization_id, status) VALUES (org, 'new') RETURNING id INTO v_lead;
  PERFORM _m3_lc_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM _m3_lc_expect_fail(
    24,
    'activity actor spoof blocked by RLS',
    format(
      $sql$INSERT INTO lead_activity (organization_id, lead_id, activity_type_code, occurred_at, created_by)
         VALUES (%L, %L, 'note', now(), %L)$sql$,
      org,
      v_lead,
      spoof
    )
  );
  PERFORM _m3_lc_as_super();
END $$;

-- 25: skip-stage transition new to qualified allowed
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  v_status text;
BEGIN
  PERFORM _m3_lc_as_super();
  INSERT INTO lead (organization_id, status) VALUES (org, 'new') RETURNING id INTO v_lead;
  PERFORM _m3_lc_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.transition_lead_status(v_lead, 'qualified', NULL, NULL);
  SELECT status INTO v_status FROM lead WHERE id = v_lead;
  PERFORM _m3_lc_record(25, 'skip-stage new to qualified allowed', v_status = 'qualified');
  PERFORM _m3_lc_as_super();
END $$;

DO $$
DECLARE total integer; passed integer; failed integer;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE result = 'PASS'), count(*) FILTER (WHERE result = 'FAIL')
  INTO total, passed, failed FROM _m3_lc_results;
  IF failed > 0 THEN
    RAISE EXCEPTION 'M3 Lead Lifecycle Tests: % / % passed (% failed)', passed, total, failed;
  END IF;
  RAISE NOTICE 'M3 Lead Lifecycle Tests: % / % passed (0 failed)', passed, total;
END $$;

COMMIT;
