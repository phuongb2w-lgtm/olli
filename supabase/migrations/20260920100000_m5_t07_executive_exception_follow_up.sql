-- M5-T07: Executive cross-domain exceptions worklist + auditable management follow-up.
-- Composes canonical T02–T05 exception RPCs; follow-up is management metadata only.

INSERT INTO permission (code) VALUES
  ('report.executive.follow_up.manage')
ON CONFLICT (code) DO NOTHING;

COMMENT ON TABLE permission IS
  'Permission codes. report.executive.follow_up.manage gates management follow-up on executive exceptions (separate from read).';

-- =============================================================================
-- EXCEPTION IDENTITY (stable across reporting reads; period is not part of key)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.build_executive_exception_key(
  p_domain text,
  p_exception_code text,
  p_entity_type text,
  p_entity_id text
)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT lower(trim(p_domain)) || '|' || trim(p_exception_code) || '|' || trim(p_entity_type) || '|' || trim(p_entity_id);
$$;

COMMENT ON FUNCTION public.build_executive_exception_key(text, text, text, text) IS
  'Deterministic executive exception identity within an organization: domain|exception_code|entity_type|entity_id. Organization id is stored separately. Reporting period is excluded because conditions attach to canonical source entities, not calendar slices.';

-- =============================================================================
-- MANAGEMENT FOLLOW-UP (not domain business truth)
-- =============================================================================

CREATE TYPE executive_exception_follow_up_status AS ENUM (
  'open',
  'acknowledged',
  'resolved',
  'dismissed'
);

CREATE TABLE executive_exception_follow_up (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id     uuid NOT NULL REFERENCES organization (id),
  exception_key       text NOT NULL CHECK (length(trim(exception_key)) > 0),
  domain              text NOT NULL CHECK (domain IN ('finance', 'admissions', 'quality', 'operations')),
  exception_code      text NOT NULL CHECK (length(trim(exception_code)) > 0),
  entity_type         text NOT NULL CHECK (length(trim(entity_type)) > 0),
  entity_id           text NOT NULL CHECK (length(trim(entity_id)) > 0),
  status              executive_exception_follow_up_status NOT NULL DEFAULT 'open',
  latest_note         text,
  created_by          uuid NOT NULL,
  updated_by          uuid NOT NULL,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, exception_key),
  CONSTRAINT executive_exception_follow_up_org_created_by_fk
    FOREIGN KEY (organization_id, created_by) REFERENCES app_user (organization_id, id),
  CONSTRAINT executive_exception_follow_up_org_updated_by_fk
    FOREIGN KEY (organization_id, updated_by) REFERENCES app_user (organization_id, id)
);

CREATE INDEX idx_executive_exception_follow_up_org_status
  ON executive_exception_follow_up (organization_id, status);

COMMENT ON TABLE executive_exception_follow_up IS
  'Current management follow-up disposition for a logical executive exception. Does not mutate canonical domain records.';

CREATE TABLE executive_exception_follow_up_event (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organization (id),
  follow_up_id    uuid NOT NULL REFERENCES executive_exception_follow_up (id) ON DELETE RESTRICT,
  exception_key   text NOT NULL,
  event_type      text NOT NULL CHECK (
    event_type IN ('created', 'status_changed', 'note_added')
  ),
  previous_status executive_exception_follow_up_status,
  new_status      executive_exception_follow_up_status,
  note            text,
  actor_id        uuid NOT NULL,
  created_at      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT executive_exception_follow_up_event_org_actor_fk
    FOREIGN KEY (organization_id, actor_id) REFERENCES app_user (organization_id, id)
);

CREATE INDEX idx_executive_exception_follow_up_event_key
  ON executive_exception_follow_up_event (organization_id, exception_key, created_at DESC);

COMMENT ON TABLE executive_exception_follow_up_event IS
  'Append-only audit trail for executive exception management follow-up changes.';

ALTER TABLE executive_exception_follow_up ENABLE ROW LEVEL SECURITY;
ALTER TABLE executive_exception_follow_up FORCE ROW LEVEL SECURITY;
ALTER TABLE executive_exception_follow_up_event ENABLE ROW LEVEL SECURITY;
ALTER TABLE executive_exception_follow_up_event FORCE ROW LEVEL SECURITY;

CREATE POLICY executive_exception_follow_up_select ON executive_exception_follow_up
  FOR SELECT TO authenticated
  USING (
    organization_id = public.current_organization_id()
    AND public.has_permission('report.executive.read')
  );

CREATE POLICY executive_exception_follow_up_event_select ON executive_exception_follow_up_event
  FOR SELECT TO authenticated
  USING (
    organization_id = public.current_organization_id()
    AND public.has_permission('report.executive.read')
  );

CREATE POLICY executive_exception_follow_up_insert ON executive_exception_follow_up
  FOR INSERT TO authenticated
  WITH CHECK (
    organization_id = public.current_organization_id()
    AND public.has_permission('report.executive.follow_up.manage')
  );

CREATE POLICY executive_exception_follow_up_update ON executive_exception_follow_up
  FOR UPDATE TO authenticated
  USING (
    organization_id = public.current_organization_id()
    AND public.has_permission('report.executive.follow_up.manage')
  )
  WITH CHECK (
    organization_id = public.current_organization_id()
    AND public.has_permission('report.executive.follow_up.manage')
  );

CREATE POLICY executive_exception_follow_up_event_insert ON executive_exception_follow_up_event
  FOR INSERT TO authenticated
  WITH CHECK (
    organization_id = public.current_organization_id()
    AND public.has_permission('report.executive.follow_up.manage')
  );

-- =============================================================================
-- ACCESS HELPERS
-- =============================================================================

CREATE OR REPLACE FUNCTION public._assert_executive_exception_read_access()
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_active_app_user() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;
  IF NOT public.has_permission('report.executive.read') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public._assert_executive_exception_follow_up_manage()
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_active_app_user() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;
  IF NOT public.has_permission('report.executive.follow_up.manage') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;
END;
$$;

-- =============================================================================
-- COMPOSITION: list_executive_exceptions
-- =============================================================================

CREATE OR REPLACE FUNCTION public.list_executive_exceptions(
  p_start_date date,
  p_end_date date,
  p_domain text DEFAULT NULL,
  p_exception_code text DEFAULT NULL,
  p_follow_up_status executive_exception_follow_up_status DEFAULT NULL,
  p_search text DEFAULT NULL,
  p_include_historical boolean DEFAULT true
)
RETURNS SETOF jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org uuid;
  v_search text := NULLIF(lower(trim(COALESCE(p_search, ''))), '');
BEGIN
  PERFORM public._assert_executive_exception_read_access();
  PERFORM public.resolve_reporting_period(p_start_date, p_end_date);
  v_org := public.current_organization_id();

  RETURN QUERY
  WITH current_raw AS (
    SELECT
      'finance'::text AS domain,
      '/finance'::text AS domain_drill_down_path,
      fin AS payload
    FROM public.list_finance_exceptions(p_start_date, p_end_date) fin
    WHERE p_domain IS NULL OR p_domain = 'finance'

    UNION ALL

    SELECT
      'admissions'::text,
      '/executive/admissions'::text,
      adm
    FROM public.list_crm_admissions_exceptions(p_start_date, p_end_date) adm
    WHERE p_domain IS NULL OR p_domain = 'admissions'

    UNION ALL

    SELECT
      'quality'::text,
      '/executive/quality'::text,
      qual
    FROM public.list_academic_exceptions(p_start_date, p_end_date) qual
    WHERE p_domain IS NULL OR p_domain = 'quality'

    UNION ALL

    SELECT
      'operations'::text,
      '/executive/operations'::text,
      ops
    FROM public.list_teaching_ops_exceptions(p_start_date, p_end_date) ops
    WHERE p_domain IS NULL OR p_domain = 'operations'
  ),
  current_norm AS (
    SELECT
      public.build_executive_exception_key(
        c.domain,
        c.payload->>'exception_code',
        c.payload->>'entity_type',
        c.payload->>'entity_id'
      ) AS exception_key,
      c.domain,
      c.domain_drill_down_path,
      c.payload->>'exception_code' AS exception_code,
      c.payload->>'reason' AS reason,
      c.payload->>'entity_type' AS entity_type,
      c.payload->>'entity_id' AS entity_id,
      (c.payload->>'metric_value')::numeric AS metric_value,
      c.payload->>'drill_down_path' AS drill_down_path,
      c.payload->'context' AS context,
      true AS source_currently_detected
    FROM current_raw c
    WHERE p_exception_code IS NULL OR c.payload->>'exception_code' = p_exception_code
  ),
  merged AS (
    SELECT
      COALESCE(c.exception_key, f.exception_key) AS exception_key,
      COALESCE(c.domain, f.domain) AS domain,
      COALESCE(c.domain_drill_down_path,
        CASE f.domain
          WHEN 'finance' THEN '/finance'
          WHEN 'admissions' THEN '/executive/admissions'
          WHEN 'quality' THEN '/executive/quality'
          WHEN 'operations' THEN '/executive/operations'
        END
      ) AS domain_drill_down_path,
      COALESCE(c.exception_code, f.exception_code) AS exception_code,
      c.reason,
      COALESCE(c.entity_type, f.entity_type) AS entity_type,
      COALESCE(c.entity_id, f.entity_id) AS entity_id,
      c.metric_value,
      c.drill_down_path,
      c.context,
      COALESCE(c.source_currently_detected, false) AS source_currently_detected,
      f.id AS follow_up_id,
      f.status AS follow_up_status,
      f.latest_note AS follow_up_note,
      f.updated_at AS follow_up_updated_at
    FROM current_norm c
    FULL OUTER JOIN executive_exception_follow_up f
      ON f.organization_id = v_org
     AND f.exception_key = c.exception_key
    WHERE c.exception_key IS NOT NULL
       OR (p_include_historical AND f.organization_id = v_org)
  )
  SELECT jsonb_build_object(
    'exception_key', m.exception_key,
    'domain', m.domain,
    'domain_drill_down_path', m.domain_drill_down_path,
    'exception_code', m.exception_code,
    'reason', m.reason,
    'entity_type', m.entity_type,
    'entity_id', m.entity_id,
    'metric_value', m.metric_value,
    'drill_down_path', m.drill_down_path,
    'context', COALESCE(m.context, '{}'::jsonb),
    'source_currently_detected', m.source_currently_detected,
    'follow_up', CASE
      WHEN m.follow_up_id IS NULL THEN NULL
      ELSE jsonb_build_object(
        'id', m.follow_up_id,
        'status', m.follow_up_status,
        'latest_note', m.follow_up_note,
        'updated_at', m.follow_up_updated_at
      )
    END,
    'reporting_period', jsonb_build_object(
      'start_date', p_start_date,
      'end_date', p_end_date
    )
  )
  FROM merged m
  WHERE (p_exception_code IS NULL OR m.exception_code = p_exception_code)
    AND (
      p_follow_up_status IS NULL
      OR (
        p_follow_up_status = 'open'
        AND (m.follow_up_id IS NULL OR m.follow_up_status = 'open')
      )
      OR (
        p_follow_up_status <> 'open'
        AND m.follow_up_status = p_follow_up_status
      )
    )
    AND (
      v_search IS NULL
      OR lower(m.exception_code) LIKE '%' || v_search || '%'
      OR lower(COALESCE(m.reason, '')) LIKE '%' || v_search || '%'
      OR lower(m.entity_id) LIKE '%' || v_search || '%'
      OR lower(m.entity_type) LIKE '%' || v_search || '%'
    )
  ORDER BY m.source_currently_detected DESC, m.domain, m.exception_code, m.entity_id;
END;
$$;

COMMENT ON FUNCTION public.list_executive_exceptions(date, date, text, text, executive_exception_follow_up_status, text, boolean) IS
  'Cross-domain executive exception worklist composed from canonical domain exception RPCs plus persisted management follow-up. Never suppresses live canonical exceptions because follow-up is resolved.';

CREATE OR REPLACE FUNCTION public.get_executive_exception_worklist_summary(
  p_start_date date,
  p_end_date date
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org uuid;
  v_detected integer;
  v_open integer;
  v_ack integer;
BEGIN
  PERFORM public._assert_executive_exception_read_access();
  v_org := public.current_organization_id();

  SELECT count(*)::integer INTO v_detected
  FROM public.list_executive_exceptions(p_start_date, p_end_date, NULL, NULL, NULL, NULL, false) row
  WHERE (row->>'source_currently_detected')::boolean;

  SELECT count(*)::integer INTO v_open
  FROM executive_exception_follow_up
  WHERE organization_id = v_org AND status = 'open';

  SELECT count(*)::integer INTO v_ack
  FROM executive_exception_follow_up
  WHERE organization_id = v_org AND status = 'acknowledged';

  RETURN jsonb_build_object(
    'current_detected_count', v_detected,
    'open_follow_up_count', v_open,
    'acknowledged_follow_up_count', v_ack,
    'worklist_path', '/executive/exceptions'
  );
END;
$$;

-- =============================================================================
-- FOLLOW-UP MUTATIONS
-- =============================================================================

CREATE OR REPLACE FUNCTION public.save_executive_exception_follow_up(
  p_exception_key text,
  p_domain text,
  p_exception_code text,
  p_entity_type text,
  p_entity_id text,
  p_status executive_exception_follow_up_status DEFAULT NULL,
  p_note text DEFAULT NULL
)
RETURNS executive_exception_follow_up
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org uuid;
  v_user uuid;
  v_row executive_exception_follow_up;
  v_prev executive_exception_follow_up_status;
  v_new_status executive_exception_follow_up_status;
  v_trim_key text := trim(p_exception_key);
BEGIN
  PERFORM public._assert_executive_exception_follow_up_manage();
  v_org := public.current_organization_id();
  v_user := public.current_app_user_id();

  IF v_trim_key = '' OR trim(p_domain) = '' OR trim(p_exception_code) = ''
     OR trim(p_entity_type) = '' OR trim(p_entity_id) = '' THEN
    RAISE EXCEPTION 'invalid_exception_identity' USING ERRCODE = 'P0001';
  END IF;

  IF public.build_executive_exception_key(p_domain, p_exception_code, p_entity_type, p_entity_id)
     <> v_trim_key THEN
    RAISE EXCEPTION 'exception_key_mismatch' USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO v_row
  FROM executive_exception_follow_up
  WHERE organization_id = v_org AND exception_key = v_trim_key
  FOR UPDATE;

  IF NOT FOUND THEN
    v_new_status := COALESCE(p_status, 'open');
    INSERT INTO executive_exception_follow_up (
      organization_id, exception_key, domain, exception_code, entity_type, entity_id,
      status, latest_note, created_by, updated_by
    ) VALUES (
      v_org, v_trim_key, p_domain, p_exception_code, p_entity_type, p_entity_id,
      v_new_status, NULLIF(trim(p_note), ''), v_user, v_user
    )
    RETURNING * INTO v_row;

    INSERT INTO executive_exception_follow_up_event (
      organization_id, follow_up_id, exception_key, event_type, new_status, note, actor_id
    ) VALUES (
      v_org, v_row.id, v_trim_key, 'created', v_new_status, NULLIF(trim(p_note), ''), v_user
    );

    IF NULLIF(trim(p_note), '') IS NOT NULL THEN
      INSERT INTO executive_exception_follow_up_event (
        organization_id, follow_up_id, exception_key, event_type, note, actor_id
      ) VALUES (
        v_org, v_row.id, v_trim_key, 'note_added', NULLIF(trim(p_note), ''), v_user
      );
    END IF;

    RETURN v_row;
  END IF;

  v_prev := v_row.status;
  v_new_status := COALESCE(p_status, v_row.status);

  UPDATE executive_exception_follow_up
  SET status = v_new_status,
      latest_note = CASE
        WHEN NULLIF(trim(p_note), '') IS NOT NULL THEN NULLIF(trim(p_note), '')
        ELSE latest_note
      END,
      updated_by = v_user,
      updated_at = now()
  WHERE id = v_row.id
  RETURNING * INTO v_row;

  IF v_prev IS DISTINCT FROM v_new_status THEN
    INSERT INTO executive_exception_follow_up_event (
      organization_id, follow_up_id, exception_key, event_type,
      previous_status, new_status, actor_id
    ) VALUES (
      v_org, v_row.id, v_trim_key, 'status_changed', v_prev, v_new_status, v_user
    );
  END IF;

  IF NULLIF(trim(p_note), '') IS NOT NULL THEN
    INSERT INTO executive_exception_follow_up_event (
      organization_id, follow_up_id, exception_key, event_type, note, actor_id
    ) VALUES (
      v_org, v_row.id, v_trim_key, 'note_added', NULLIF(trim(p_note), ''), v_user
    );
  END IF;

  RETURN v_row;
END;
$$;

CREATE OR REPLACE FUNCTION public.list_executive_exception_follow_up_history(
  p_exception_key text
)
RETURNS SETOF jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org uuid;
BEGIN
  PERFORM public._assert_executive_exception_read_access();
  v_org := public.current_organization_id();

  RETURN QUERY
  SELECT jsonb_build_object(
    'event_type', e.event_type,
    'previous_status', e.previous_status,
    'new_status', e.new_status,
    'note', e.note,
    'actor_id', e.actor_id,
    'created_at', e.created_at
  )
  FROM executive_exception_follow_up_event e
  WHERE e.organization_id = v_org
    AND e.exception_key = trim(p_exception_key)
  ORDER BY e.created_at ASC, e.id ASC;
END;
$$;

-- Extend executive overview with worklist summary (T06 composition blocks unchanged).
CREATE OR REPLACE FUNCTION public.get_executive_overview(
  p_start_date date,
  p_end_date date,
  p_compare_previous boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_bounds reporting_period_bounds;
  v_compare jsonb;
BEGIN
  PERFORM public._assert_executive_overview_access();
  v_bounds := public.resolve_reporting_period(p_start_date, p_end_date);

  IF p_compare_previous THEN
    v_compare := public.resolve_finance_comparison_period(p_start_date, p_end_date);
  END IF;

  RETURN jsonb_build_object(
    'period', jsonb_build_object(
      'organization_id', v_bounds.organization_id,
      'start_date', v_bounds.start_date,
      'end_date', v_bounds.end_date,
      'timezone', v_bounds.timezone,
      'start_at_utc', v_bounds.start_at_utc,
      'end_at_exclusive', v_bounds.end_at_exclusive
    ),
    'comparison_period', CASE WHEN p_compare_previous THEN v_compare ELSE NULL END,
    'finance', public.get_finance_intelligence_overview(
      p_start_date, p_end_date, p_compare_previous
    ),
    'admissions', public.get_crm_admissions_overview(
      p_start_date, p_end_date, p_compare_previous
    ),
    'quality', public.get_academic_quality_overview(
      p_start_date, p_end_date, p_compare_previous
    ),
    'operations', public.get_teaching_ops_intelligence_overview(
      p_start_date, p_end_date, p_compare_previous
    ),
    'attention', COALESCE((
      SELECT jsonb_agg(item ORDER BY item->>'domain', item->>'exception_code')
      FROM public.list_executive_attention_items(p_start_date, p_end_date, 5) AS item
    ), '[]'::jsonb),
    'exception_worklist', public.get_executive_exception_worklist_summary(p_start_date, p_end_date),
    'composition_rule',
      'Each domain object is the verbatim output of the canonical domain overview RPC for the same period inputs.'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.build_executive_exception_key(text, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public._assert_executive_exception_read_access() TO authenticated;
GRANT EXECUTE ON FUNCTION public._assert_executive_exception_follow_up_manage() TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_executive_exceptions(date, date, text, text, executive_exception_follow_up_status, text, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_executive_exception_worklist_summary(date, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.save_executive_exception_follow_up(text, text, text, text, text, executive_exception_follow_up_status, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_executive_exception_follow_up_history(text) TO authenticated;
