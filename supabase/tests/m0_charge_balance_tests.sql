-- M0-T05: charge_balance view security verification (separate from 30-scenario suite).

CREATE TEMP TABLE IF NOT EXISTS _cb_results (
  test_no integer PRIMARY KEY,
  test_name text NOT NULL,
  result text NOT NULL CHECK (result IN ('PASS', 'FAIL'))
);

GRANT ALL ON TABLE _cb_results TO authenticated, anon;

CREATE OR REPLACE FUNCTION _cb_record(test_no integer, test_name text, passed boolean)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO _cb_results (test_no, test_name, result)
  VALUES (test_no, test_name, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END);
END;
$$;

CREATE OR REPLACE FUNCTION _cb_as_auth(p_auth_id uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', p_auth_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_auth_id::text, 'role', 'authenticated')::text, true);
END;
$$;

CREATE OR REPLACE FUNCTION _cb_as_anon()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE anon;
  PERFORM set_config('request.jwt.claim.sub', '', true);
END;
$$;

CREATE OR REPLACE FUNCTION _cb_as_super()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
END;
$$;

-- 1 security_invoker enabled
DO $$
DECLARE v_invoker boolean;
BEGIN
  SELECT COALESCE(
    (SELECT option_value = 'true'
     FROM pg_options_to_table(
       (SELECT reloptions FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' AND c.relname = 'charge_balance')
     )
     WHERE option_name = 'security_invoker'),
    false
  ) INTO v_invoker;
  PERFORM _cb_record(1, 'charge_balance security_invoker true', v_invoker);
END $$;

-- 2 anon cannot read charge_balance
DO $$
BEGIN
  PERFORM _cb_as_anon();
  BEGIN
    PERFORM 1 FROM charge_balance LIMIT 1;
    PERFORM _cb_record(2, 'anon cannot read charge_balance', false);
  EXCEPTION WHEN insufficient_privilege THEN
    PERFORM _cb_record(2, 'anon cannot read charge_balance', true);
  END;
END $$;

-- 3 org A admin reads own org balances only
DO $$
DECLARE v_total integer; v_cross integer;
BEGIN
  PERFORM _cb_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_total FROM charge_balance;
  SELECT count(*) INTO v_cross FROM charge_balance
  WHERE organization_id = 'b0000000-0000-4000-8000-000000000001';
  PERFORM _cb_record(3, 'org A reads own charge_balance rows', v_total >= 1 AND v_cross = 0);
END $$;

-- 4 org A cannot read org B charge_balance
DO $$
DECLARE v_cross integer;
BEGIN
  PERFORM _cb_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO v_cross FROM charge_balance
  WHERE organization_id = 'b0000000-0000-4000-8000-000000000001';
  PERFORM _cb_record(4, 'org A cannot read org B charge_balance', v_cross = 0);
END $$;

-- 5 staff without charge.read sees no balances
DO $$
DECLARE v_count integer; v_role uuid; v_perm uuid;
BEGIN
  PERFORM _cb_as_super();
  SELECT id INTO v_role FROM role WHERE organization_id = 'a0000000-0000-4000-8000-000000000001' AND code = 'fixture_readonly';
  SELECT id INTO v_perm FROM permission WHERE code = 'charge.read';
  DELETE FROM role_permission WHERE role_id = v_role AND permission_id = v_perm;
  PERFORM _cb_as_auth('a2222222-2222-4222-8222-222222222222');
  SELECT count(*) INTO v_count FROM charge_balance;
  PERFORM _cb_record(5, 'no charge.read sees no charge_balance', v_count = 0);
  PERFORM _cb_as_super();
  INSERT INTO role_permission (role_id, permission_id) VALUES (v_role, v_perm)
  ON CONFLICT DO NOTHING;
END $$;

DO $$
DECLARE total integer; passed integer; failed integer;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE result = 'PASS'), count(*) FILTER (WHERE result = 'FAIL')
  INTO total, passed, failed FROM _cb_results;
  RAISE NOTICE 'M0 charge_balance Tests: % / % passed (% failed)', passed, total, failed;
  IF failed > 0 OR total <> 5 THEN
    RAISE EXCEPTION 'charge_balance tests failed: % of % (expected 5)', failed, total;
  END IF;
END $$;

SELECT test_no, test_name, result FROM _cb_results ORDER BY test_no;
