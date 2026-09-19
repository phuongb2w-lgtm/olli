-- M5-T04.1: Consultant cohort attribution and conversion-rate semantics.

-- =============================================================================
-- COHORT CONSULTANT ATTRIBUTION (historical, not current owner)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.crm_lead_cohort_consultant_user_id(
  p_organization_id uuid,
  p_lead_id uuid
)
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT la.new_assigned_user_id
  FROM lead_assignment la
  WHERE la.organization_id = p_organization_id
    AND la.lead_id = p_lead_id
    AND la.new_assigned_user_id IS NOT NULL
  ORDER BY la.changed_at ASC, la.id ASC
  LIMIT 1;
$$;

COMMENT ON FUNCTION public.crm_lead_cohort_consultant_user_id(uuid, uuid) IS
  'Consultant cohort attribution: first effective assignee from lead_assignment (earliest new_assigned_user_id). Does not use current lead.assigned_user_id or lead.created_by.';

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
  v_cohort_rule constant text :=
    'cohort_leads: leads created in period where crm_lead_cohort_consultant_user_id = consultant; '
    || 'cohort_converted_leads: distinct cohort leads with any lead_conversion (lifetime, aligned with source cohort); '
    || 'cohort_conversion_rate: cohort_converted_leads / cohort_leads; '
    || 'conversions_in_period: lead_conversion.converted_at in period with lead_conversion.assigned_user_id snapshot.';
BEGIN
  PERFORM public._assert_crm_executive_access();
  v_bounds := public.resolve_reporting_period(p_start_date, p_end_date);
  v_org := v_bounds.organization_id;

  RETURN jsonb_build_object(
    'cohort_attribution_rule', v_cohort_rule,
    'cohort_conversion_time_rule',
      'Cohort conversions count any canonical lead_conversion on cohort leads (lifetime-to-date), matching source cohort semantics.',
    'rows', (
      SELECT COALESCE(jsonb_agg(row_to_json(sub) ORDER BY sub.display_name), '[]'::jsonb)
      FROM (
        SELECT
          au.id AS consultant_user_id,
          au.display_name,
          (
            SELECT count(*)
            FROM lead l
            WHERE l.organization_id = v_org
              AND l.assigned_user_id = au.id
              AND l.status NOT IN ('converted', 'lost')
          ) AS current_leads_owned,
          (
            SELECT count(DISTINCT l.id)
            FROM lead l
            WHERE l.organization_id = v_org
              AND l.created_at >= v_bounds.start_at_utc
              AND l.created_at < v_bounds.end_at_exclusive
              AND public.crm_lead_cohort_consultant_user_id(v_org, l.id) = au.id
          ) AS cohort_leads,
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
          ) AS conversions_in_period,
          (
            SELECT count(DISTINCT l.id)
            FROM lead l
            JOIN lead_conversion lc
              ON lc.lead_id = l.id AND lc.organization_id = l.organization_id
            WHERE l.organization_id = v_org
              AND l.created_at >= v_bounds.start_at_utc
              AND l.created_at < v_bounds.end_at_exclusive
              AND public.crm_lead_cohort_consultant_user_id(v_org, l.id) = au.id
          ) AS cohort_converted_leads,
          CASE
            WHEN (
              SELECT count(DISTINCT l.id)
              FROM lead l
              WHERE l.organization_id = v_org
                AND l.created_at >= v_bounds.start_at_utc
                AND l.created_at < v_bounds.end_at_exclusive
                AND public.crm_lead_cohort_consultant_user_id(v_org, l.id) = au.id
            ) > 0 THEN round(
              (
                SELECT count(DISTINCT l.id)::numeric
                FROM lead l
                JOIN lead_conversion lc
                  ON lc.lead_id = l.id AND lc.organization_id = l.organization_id
                WHERE l.organization_id = v_org
                  AND l.created_at >= v_bounds.start_at_utc
                  AND l.created_at < v_bounds.end_at_exclusive
                  AND public.crm_lead_cohort_consultant_user_id(v_org, l.id) = au.id
              ) / (
                SELECT count(DISTINCT l.id)::numeric
                FROM lead l
                WHERE l.organization_id = v_org
                  AND l.created_at >= v_bounds.start_at_utc
                  AND l.created_at < v_bounds.end_at_exclusive
                  AND public.crm_lead_cohort_consultant_user_id(v_org, l.id) = au.id
              ),
              4
            )
            ELSE NULL
          END AS cohort_conversion_rate,
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
    )
  );
END;
$$;

COMMENT ON FUNCTION public.get_crm_consultant_productivity(date, date) IS
  'Consultant metrics with separated snapshot workload, period events, and cohort conversion rate. Cohort uses first lead_assignment; period conversions use lead_conversion.assigned_user_id.';

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
  v_cohort_leads bigint;
  v_cohort_converted bigint;
BEGIN
  PERFORM public._assert_consultant_crm_personal_access();
  v_bounds := public.resolve_reporting_period(p_start_date, p_end_date);
  v_org := v_bounds.organization_id;
  v_user := public.current_app_user_id();

  SELECT count(DISTINCT l.id) INTO v_cohort_leads
  FROM lead l
  WHERE l.organization_id = v_org
    AND l.created_at >= v_bounds.start_at_utc
    AND l.created_at < v_bounds.end_at_exclusive
    AND public.crm_lead_cohort_consultant_user_id(v_org, l.id) = v_user;

  SELECT count(DISTINCT l.id) INTO v_cohort_converted
  FROM lead l
  JOIN lead_conversion lc ON lc.lead_id = l.id AND lc.organization_id = l.organization_id
  WHERE l.organization_id = v_org
    AND l.created_at >= v_bounds.start_at_utc
    AND l.created_at < v_bounds.end_at_exclusive
    AND public.crm_lead_cohort_consultant_user_id(v_org, l.id) = v_user;

  RETURN jsonb_build_object(
    'period', jsonb_build_object(
      'start_date', v_bounds.start_date,
      'end_date', v_bounds.end_date,
      'timezone', v_bounds.timezone
    ),
    'consultant_user_id', v_user,
    'cohort_attribution_rule',
      'First effective assignee from lead_assignment history (earliest new_assigned_user_id).',
    'cohort_conversion_time_rule',
      'Cohort conversions include any lead_conversion on cohort leads (lifetime-to-date).',
    'current_leads_owned', (
      SELECT count(*)
      FROM lead l
      WHERE l.organization_id = v_org
        AND l.assigned_user_id = v_user
        AND l.status NOT IN ('converted', 'lost')
    ),
    'cohort_leads', v_cohort_leads,
    'leads_created_by_me', (
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
    'conversions_in_period', (
      SELECT count(*)
      FROM lead_conversion lc
      WHERE lc.organization_id = v_org
        AND lc.assigned_user_id = v_user
        AND lc.converted_at >= v_bounds.start_at_utc
        AND lc.converted_at < v_bounds.end_at_exclusive
    ),
    'cohort_converted_leads', v_cohort_converted,
    'cohort_conversion_rate', CASE
      WHEN v_cohort_leads > 0 THEN round(v_cohort_converted::numeric / v_cohort_leads, 4)
      ELSE NULL
    END,
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
-- SOURCE METRICS (explicit cohort vs period fields)
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
        count(DISTINCT lc_period.id) AS conversions_in_period,
        count(DISTINCT lc_cohort.lead_id) AS cohort_converted_leads,
        CASE
          WHEN count(DISTINCT l.id) > 0 THEN
            round(
              count(DISTINCT lc_cohort.lead_id)::numeric / count(DISTINCT l.id),
              4
            )
          ELSE NULL
        END AS cohort_conversion_rate
      FROM lead l
      LEFT JOIN lead_source ls ON ls.id = l.lead_source_id AND ls.organization_id = l.organization_id
      LEFT JOIN lead_conversion lc_period
        ON lc_period.lead_id = l.id
        AND lc_period.organization_id = l.organization_id
        AND lc_period.converted_at >= v_bounds.start_at_utc
        AND lc_period.converted_at < v_bounds.end_at_exclusive
      LEFT JOIN lead_conversion lc_cohort
        ON lc_cohort.lead_id = l.id
        AND lc_cohort.organization_id = l.organization_id
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
  'Source cohort denominator = leads created in period. cohort_conversion_rate numerator = distinct cohort leads with any lead_conversion. conversions_in_period is a separate period-event metric.';

-- Composite overview: consultant productivity is now wrapped object
CREATE OR REPLACE FUNCTION public.get_crm_admissions_overview(
  p_start_date date,
  p_end_date date,
  p_compare_previous boolean DEFAULT false
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
BEGIN
  PERFORM public._assert_crm_executive_access();
  v_bounds := public.resolve_reporting_period(p_start_date, p_end_date);

  v_span := (p_end_date - p_start_date) + 1;
  v_prev_end := p_start_date - 1;
  v_prev_start := v_prev_end - (v_span - 1);

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

GRANT EXECUTE ON FUNCTION public.crm_lead_cohort_consultant_user_id(uuid, uuid) TO authenticated;
