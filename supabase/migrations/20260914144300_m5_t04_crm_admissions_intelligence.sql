-- M5-T04: CRM / admissions / consultant productivity intelligence read layer.
-- Uses canonical M3 event/history tables — never fabricates history from lead.status alone.

-- =============================================================================
-- INDEXES
-- =============================================================================

CREATE INDEX IF NOT EXISTS idx_lead_activity_org_occurred_at
  ON lead_activity (organization_id, occurred_at);

CREATE INDEX IF NOT EXISTS idx_lead_follow_up_org_status_due
  ON lead_follow_up (organization_id, status, due_at);

CREATE INDEX IF NOT EXISTS idx_lead_trial_org_completed_at
  ON lead_trial (organization_id, completed_at)
  WHERE completed_at IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_consultant_rev_decl_org_consultant_date
  ON consultant_revenue_declaration (organization_id, consultant_user_id, declaration_date);

-- =============================================================================
-- PERMISSION GATES
-- =============================================================================

CREATE OR REPLACE FUNCTION public._assert_crm_executive_access()
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

COMMENT ON FUNCTION public._assert_crm_executive_access() IS
  'Center-wide CRM/admissions executive intelligence. Consultants and accountants are excluded.';

CREATE OR REPLACE FUNCTION public._assert_consultant_crm_personal_access()
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

  IF NOT public.has_permission('lead.read') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;
END;
$$;

COMMENT ON FUNCTION public._assert_consultant_crm_personal_access() IS
  'Personal CRM workspace for consultants. Does not grant executive center-wide intelligence.';

-- =============================================================================
-- LEAD INTAKE (PERIOD EVENT)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_crm_lead_intake_metrics(
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
  v_bounds reporting_period_bounds;
BEGIN
  PERFORM public._assert_crm_executive_access();
  v_bounds := public.resolve_reporting_period(p_start_date, p_end_date);

  RETURN (
    SELECT jsonb_build_object(
      'kpi', 'crm.lead_intake',
      'metric_type', 'period_event',
      'leads_created', count(*),
      'unassigned_count', count(*) FILTER (WHERE l.assigned_user_id IS NULL),
      'denominator_rule', 'Count of lead rows where created_at falls in inclusive local reporting period.',
      'event_timestamp', 'lead.created_at'
    )
    FROM lead l
    WHERE l.organization_id = v_bounds.organization_id
      AND l.created_at >= v_bounds.start_at_utc
      AND l.created_at < v_bounds.end_at_exclusive
  );
END;
$$;

-- =============================================================================
-- ACTIVITY / FOLLOW-UP (PERIOD EVENT + SNAPSHOT)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_crm_activity_metrics(
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
  v_bounds reporting_period_bounds;
  v_org uuid;
BEGIN
  PERFORM public._assert_crm_executive_access();
  v_bounds := public.resolve_reporting_period(p_start_date, p_end_date);
  v_org := v_bounds.organization_id;

  RETURN jsonb_build_object(
    'kpi', 'crm.follow_up_activity',
    'activities_recorded', (
      SELECT count(*)
      FROM lead_activity la
      WHERE la.organization_id = v_org
        AND la.occurred_at >= v_bounds.start_at_utc
        AND la.occurred_at < v_bounds.end_at_exclusive
    ),
    'activities_by_actor', (
      SELECT COALESCE(jsonb_agg(row_to_json(sub)), '[]'::jsonb)
      FROM (
        SELECT la.created_by AS consultant_user_id,
          au.display_name,
          count(*) AS activity_count
        FROM lead_activity la
        JOIN app_user au ON au.id = la.created_by AND au.organization_id = la.organization_id
        WHERE la.organization_id = v_org
          AND la.occurred_at >= v_bounds.start_at_utc
          AND la.occurred_at < v_bounds.end_at_exclusive
        GROUP BY la.created_by, au.display_name
        ORDER BY activity_count DESC
      ) sub
    ),
    'pending_follow_ups', (
      SELECT count(*)
      FROM lead_follow_up f
      JOIN lead l ON l.id = f.lead_id AND l.organization_id = f.organization_id
      WHERE f.organization_id = v_org
        AND f.status = 'pending'
        AND l.status NOT IN ('converted', 'lost')
    ),
    'overdue_follow_ups', (
      SELECT count(*)
      FROM lead_follow_up f
      JOIN lead l ON l.id = f.lead_id AND l.organization_id = f.organization_id
      WHERE f.organization_id = v_org
        AND f.status = 'pending'
        AND f.due_at < now()
        AND l.status NOT IN ('converted', 'lost')
    ),
    'activity_event_timestamp', 'lead_activity.occurred_at',
    'overdue_rule', 'lead_follow_up.status = pending AND due_at < now() AND lead not converted/lost'
  );
END;
$$;

-- =============================================================================
-- TRIALS (PERIOD EVENT)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_crm_trial_metrics(
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
  v_bounds reporting_period_bounds;
  v_org uuid;
BEGIN
  PERFORM public._assert_crm_executive_access();
  v_bounds := public.resolve_reporting_period(p_start_date, p_end_date);
  v_org := v_bounds.organization_id;

  RETURN jsonb_build_object(
    'kpi', 'crm.trials',
    'trials_scheduled', (
      SELECT count(*)
      FROM lead_trial t
      WHERE t.organization_id = v_org
        AND t.created_at >= v_bounds.start_at_utc
        AND t.created_at < v_bounds.end_at_exclusive
    ),
    'trials_completed', (
      SELECT count(*)
      FROM lead_trial t
      WHERE t.organization_id = v_org
        AND t.status = 'completed'
        AND t.completed_at IS NOT NULL
        AND t.completed_at >= v_bounds.start_at_utc
        AND t.completed_at < v_bounds.end_at_exclusive
    ),
    'scheduled_event_timestamp', 'lead_trial.created_at',
    'completed_event_timestamp', 'lead_trial.completed_at',
    'denominator_rule', 'Scheduled and completed are separate period-event counts; do not infer completion from lead.status.'
  );
END;
$$;

-- =============================================================================
-- CONVERSION (PERIOD EVENT + COHORT)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_crm_conversion_metrics(
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
  v_bounds reporting_period_bounds;
  v_org uuid;
  v_period_conversions bigint;
  v_cohort_leads bigint;
  v_cohort_conversions bigint;
BEGIN
  PERFORM public._assert_crm_executive_access();
  v_bounds := public.resolve_reporting_period(p_start_date, p_end_date);
  v_org := v_bounds.organization_id;

  SELECT count(*) INTO v_period_conversions
  FROM lead_conversion lc
  WHERE lc.organization_id = v_org
    AND lc.converted_at >= v_bounds.start_at_utc
    AND lc.converted_at < v_bounds.end_at_exclusive;

  SELECT count(*) INTO v_cohort_leads
  FROM lead l
  WHERE l.organization_id = v_org
    AND l.created_at >= v_bounds.start_at_utc
    AND l.created_at < v_bounds.end_at_exclusive;

  SELECT count(*) INTO v_cohort_conversions
  FROM lead l
  JOIN lead_conversion lc ON lc.lead_id = l.id AND lc.organization_id = l.organization_id
  WHERE l.organization_id = v_org
    AND l.created_at >= v_bounds.start_at_utc
    AND l.created_at < v_bounds.end_at_exclusive;

  RETURN jsonb_build_object(
    'kpi', 'crm.conversions',
    'conversions_in_period', v_period_conversions,
    'period_event_timestamp', 'lead_conversion.converted_at',
    'period_event_denominator_rule', 'Count of lead_conversion rows with converted_at in period.',
    'cohort_leads_created', v_cohort_leads,
    'cohort_conversions', v_cohort_conversions,
    'cohort_conversion_rate', CASE
      WHEN v_cohort_leads > 0 THEN round(v_cohort_conversions::numeric / v_cohort_leads, 4)
      ELSE NULL
    END,
    'cohort_denominator_rule', 'cohort_conversions / leads created in same period (inclusive local dates).',
    'enrollments_linked', (
      SELECT count(*)
      FROM lead_conversion_enrollment lce
      JOIN lead_conversion lc ON lc.id = lce.lead_conversion_id
      WHERE lce.organization_id = v_org
        AND lc.converted_at >= v_bounds.start_at_utc
        AND lc.converted_at < v_bounds.end_at_exclusive
    ),
    'conversions_without_enrollment', (
      SELECT count(*)
      FROM lead_conversion lc
      WHERE lc.organization_id = v_org
        AND lc.converted_at >= v_bounds.start_at_utc
        AND lc.converted_at < v_bounds.end_at_exclusive
        AND NOT EXISTS (
          SELECT 1 FROM lead_conversion_enrollment lce
          WHERE lce.lead_conversion_id = lc.id AND lce.organization_id = v_org
        )
    )
  );
END;
$$;

-- =============================================================================
-- CONSULTANT PRODUCTIVITY (EXECUTIVE)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_crm_consultant_productivity(
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
  v_bounds reporting_period_bounds;
  v_org uuid;
BEGIN
  PERFORM public._assert_crm_executive_access();
  v_bounds := public.resolve_reporting_period(p_start_date, p_end_date);
  v_org := v_bounds.organization_id;

  RETURN (
    SELECT COALESCE(jsonb_agg(row_to_json(sub) ORDER BY sub.display_name), '[]'::jsonb)
    FROM (
      SELECT
        au.id AS consultant_user_id,
        au.display_name,
        (
          SELECT count(DISTINCT l.id)
          FROM lead l
          WHERE l.organization_id = v_org
            AND l.assigned_user_id = au.id
            AND l.created_at >= v_bounds.start_at_utc
            AND l.created_at < v_bounds.end_at_exclusive
        ) AS leads_owned_created,
        (
          SELECT count(*)
          FROM lead_activity la
          WHERE la.organization_id = v_org
            AND la.created_by = au.id
            AND la.occurred_at >= v_bounds.start_at_utc
            AND la.occurred_at < v_bounds.end_at_exclusive
        ) AS activities_recorded,
        (
          SELECT count(*)
          FROM lead_trial t
          WHERE t.organization_id = v_org
            AND t.created_by = au.id
            AND t.created_at >= v_bounds.start_at_utc
            AND t.created_at < v_bounds.end_at_exclusive
        ) AS trials_scheduled,
        (
          SELECT count(*)
          FROM lead_conversion lc
          WHERE lc.organization_id = v_org
            AND lc.assigned_user_id = au.id
            AND lc.converted_at >= v_bounds.start_at_utc
            AND lc.converted_at < v_bounds.end_at_exclusive
        ) AS conversions_attributed,
        CASE
          WHEN (
            SELECT count(DISTINCT l.id)
            FROM lead l
            WHERE l.organization_id = v_org
              AND l.assigned_user_id = au.id
              AND l.created_at >= v_bounds.start_at_utc
              AND l.created_at < v_bounds.end_at_exclusive
          ) > 0 THEN round(
            (
              SELECT count(*)::numeric
              FROM lead_conversion lc2
              WHERE lc2.organization_id = v_org
                AND lc2.assigned_user_id = au.id
                AND lc2.converted_at >= v_bounds.start_at_utc
                AND lc2.converted_at < v_bounds.end_at_exclusive
            ) / (
              SELECT count(DISTINCT l.id)::numeric
              FROM lead l
              WHERE l.organization_id = v_org
                AND l.assigned_user_id = au.id
                AND l.created_at >= v_bounds.start_at_utc
                AND l.created_at < v_bounds.end_at_exclusive
            ),
            4
          )
          ELSE NULL
        END AS conversion_rate_by_attribution,
        (
          SELECT COALESCE(SUM(crd.declared_amount) FILTER (WHERE crd.status = 'approved'), 0)
          FROM consultant_revenue_declaration crd
          WHERE crd.organization_id = v_org
            AND crd.consultant_user_id = au.id
            AND crd.declaration_date BETWEEN p_start_date AND p_end_date
        ) AS approved_declarations_amount,
        (
          SELECT COALESCE(SUM(crd.declared_amount) FILTER (WHERE crd.status = 'pending'), 0)
          FROM consultant_revenue_declaration crd
          WHERE crd.organization_id = v_org
            AND crd.consultant_user_id = au.id
            AND crd.declaration_date BETWEEN p_start_date AND p_end_date
        ) AS pending_declarations_amount
      FROM app_user au
      WHERE au.organization_id = v_org
        AND au.status = 'active'
        AND EXISTS (
          SELECT 1 FROM user_role ur
          JOIN role_permission rp ON rp.role_id = ur.role_id
          JOIN permission p ON p.id = rp.permission_id
          WHERE ur.user_id = au.id
            AND ur.organization_id = v_org
            AND ur.status = 'active'
            AND p.code IN ('lead.read', 'lead.create', 'lead.update')
        )
    ) sub
  );
END;
$$;

COMMENT ON FUNCTION public.get_crm_consultant_productivity(date, date) IS
  'Objective consultant metrics. Conversion attribution uses lead_conversion.assigned_user_id snapshot. Approved declaration amounts are NOT cash.';

-- =============================================================================
-- SOURCE / CHANNEL (COHORT + PERIOD CONVERSIONS)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_crm_source_metrics(
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
  v_bounds reporting_period_bounds;
  v_org uuid;
BEGIN
  PERFORM public._assert_crm_executive_access();
  v_bounds := public.resolve_reporting_period(p_start_date, p_end_date);
  v_org := v_bounds.organization_id;

  RETURN (
    SELECT COALESCE(jsonb_agg(row_to_json(sub)), '[]'::jsonb)
    FROM (
      SELECT
        COALESCE(ls.display_name, 'Unattributed') AS source_name,
        ls.id AS source_id,
        count(DISTINCT l.id) AS leads_created,
        count(DISTINCT lc.id) FILTER (
          WHERE lc.converted_at >= v_bounds.start_at_utc
            AND lc.converted_at < v_bounds.end_at_exclusive
        ) AS conversions_in_period,
        CASE
          WHEN count(DISTINCT l.id) > 0 THEN
            round(
              count(DISTINCT lc_all.lead_id)::numeric / count(DISTINCT l.id),
              4
            )
          ELSE NULL
        END AS cohort_conversion_rate
      FROM lead l
      LEFT JOIN lead_source ls ON ls.id = l.lead_source_id AND ls.organization_id = l.organization_id
      LEFT JOIN lead_conversion lc ON lc.lead_id = l.id AND lc.organization_id = l.organization_id
        AND lc.converted_at >= v_bounds.start_at_utc
        AND lc.converted_at < v_bounds.end_at_exclusive
      LEFT JOIN lead_conversion lc_all ON lc_all.lead_id = l.id AND lc_all.organization_id = l.organization_id
      WHERE l.organization_id = v_org
        AND l.created_at >= v_bounds.start_at_utc
        AND l.created_at < v_bounds.end_at_exclusive
      GROUP BY ls.id, ls.display_name
      ORDER BY leads_created DESC
    ) sub
  );
END;
$$;

COMMENT ON FUNCTION public.get_crm_source_metrics(date, date) IS
  'Source cohort uses leads created in period with current lead_source_id. Period conversions use lead_conversion.converted_at.';

-- =============================================================================
-- PIPELINE SNAPSHOT (POINT IN TIME)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_crm_pipeline_snapshot()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org uuid;
BEGIN
  PERFORM public._assert_crm_executive_access();
  v_org := public.current_organization_id();

  RETURN (
    SELECT jsonb_build_object(
      'metric_type', 'point_in_time_snapshot',
      'as_of', now(),
      'by_status', COALESCE(jsonb_object_agg(sub.status, sub.cnt), '{}'::jsonb)
    )
    FROM (
      SELECT l.status, count(*) AS cnt
      FROM lead l
      WHERE l.organization_id = v_org
      GROUP BY l.status
    ) sub
  );
END;
$$;

-- =============================================================================
-- EXECUTIVE OVERVIEW COMPOSITE
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_crm_admissions_overview(
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
  v_span integer;
  v_prev_start date;
  v_prev_end date;
  v_prev_bounds reporting_period_bounds;
BEGIN
  PERFORM public._assert_crm_executive_access();
  v_bounds := public.resolve_reporting_period(p_start_date, p_end_date);

  v_span := (p_end_date - p_start_date) + 1;
  v_prev_end := p_start_date - 1;
  v_prev_start := v_prev_end - (v_span - 1);

  IF p_compare_previous THEN
    v_prev_bounds := public.resolve_reporting_period(v_prev_start, v_prev_end);
  END IF;

  RETURN jsonb_build_object(
    'period', jsonb_build_object(
      'start_date', v_bounds.start_date,
      'end_date', v_bounds.end_date,
      'timezone', v_bounds.timezone,
      'start_at_utc', v_bounds.start_at_utc,
      'end_at_exclusive', v_bounds.end_at_exclusive
    ),
    'comparison_period', CASE
      WHEN p_compare_previous THEN jsonb_build_object(
        'start_date', v_prev_start,
        'end_date', v_prev_end
      )
      ELSE NULL
    END,
    'leadIntake', public.get_crm_lead_intake_metrics(p_start_date, p_end_date),
    'activity', public.get_crm_activity_metrics(p_start_date, p_end_date),
    'trials', public.get_crm_trial_metrics(p_start_date, p_end_date),
    'conversions', public.get_crm_conversion_metrics(p_start_date, p_end_date),
    'consultantProductivity', public.get_crm_consultant_productivity(p_start_date, p_end_date),
    'sources', public.get_crm_source_metrics(p_start_date, p_end_date),
    'pipelineSnapshot', public.get_crm_pipeline_snapshot(),
    'declarations', public.get_consultant_declaration_summary(p_start_date, p_end_date)
  );
END;
$$;

COMMENT ON FUNCTION public.get_crm_admissions_overview(date, date, boolean) IS
  'Center-wide CRM/admissions intelligence for center managers. Historical metrics use event timestamps, not lead.status alone.';

-- =============================================================================
-- CONSULTANT PERSONAL OVERVIEW
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_consultant_crm_overview(
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
  v_bounds reporting_period_bounds;
  v_org uuid;
  v_user uuid;
BEGIN
  PERFORM public._assert_consultant_crm_personal_access();
  v_bounds := public.resolve_reporting_period(p_start_date, p_end_date);
  v_org := v_bounds.organization_id;
  v_user := public.current_app_user_id();

  RETURN jsonb_build_object(
    'period', jsonb_build_object(
      'start_date', v_bounds.start_date,
      'end_date', v_bounds.end_date,
      'timezone', v_bounds.timezone
    ),
    'consultant_user_id', v_user,
    'leads_owned', (
      SELECT count(*)
      FROM lead l
      WHERE l.organization_id = v_org
        AND l.assigned_user_id = v_user
        AND l.status NOT IN ('converted', 'lost')
    ),
    'leads_created_in_period', (
      SELECT count(*)
      FROM lead l
      WHERE l.organization_id = v_org
        AND l.created_by = v_user
        AND l.created_at >= v_bounds.start_at_utc
        AND l.created_at < v_bounds.end_at_exclusive
    ),
    'activities_in_period', (
      SELECT count(*)
      FROM lead_activity la
      WHERE la.organization_id = v_org
        AND la.created_by = v_user
        AND la.occurred_at >= v_bounds.start_at_utc
        AND la.occurred_at < v_bounds.end_at_exclusive
    ),
    'trials_scheduled_in_period', (
      SELECT count(*)
      FROM lead_trial t
      WHERE t.organization_id = v_org
        AND t.created_by = v_user
        AND t.created_at >= v_bounds.start_at_utc
        AND t.created_at < v_bounds.end_at_exclusive
    ),
    'conversions_attributed_in_period', (
      SELECT count(*)
      FROM lead_conversion lc
      WHERE lc.organization_id = v_org
        AND lc.assigned_user_id = v_user
        AND lc.converted_at >= v_bounds.start_at_utc
        AND lc.converted_at < v_bounds.end_at_exclusive
    ),
    'conversion_rate_attributed', (
      SELECT CASE
        WHEN owned.cnt > 0 THEN round(conv.cnt::numeric / owned.cnt, 4)
        ELSE NULL
      END
      FROM (
        SELECT count(*) AS cnt
        FROM lead l
        WHERE l.organization_id = v_org
          AND l.assigned_user_id = v_user
          AND l.created_at >= v_bounds.start_at_utc
          AND l.created_at < v_bounds.end_at_exclusive
      ) owned,
      (
        SELECT count(*) AS cnt
        FROM lead_conversion lc
        WHERE lc.organization_id = v_org
          AND lc.assigned_user_id = v_user
          AND lc.converted_at >= v_bounds.start_at_utc
          AND lc.converted_at < v_bounds.end_at_exclusive
      ) conv
    ),
    'declarations', (
      SELECT jsonb_build_object(
        'pending_amount', COALESCE(SUM(crd.declared_amount) FILTER (WHERE crd.status = 'pending'), 0),
        'pending_count', COALESCE(COUNT(*) FILTER (WHERE crd.status = 'pending'), 0),
        'returned_amount', COALESCE(SUM(crd.declared_amount) FILTER (WHERE crd.status = 'returned'), 0),
        'returned_count', COALESCE(COUNT(*) FILTER (WHERE crd.status = 'returned'), 0),
        'approved_amount', COALESCE(SUM(crd.declared_amount) FILTER (WHERE crd.status = 'approved'), 0),
        'approved_count', COALESCE(COUNT(*) FILTER (WHERE crd.status = 'approved'), 0),
        'approved_linked_count', COALESCE(COUNT(*) FILTER (
          WHERE crd.status = 'approved'
            AND public.declaration_has_canonical_payment(crd.id)
        ), 0),
        'semantic_note', 'Approved declaration amount is not cash collected or recognized revenue.'
      )
      FROM consultant_revenue_declaration crd
      WHERE crd.organization_id = v_org
        AND crd.consultant_user_id = v_user
        AND crd.declaration_date BETWEEN p_start_date AND p_end_date
    )
  );
END;
$$;

-- =============================================================================
-- CONSULTANT WORK QUEUE (PERSONAL)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.list_consultant_work_queue(
  p_limit integer DEFAULT 20
)
RETURNS SETOF jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org uuid;
  v_user uuid;
BEGIN
  PERFORM public._assert_consultant_crm_personal_access();
  v_org := public.current_organization_id();
  v_user := public.current_app_user_id();

  RETURN QUERY
  SELECT jsonb_build_object(
    'queue_type', 'overdue_follow_up',
    'lead_id', f.lead_id,
    'due_at', f.due_at,
    'note', f.note,
    'drill_down_path', '/crm/leads/' || f.lead_id::text
  )
  FROM lead_follow_up f
  JOIN lead l ON l.id = f.lead_id AND l.organization_id = f.organization_id
  WHERE f.organization_id = v_org
    AND f.status = 'pending'
    AND f.due_at < now()
    AND (f.assigned_user_id = v_user OR l.assigned_user_id = v_user)
    AND l.status NOT IN ('converted', 'lost')
  ORDER BY f.due_at ASC
  LIMIT p_limit;

  RETURN QUERY
  SELECT jsonb_build_object(
    'queue_type', 'upcoming_follow_up',
    'lead_id', f.lead_id,
    'due_at', f.due_at,
    'note', f.note,
    'drill_down_path', '/crm/leads/' || f.lead_id::text
  )
  FROM lead_follow_up f
  JOIN lead l ON l.id = f.lead_id AND l.organization_id = f.organization_id
  WHERE f.organization_id = v_org
    AND f.status = 'pending'
    AND f.due_at >= now()
    AND f.due_at < now() + interval '7 days'
    AND (f.assigned_user_id = v_user OR l.assigned_user_id = v_user)
    AND l.status NOT IN ('converted', 'lost')
  ORDER BY f.due_at ASC
  LIMIT p_limit;

  RETURN QUERY
  SELECT jsonb_build_object(
    'queue_type', 'owned_active_lead',
    'lead_id', l.id,
    'status', l.status,
    'drill_down_path', '/crm/leads/' || l.id::text
  )
  FROM lead l
  WHERE l.organization_id = v_org
    AND l.assigned_user_id = v_user
    AND l.status NOT IN ('converted', 'lost')
  ORDER BY l.updated_at DESC
  LIMIT p_limit;
END;
$$;

-- =============================================================================
-- ADMISSIONS EXCEPTIONS (EXECUTIVE)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.list_crm_admissions_exceptions(
  p_start_date date,
  p_end_date date
)
RETURNS SETOF jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_bounds reporting_period_bounds;
  v_org uuid;
BEGIN
  PERFORM public._assert_crm_executive_access();
  v_bounds := public.resolve_reporting_period(p_start_date, p_end_date);
  v_org := v_bounds.organization_id;

  RETURN QUERY
  SELECT jsonb_build_object(
    'exception_code', 'unassigned_active_lead',
    'reason', 'Active lead has no assigned consultant',
    'entity_type', 'lead',
    'entity_id', l.id,
    'metric_value', 1,
    'drill_down_path', '/crm/leads/' || l.id::text,
    'context', jsonb_build_object('status', l.status, 'created_at', l.created_at)
  )
  FROM lead l
  WHERE l.organization_id = v_org
    AND l.assigned_user_id IS NULL
    AND l.status NOT IN ('converted', 'lost');

  RETURN QUERY
  SELECT jsonb_build_object(
    'exception_code', 'overdue_follow_up',
    'reason', 'Follow-up is overdue',
    'entity_type', 'lead_follow_up',
    'entity_id', f.id,
    'metric_value', extract(epoch FROM (now() - f.due_at)) / 86400,
    'drill_down_path', '/crm/leads/' || f.lead_id::text,
    'context', jsonb_build_object('due_at', f.due_at, 'lead_id', f.lead_id)
  )
  FROM lead_follow_up f
  JOIN lead l ON l.id = f.lead_id AND l.organization_id = f.organization_id
  WHERE f.organization_id = v_org
    AND f.status = 'pending'
    AND f.due_at < now()
    AND l.status NOT IN ('converted', 'lost');

  RETURN QUERY
  SELECT jsonb_build_object(
    'exception_code', 'stale_active_lead',
    'reason', 'Active lead with no activity in 14 days',
    'entity_type', 'lead',
    'entity_id', l.id,
    'metric_value', 14,
    'drill_down_path', '/crm/leads/' || l.id::text,
    'context', jsonb_build_object('status', l.status)
  )
  FROM lead l
  WHERE l.organization_id = v_org
    AND l.status NOT IN ('converted', 'lost')
    AND l.created_at < now() - interval '14 days'
    AND NOT EXISTS (
      SELECT 1 FROM lead_activity la
      WHERE la.lead_id = l.id
        AND la.organization_id = v_org
        AND la.occurred_at >= now() - interval '14 days'
    );

  RETURN QUERY
  SELECT jsonb_build_object(
    'exception_code', 'trial_pending_outcome',
    'reason', 'Scheduled trial start time has passed without completion',
    'entity_type', 'lead_trial',
    'entity_id', t.id,
    'metric_value', 1,
    'drill_down_path', '/crm/leads/' || t.lead_id::text,
    'context', jsonb_build_object('scheduled_start_at', t.scheduled_start_at, 'lead_id', t.lead_id)
  )
  FROM lead_trial t
  WHERE t.organization_id = v_org
    AND t.status = 'scheduled'
    AND t.scheduled_start_at < now() - interval '1 day';

  RETURN QUERY
  SELECT jsonb_build_object(
    'exception_code', 'conversion_missing_enrollment',
    'reason', 'Converted lead has no enrollment linkage',
    'entity_type', 'lead_conversion',
    'entity_id', lc.id,
    'metric_value', 1,
    'drill_down_path', '/crm/leads/' || lc.lead_id::text,
    'context', jsonb_build_object('converted_at', lc.converted_at)
  )
  FROM lead_conversion lc
  WHERE lc.organization_id = v_org
    AND lc.converted_at >= v_bounds.start_at_utc
    AND lc.converted_at < v_bounds.end_at_exclusive
    AND NOT EXISTS (
      SELECT 1 FROM lead_conversion_enrollment lce
      WHERE lce.lead_conversion_id = lc.id AND lce.organization_id = v_org
    );

  RETURN QUERY
  SELECT jsonb_build_object(
    'exception_code', 'returned_revenue_declaration',
    'reason', 'Consultant revenue declaration returned for correction',
    'entity_type', 'consultant_revenue_declaration',
    'entity_id', crd.id,
    'metric_value', crd.declared_amount,
    'drill_down_path', '/finance/consultant-revenue',
    'context', jsonb_build_object(
      'consultant_user_id', crd.consultant_user_id,
      'declaration_date', crd.declaration_date
    )
  )
  FROM consultant_revenue_declaration crd
  WHERE crd.organization_id = v_org
    AND crd.status = 'returned'
    AND crd.declaration_date BETWEEN p_start_date AND p_end_date;
END;
$$;

-- =============================================================================
-- GRANTS
-- =============================================================================

GRANT EXECUTE ON FUNCTION public._assert_crm_executive_access() TO authenticated;
GRANT EXECUTE ON FUNCTION public._assert_consultant_crm_personal_access() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_crm_lead_intake_metrics(date, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_crm_activity_metrics(date, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_crm_trial_metrics(date, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_crm_conversion_metrics(date, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_crm_consultant_productivity(date, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_crm_source_metrics(date, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_crm_pipeline_snapshot() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_crm_admissions_overview(date, date, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_consultant_crm_overview(date, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_consultant_work_queue(integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_crm_admissions_exceptions(date, date) TO authenticated;
