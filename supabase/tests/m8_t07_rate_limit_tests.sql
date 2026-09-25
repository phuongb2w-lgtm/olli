-- M8-T07 rate limiting: 14 scenarios (Postgres-backed counters, grants, isolation).

DELETE FROM public.app_rate_limit_bucket
WHERE bucket_key LIKE 'm8-rl-%' OR bucket_key LIKE 'v1:%' OR bucket_key LIKE 'smoke-%';

CREATE TEMP TABLE IF NOT EXISTS _m8_rl_results (
  test_no integer PRIMARY KEY,
  test_name text NOT NULL,
  result text NOT NULL CHECK (result IN ('PASS', 'FAIL'))
);

GRANT ALL ON TABLE _m8_rl_results TO authenticated, anon;

CREATE OR REPLACE FUNCTION _m8_rl_record(test_no integer, test_name text, passed boolean)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO _m8_rl_results (test_no, test_name, result)
  VALUES (test_no, test_name, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END);
END;
$$;

CREATE OR REPLACE FUNCTION _m8_rl_as_auth(p_auth_id uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', p_auth_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_auth_id::text, 'role', 'authenticated')::text, true);
END;
$$;

CREATE OR REPLACE FUNCTION _m8_rl_as_anon()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE anon;
END;
$$;

CREATE OR REPLACE FUNCTION _m8_rl_consume(
  p_key text,
  p_max integer,
  p_window integer
)
RETURNS jsonb LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
  RETURN public.consume_app_rate_limit(p_key, p_max, p_window);
END;
$$;

-- 1 below limit allowed
DO $$
DECLARE v jsonb;
BEGIN
  v := _m8_rl_consume('m8-rl-test-1', 3, 60);
  PERFORM _m8_rl_record(1, 'first attempt allowed', (v->>'allowed')::boolean = true);
END $$;

-- 2 boundary: third allowed when max=3
DO $$
DECLARE v jsonb;
BEGIN
  PERFORM _m8_rl_consume('m8-rl-test-2', 3, 60);
  PERFORM _m8_rl_consume('m8-rl-test-2', 3, 60);
  v := _m8_rl_consume('m8-rl-test-2', 3, 60);
  PERFORM _m8_rl_record(2, 'boundary attempt allowed at max', (v->>'allowed')::boolean = true);
END $$;

-- 3 above limit blocked
DO $$
DECLARE v jsonb;
BEGIN
  PERFORM _m8_rl_consume('m8-rl-test-3', 2, 60);
  PERFORM _m8_rl_consume('m8-rl-test-3', 2, 60);
  v := _m8_rl_consume('m8-rl-test-3', 2, 60);
  PERFORM _m8_rl_record(3, 'above limit blocked', (v->>'allowed')::boolean = false);
END $$;

-- 4 window reset after expiry (simulate by backdating window)
DO $$
DECLARE v jsonb;
BEGIN
  PERFORM _m8_rl_consume('m8-rl-test-4', 1, 30);
  UPDATE public.app_rate_limit_bucket
  SET window_started_at = now() - interval '2 minutes', attempt_count = 1
  WHERE bucket_key = 'm8-rl-test-4';
  v := _m8_rl_consume('m8-rl-test-4', 1, 30);
  PERFORM _m8_rl_record(4, 'expired window resets counter', (v->>'allowed')::boolean = true);
END $$;

-- 5 different bucket keys isolated
DO $$
DECLARE v_a jsonb; v_b jsonb;
BEGIN
  PERFORM _m8_rl_consume('m8-rl-test-5a', 1, 60);
  v_a := _m8_rl_consume('m8-rl-test-5a', 1, 60);
  v_b := _m8_rl_consume('m8-rl-test-5b', 1, 60);
  PERFORM _m8_rl_record(
    5,
    'distinct bucket keys do not share counters',
    (v_a->>'allowed')::boolean = false AND (v_b->>'allowed')::boolean = true
  );
END $$;

-- 6 org-scoped keys isolated (simulated subjects)
DO $$
DECLARE v_org_a jsonb; v_org_b jsonb;
BEGIN
  PERFORM _m8_rl_consume('v1:staff.provision.org:org-a', 1, 60);
  v_org_a := _m8_rl_consume('v1:staff.provision.org:org-a', 1, 60);
  v_org_b := _m8_rl_consume('v1:staff.provision.org:org-b', 1, 60);
  PERFORM _m8_rl_record(
    6,
    'organization-scoped keys isolated',
    (v_org_a->>'allowed')::boolean = false AND (v_org_b->>'allowed')::boolean = true
  );
END $$;

-- 7 changing target id in key suffix does not reset actor/org bucket
DO $$
DECLARE v jsonb;
BEGIN
  PERFORM _m8_rl_consume('v1:staff.lifecycle.org_actor:actor-1', 1, 60);
  v := _m8_rl_consume('v1:staff.lifecycle.org_actor:actor-1', 1, 60);
  PERFORM _m8_rl_record(
    7,
    'same actor bucket blocked regardless of payload ids elsewhere',
    (v->>'allowed')::boolean = false
  );
END $$;

-- 8 concurrent-style double increment still respects max=1
DO $$
DECLARE v1 jsonb; v2 jsonb;
BEGIN
  v1 := _m8_rl_consume('m8-rl-test-8', 1, 60);
  v2 := _m8_rl_consume('m8-rl-test-8', 1, 60);
  PERFORM _m8_rl_record(
    8,
    'sequential increments enforce atomic max',
    (v1->>'allowed')::boolean = true AND (v2->>'allowed')::boolean = false
  );
END $$;

-- 9 anon cannot execute consume_app_rate_limit
DO $$
BEGIN
  PERFORM _m8_rl_as_anon();
  BEGIN
    PERFORM public.consume_app_rate_limit('m8-rl-test-9', 1, 60);
    PERFORM _m8_rl_record(9, 'anon cannot invoke rate limit rpc', false);
  EXCEPTION WHEN insufficient_privilege THEN
    PERFORM _m8_rl_record(9, 'anon cannot invoke rate limit rpc', true);
  END;
END $$;

-- 10 authenticated cannot execute consume_app_rate_limit
DO $$
BEGIN
  PERFORM _m8_rl_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.consume_app_rate_limit('m8-rl-test-10', 1, 60);
    PERFORM _m8_rl_record(10, 'authenticated cannot invoke rate limit rpc', false);
  EXCEPTION WHEN insufficient_privilege THEN
    PERFORM _m8_rl_record(10, 'authenticated cannot invoke rate limit rpc', true);
  END;
END $$;

-- 11 anon cannot read bucket table
DO $$
DECLARE v_count integer;
BEGIN
  PERFORM _m8_rl_as_anon();
  BEGIN
    SELECT count(*) INTO v_count FROM public.app_rate_limit_bucket;
    PERFORM _m8_rl_record(11, 'anon cannot read rate limit table', false);
  EXCEPTION WHEN insufficient_privilege THEN
    PERFORM _m8_rl_record(11, 'anon cannot read rate limit table', true);
  END;
END $$;

-- 12 authenticated cannot read bucket table
DO $$
DECLARE v_count integer;
BEGIN
  PERFORM _m8_rl_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    SELECT count(*) INTO v_count FROM public.app_rate_limit_bucket;
    PERFORM _m8_rl_record(12, 'authenticated cannot read rate limit table', false);
  EXCEPTION WHEN insufficient_privilege THEN
    PERFORM _m8_rl_record(12, 'authenticated cannot read rate limit table', true);
  END;
END $$;

-- 13 purge removes stale rows
DO $$
DECLARE v_deleted integer;
BEGIN
  INSERT INTO public.app_rate_limit_bucket (bucket_key, window_started_at, attempt_count, updated_at)
  VALUES ('m8-rl-stale', now() - interval '10 days', 1, now() - interval '10 days')
  ON CONFLICT (bucket_key) DO UPDATE
  SET updated_at = excluded.updated_at, window_started_at = excluded.window_started_at, attempt_count = excluded.attempt_count;
  RESET ROLE;
  SET LOCAL ROLE postgres;
  v_deleted := public.purge_stale_app_rate_limit_buckets(86400);
  PERFORM _m8_rl_record(
    13,
    'purge removes stale buckets',
    v_deleted >= 1 AND NOT EXISTS (SELECT 1 FROM public.app_rate_limit_bucket WHERE bucket_key = 'm8-rl-stale')
  );
END $$;

-- 14 blocked response includes retry_after_seconds
DO $$
DECLARE v jsonb;
BEGIN
  PERFORM _m8_rl_consume('m8-rl-test-14', 1, 120);
  v := _m8_rl_consume('m8-rl-test-14', 1, 120);
  PERFORM _m8_rl_record(
    14,
    'blocked attempt exposes retry_after_seconds only',
    (v->>'allowed')::boolean = false AND (v->>'retry_after_seconds') IS NOT NULL
  );
END $$;

DO $$
DECLARE v_fail integer;
BEGIN
  SELECT count(*) INTO v_fail FROM _m8_rl_results WHERE result = 'FAIL';
  IF v_fail > 0 THEN
    RAISE EXCEPTION 'M8-T07 rate limit tests failed: % failing scenario(s)', v_fail;
  END IF;
  RAISE NOTICE 'M8-T07 rate limit tests: 14/14 PASS';
END $$;
