-- M8-T07: Durable application rate-limit counters (server-side enforcement only).

CREATE TABLE public.app_rate_limit_bucket (
  bucket_key text PRIMARY KEY,
  window_started_at timestamptz NOT NULL,
  attempt_count integer NOT NULL CHECK (attempt_count >= 0),
  updated_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.app_rate_limit_bucket IS
  'Fixed-window attempt counters for Olli application rate limits. Mutated only via consume_app_rate_limit (service_role).';

CREATE INDEX app_rate_limit_bucket_updated_at_idx
  ON public.app_rate_limit_bucket (updated_at);

ALTER TABLE public.app_rate_limit_bucket ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.app_rate_limit_bucket FROM PUBLIC;
REVOKE ALL ON TABLE public.app_rate_limit_bucket FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.consume_app_rate_limit(
  p_bucket_key text,
  p_max_attempts integer,
  p_window_seconds integer
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_now timestamptz := clock_timestamp();
  v_window_start timestamptz;
  v_count integer;
  v_allowed boolean;
  v_retry_after integer;
  v_window_end timestamptz;
BEGIN
  IF p_bucket_key IS NULL OR length(trim(p_bucket_key)) = 0 THEN
    RAISE EXCEPTION 'invalid_rate_limit_bucket_key';
  END IF;
  IF p_max_attempts IS NULL OR p_max_attempts < 1 THEN
    RAISE EXCEPTION 'invalid_rate_limit_max_attempts';
  END IF;
  IF p_window_seconds IS NULL OR p_window_seconds < 1 THEN
    RAISE EXCEPTION 'invalid_rate_limit_window_seconds';
  END IF;

  INSERT INTO public.app_rate_limit_bucket AS b (
    bucket_key,
    window_started_at,
    attempt_count,
    updated_at
  )
  VALUES (p_bucket_key, v_now, 1, v_now)
  ON CONFLICT (bucket_key) DO UPDATE
  SET
    attempt_count = CASE
      WHEN b.window_started_at + make_interval(secs => p_window_seconds) <= v_now THEN 1
      ELSE b.attempt_count + 1
    END,
    window_started_at = CASE
      WHEN b.window_started_at + make_interval(secs => p_window_seconds) <= v_now THEN v_now
      ELSE b.window_started_at
    END,
    updated_at = v_now
  RETURNING b.window_started_at, b.attempt_count
  INTO v_window_start, v_count;

  v_allowed := v_count <= p_max_attempts;
  v_window_end := v_window_start + make_interval(secs => p_window_seconds);
  IF NOT v_allowed THEN
    v_retry_after := GREATEST(
      1,
      ceil(extract(epoch FROM (v_window_end - v_now)))::integer
    );
  END IF;

  RETURN jsonb_build_object(
    'allowed', v_allowed,
    'retry_after_seconds', CASE WHEN v_allowed THEN NULL ELSE v_retry_after END
  );
END;
$$;

COMMENT ON FUNCTION public.consume_app_rate_limit(text, integer, integer) IS
  'Atomically increments a fixed-window counter and returns whether the attempt is allowed. Callable only with service_role.';

REVOKE ALL ON FUNCTION public.consume_app_rate_limit(text, integer, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.consume_app_rate_limit(text, integer, integer) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.consume_app_rate_limit(text, integer, integer) TO service_role;

CREATE OR REPLACE FUNCTION public.purge_stale_app_rate_limit_buckets(
  p_retention_seconds integer DEFAULT 604800
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_deleted integer;
BEGIN
  IF p_retention_seconds IS NULL OR p_retention_seconds < 3600 THEN
    RAISE EXCEPTION 'invalid_rate_limit_retention_seconds';
  END IF;

  DELETE FROM public.app_rate_limit_bucket
  WHERE updated_at < now() - make_interval(secs => p_retention_seconds);

  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN v_deleted;
END;
$$;

REVOKE ALL ON FUNCTION public.purge_stale_app_rate_limit_buckets(integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.purge_stale_app_rate_limit_buckets(integer) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.purge_stale_app_rate_limit_buckets(integer) TO service_role;
