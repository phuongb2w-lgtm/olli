-- M3-T08: CRM marketing attribution and conversion reporting (read-only).

-- =============================================================================
-- REPORTING INDEXES
-- =============================================================================

CREATE INDEX idx_lead_org_created_at ON lead (organization_id, created_at);
CREATE INDEX idx_lead_conversion_org_converted_at ON lead_conversion (organization_id, converted_at);
CREATE INDEX idx_lead_status_history_org_changed_at ON lead_status_history (organization_id, changed_at);
CREATE INDEX idx_lead_status_history_org_to_status ON lead_status_history (organization_id, to_status, lead_id);

COMMENT ON INDEX idx_lead_org_created_at IS
  'Supports CRM attribution reporting by lead creation window.';

-- =============================================================================
-- ATTRIBUTION REPORT RPC
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_crm_attribution_report(
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
  v_org_id uuid;
  v_can_charge boolean;
  v_can_payment boolean;
  v_can_revenue boolean;
  v_result jsonb;
BEGIN
  IF NOT public.is_active_app_user() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  IF NOT public.has_permission('lead.read') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  IF p_start_date IS NULL OR p_end_date IS NULL OR p_end_date < p_start_date THEN
    RAISE EXCEPTION 'invalid_date_range' USING ERRCODE = 'P0001';
  END IF;

  v_org_id := public.current_organization_id();
  v_can_charge := public.has_permission('charge.read');
  v_can_payment := public.has_permission('payment.read');
  v_can_revenue := public.has_permission('revenue.read');

  WITH lead_cohort AS (
    SELECT l.id, l.lead_source_id, l.lead_campaign_id, l.status, l.created_at
    FROM lead l
    WHERE l.organization_id = v_org_id
      AND l.created_at::date >= p_start_date
      AND l.created_at::date <= p_end_date
  ),
  milestone AS (
    SELECT DISTINCT h.lead_id, h.to_status
    FROM lead_status_history h
    JOIN lead_cohort c ON c.id = h.lead_id
    WHERE h.organization_id = v_org_id
      AND h.to_status IN (
        'contacted', 'qualified', 'trial_scheduled', 'trial_completed', 'converted', 'lost'
      )
  ),
  trial_leads AS (
    SELECT DISTINCT t.lead_id,
      bool_or(t.status IN ('scheduled', 'completed', 'no_show', 'cancelled')) AS has_scheduled,
      bool_or(t.status = 'completed') AS has_completed
    FROM lead_trial t
    JOIN lead_cohort c ON c.id = t.lead_id
    WHERE t.organization_id = v_org_id
    GROUP BY t.lead_id
  ),
  trial_volume AS (
    SELECT
      count(*) FILTER (
        WHERE t.created_at::date >= p_start_date AND t.created_at::date <= p_end_date
      ) AS trials_created,
      count(*) FILTER (
        WHERE t.status = 'completed'
          AND t.completed_at IS NOT NULL
          AND t.completed_at::date >= p_start_date
          AND t.completed_at::date <= p_end_date
      ) AS trials_completed
    FROM lead_trial t
    WHERE t.organization_id = v_org_id
  ),
  cohort_converted AS (
    SELECT DISTINCT c.id AS lead_id
    FROM lead_cohort c
    JOIN lead_conversion lc ON lc.lead_id = c.id AND lc.organization_id = v_org_id
  ),
  cohort_enrolled AS (
    SELECT DISTINCT c.id AS lead_id
    FROM lead_cohort c
    JOIN lead_conversion lc ON lc.lead_id = c.id AND lc.organization_id = v_org_id
    JOIN lead_conversion_enrollment lce ON lce.lead_conversion_id = lc.id AND lce.organization_id = v_org_id
  ),
  conversions_period AS (
    SELECT lc.*
    FROM lead_conversion lc
    WHERE lc.organization_id = v_org_id
      AND lc.converted_at::date >= p_start_date
      AND lc.converted_at::date <= p_end_date
  ),
  conversion_students AS (
    SELECT count(*) AS student_count
    FROM lead_conversion_candidate cc
    JOIN conversions_period cp ON cp.id = cc.lead_conversion_id
    WHERE cc.organization_id = v_org_id
  ),
  conversion_enrollments AS (
    SELECT count(*) AS enrollment_count
    FROM lead_conversion_enrollment ce
    JOIN conversions_period cp ON cp.id = ce.lead_conversion_id
    WHERE ce.organization_id = v_org_id
  ),
  conversions_without_enrollment AS (
    SELECT count(*) AS conversion_count
    FROM conversions_period cp
    WHERE NOT EXISTS (
      SELECT 1 FROM lead_conversion_enrollment ce
      WHERE ce.lead_conversion_id = cp.id AND ce.organization_id = v_org_id
    )
  ),
  lost_events AS (
    SELECT h.lead_id, h.lost_reason_id
    FROM lead_status_history h
    WHERE h.organization_id = v_org_id
      AND h.to_status = 'lost'
      AND h.changed_at::date >= p_start_date
      AND h.changed_at::date <= p_end_date
  ),
  funnel AS (
    SELECT
      (SELECT count(*) FROM lead_cohort) AS leads_created,
      (SELECT count(DISTINCT lead_id) FROM milestone WHERE to_status = 'contacted') AS contacted_leads,
      (SELECT count(DISTINCT lead_id) FROM milestone WHERE to_status = 'qualified') AS qualified_leads,
      (
        SELECT count(DISTINCT lead_id) FROM milestone WHERE to_status = 'trial_scheduled'
      ) + (
        SELECT count(*) FROM trial_leads tl
        WHERE tl.has_scheduled
          AND NOT EXISTS (
            SELECT 1 FROM milestone m WHERE m.lead_id = tl.lead_id AND m.to_status = 'trial_scheduled'
          )
      ) AS trial_scheduled_leads,
      (
        SELECT count(DISTINCT lead_id) FROM milestone WHERE to_status = 'trial_completed'
      ) + (
        SELECT count(*) FROM trial_leads tl
        WHERE tl.has_completed
          AND NOT EXISTS (
            SELECT 1 FROM milestone m WHERE m.lead_id = tl.lead_id AND m.to_status = 'trial_completed'
          )
      ) AS trial_completed_leads,
      (SELECT count(*) FROM conversions_period) AS converted_leads,
      (SELECT count(DISTINCT lead_id) FROM cohort_converted) AS cohort_converted_leads,
      (SELECT count(DISTINCT lead_id) FROM cohort_enrolled) AS enrolled_leads,
      (SELECT count(DISTINCT lead_id) FROM lost_events) AS lost_leads,
      (SELECT student_count FROM conversion_students) AS converted_students,
      (SELECT enrollment_count FROM conversion_enrollments) AS enrollments_from_conversions,
      (SELECT conversion_count FROM conversions_without_enrollment) AS conversions_without_enrollment,
      (SELECT trials_created FROM trial_volume) AS trial_events_scheduled,
      (SELECT trials_completed FROM trial_volume) AS trial_events_completed
  ),
  source_rows AS (
    SELECT
      ls.id AS lead_source_id,
      ls.code,
      ls.display_name,
      ls.status,
      count(c.id) AS leads_created,
      count(DISTINCT c.id) FILTER (
        WHERE EXISTS (SELECT 1 FROM milestone m WHERE m.lead_id = c.id AND m.to_status = 'qualified')
      ) AS qualified_leads,
      count(DISTINCT c.id) FILTER (
        WHERE EXISTS (
          SELECT 1 FROM milestone m WHERE m.lead_id = c.id AND m.to_status = 'trial_scheduled'
        ) OR EXISTS (
          SELECT 1 FROM trial_leads tl WHERE tl.lead_id = c.id AND tl.has_scheduled
        )
      ) AS trial_scheduled_leads,
      count(DISTINCT c.id) FILTER (
        WHERE EXISTS (
          SELECT 1 FROM milestone m WHERE m.lead_id = c.id AND m.to_status = 'trial_completed'
        ) OR EXISTS (
          SELECT 1 FROM trial_leads tl WHERE tl.lead_id = c.id AND tl.has_completed
        )
      ) AS trial_completed_leads,
      count(DISTINCT cp.lead_id) AS converted_leads,
      count(DISTINCT c.id) FILTER (
        WHERE EXISTS (SELECT 1 FROM cohort_enrolled e WHERE e.lead_id = c.id)
      ) AS enrolled_leads
    FROM lead_source ls
    LEFT JOIN lead_cohort c ON c.lead_source_id = ls.id
    LEFT JOIN conversions_period cp ON cp.lead_source_id = ls.id
    WHERE ls.organization_id = v_org_id
    GROUP BY ls.id, ls.code, ls.display_name, ls.status

    UNION ALL

    SELECT
      NULL::uuid AS lead_source_id,
      'unattributed'::text AS code,
      'Unattributed'::text AS display_name,
      'active'::text AS status,
      count(c.id) AS leads_created,
      count(DISTINCT c.id) FILTER (
        WHERE EXISTS (SELECT 1 FROM milestone m WHERE m.lead_id = c.id AND m.to_status = 'qualified')
      ) AS qualified_leads,
      count(DISTINCT c.id) FILTER (
        WHERE EXISTS (
          SELECT 1 FROM milestone m WHERE m.lead_id = c.id AND m.to_status = 'trial_scheduled'
        ) OR EXISTS (
          SELECT 1 FROM trial_leads tl WHERE tl.lead_id = c.id AND tl.has_scheduled
        )
      ) AS trial_scheduled_leads,
      count(DISTINCT c.id) FILTER (
        WHERE EXISTS (
          SELECT 1 FROM milestone m WHERE m.lead_id = c.id AND m.to_status = 'trial_completed'
        ) OR EXISTS (
          SELECT 1 FROM trial_leads tl WHERE tl.lead_id = c.id AND tl.has_completed
        )
      ) AS trial_completed_leads,
      count(DISTINCT cp.lead_id) AS converted_leads,
      count(DISTINCT c.id) FILTER (
        WHERE EXISTS (SELECT 1 FROM cohort_enrolled e WHERE e.lead_id = c.id)
      ) AS enrolled_leads
    FROM lead_cohort c
    LEFT JOIN conversions_period cp ON cp.lead_id = c.id AND cp.lead_source_id IS NULL
    WHERE c.lead_source_id IS NULL
  ),
  campaign_rows AS (
    SELECT
      lc.id AS lead_campaign_id,
      lc.code,
      lc.name,
      lc.status,
      lc.lead_source_id,
      lc.expense_id,
      count(DISTINCT c.id) AS leads_created,
      count(DISTINCT cp.lead_id) AS conversions_in_period,
      count(DISTINCT ce.enrollment_id) AS enrollments_from_conversions,
      CASE
        WHEN lc.expense_id IS NOT NULL THEN (
          SELECT e.amount FROM expense e
          WHERE e.organization_id = v_org_id AND e.id = lc.expense_id AND e.status = 'posted'
        )
        ELSE NULL
      END AS campaign_spend
    FROM lead_campaign lc
    LEFT JOIN lead_cohort c ON c.lead_campaign_id = lc.id
    LEFT JOIN conversions_period cp ON cp.lead_campaign_id = lc.id
    LEFT JOIN lead_conversion_enrollment ce
      ON ce.lead_conversion_id = cp.id AND ce.organization_id = v_org_id
    WHERE lc.organization_id = v_org_id
    GROUP BY lc.id, lc.code, lc.name, lc.status, lc.lead_source_id, lc.expense_id

    UNION ALL

    SELECT
      NULL::uuid,
      'unattributed'::text,
      'Unattributed'::text,
      'active'::text,
      NULL::uuid,
      NULL::uuid,
      count(c.id),
      count(DISTINCT cp.lead_id),
      count(DISTINCT ce.enrollment_id),
      NULL::bigint
    FROM lead_cohort c
    LEFT JOIN conversions_period cp ON cp.lead_id = c.id AND cp.lead_campaign_id IS NULL
    LEFT JOIN lead_conversion_enrollment ce
      ON ce.lead_conversion_id = cp.id AND ce.organization_id = v_org_id
    WHERE c.lead_campaign_id IS NULL
  ),
  enrollment_finance AS (
    SELECT
      cp.lead_source_id,
      cp.lead_campaign_id,
      ce.enrollment_id,
      coalesce(ch.charged_amount, 0)::bigint AS charged_amount,
      coalesce(pa.collected_amount, 0)::bigint AS collected_amount,
      coalesce(rev.recognized_amount, 0)::bigint AS recognized_amount
    FROM conversions_period cp
    JOIN lead_conversion_enrollment ce
      ON ce.lead_conversion_id = cp.id AND ce.organization_id = v_org_id
    LEFT JOIN LATERAL (
      SELECT sum(c.amount)::bigint AS charged_amount
      FROM charge c
      WHERE c.organization_id = v_org_id
        AND c.enrollment_id = ce.enrollment_id
        AND c.status <> 'void'
    ) ch ON true
    LEFT JOIN LATERAL (
      SELECT sum(pa.amount)::bigint AS collected_amount
      FROM payment_allocation pa
      JOIN charge c ON c.id = pa.charge_id AND c.organization_id = v_org_id
      WHERE pa.organization_id = v_org_id
        AND pa.status = 'posted'
        AND c.enrollment_id = ce.enrollment_id
    ) pa ON true
    LEFT JOIN LATERAL (
      SELECT sum(r.amount)::bigint AS recognized_amount
      FROM revenue_recognition_event r
      WHERE r.organization_id = v_org_id
        AND r.enrollment_id = ce.enrollment_id
        AND r.status = 'posted'
        AND r.recognized_at::date >= p_start_date
        AND r.recognized_at::date <= p_end_date
    ) rev ON true
  ),
  lost_reason_rows AS (
    SELECT
      lr.id AS lost_reason_id,
      lr.code,
      lr.display_name,
      count(le.lead_id) AS lost_count
    FROM lead_lost_reason lr
    LEFT JOIN lost_events le ON le.lost_reason_id = lr.id
    WHERE lr.organization_id = v_org_id
    GROUP BY lr.id, lr.code, lr.display_name
    HAVING count(le.lead_id) > 0
  ),
  referral_rows AS (
    SELECT
      count(*) FILTER (WHERE cp.referral_guardian_id IS NOT NULL) AS guardian_referral_conversions,
      count(*) FILTER (WHERE cp.referral_student_id IS NOT NULL) AS student_referral_conversions
    FROM conversions_period cp
  )
  SELECT jsonb_build_object(
    'period', jsonb_build_object(
      'start_date', p_start_date,
      'end_date', p_end_date
    ),
    'semantics', jsonb_build_object(
      'funnel_cohort', 'Leads created within the reporting window.',
      'funnel_stages', 'Observed milestones from lead_status_history and canonical trial facts; stage skipping allowed.',
      'conversion_count', 'Conversions with lead_conversion.converted_at within the window.',
      'enrollment_count', 'Candidate-specific enrollments linked to conversions in the window.',
      'downstream_attribution', 'Enrollment/finance metrics use immutable lead_conversion snapshot attribution.',
      'lead_creation_attribution', 'Lead cohort metrics use current lead source/campaign at query time.',
      'conversion_rate', 'converted_leads / leads_created (distinct date semantics documented above).',
      'trial_completion_rate', 'trial_completed_leads / trial_scheduled_leads within cohort.',
      'trial_to_conversion_rate', 'converted_leads / trial_completed_leads among conversions in period with completed trial history.',
      'converted_to_enrolled_rate', 'enrollments_from_conversions / converted_leads in period.'
    ),
    'permissions', jsonb_build_object(
      'can_view_charged', v_can_charge,
      'can_view_collected', v_can_payment,
      'can_view_recognized_revenue', v_can_revenue
    ),
    'funnel', (
      SELECT jsonb_build_object(
        'leads_created', f.leads_created,
        'contacted_leads', f.contacted_leads,
        'qualified_leads', f.qualified_leads,
        'trial_scheduled_leads', f.trial_scheduled_leads,
        'trial_completed_leads', f.trial_completed_leads,
        'converted_leads', f.converted_leads,
        'cohort_converted_leads', f.cohort_converted_leads,
        'enrolled_leads', f.enrolled_leads,
        'lost_leads', f.lost_leads,
        'converted_students', f.converted_students,
        'enrollments_from_conversions', f.enrollments_from_conversions,
        'conversions_without_enrollment', f.conversions_without_enrollment,
        'trial_events_scheduled', f.trial_events_scheduled,
        'trial_events_completed', f.trial_events_completed,
        'conversion_rate', CASE WHEN f.leads_created > 0
          THEN round(f.converted_leads::numeric / f.leads_created::numeric, 4) ELSE 0 END,
        'lost_rate', CASE WHEN f.leads_created > 0
          THEN round(f.lost_leads::numeric / f.leads_created::numeric, 4) ELSE 0 END,
        'trial_scheduling_rate', CASE WHEN f.leads_created > 0
          THEN round(f.trial_scheduled_leads::numeric / f.leads_created::numeric, 4) ELSE 0 END,
        'trial_completion_rate', CASE WHEN f.trial_scheduled_leads > 0
          THEN round(f.trial_completed_leads::numeric / f.trial_scheduled_leads::numeric, 4) ELSE 0 END,
        'trial_to_conversion_rate', CASE WHEN f.trial_completed_leads > 0
          THEN round(f.converted_leads::numeric / f.trial_completed_leads::numeric, 4) ELSE 0 END,
        'converted_to_enrolled_rate', CASE WHEN f.converted_leads > 0
          THEN round(f.enrollments_from_conversions::numeric / f.converted_leads::numeric, 4) ELSE 0 END
      )
      FROM funnel f
    ),
    'sources', coalesce((
      SELECT jsonb_agg(
        jsonb_build_object(
          'lead_source_id', sr.lead_source_id,
          'code', sr.code,
          'display_name', sr.display_name,
          'status', sr.status,
          'leads_created', sr.leads_created,
          'qualified_leads', sr.qualified_leads,
          'trial_scheduled_leads', sr.trial_scheduled_leads,
          'trial_completed_leads', sr.trial_completed_leads,
          'converted_leads', sr.converted_leads,
          'enrolled_leads', sr.enrolled_leads,
          'conversion_rate', CASE WHEN sr.leads_created > 0
            THEN round(sr.converted_leads::numeric / sr.leads_created::numeric, 4) ELSE 0 END,
          'financials', CASE
            WHEN v_can_charge OR v_can_payment OR v_can_revenue THEN (
              SELECT jsonb_build_object(
                'charged_amount', CASE WHEN v_can_charge
                  THEN coalesce(sum(ef.charged_amount), 0) ELSE NULL END,
                'collected_amount', CASE WHEN v_can_payment
                  THEN coalesce(sum(ef.collected_amount), 0) ELSE NULL END,
                'recognized_revenue', CASE WHEN v_can_revenue
                  THEN coalesce(sum(ef.recognized_amount), 0) ELSE NULL END
              )
              FROM enrollment_finance ef
              WHERE (sr.lead_source_id IS NULL AND ef.lead_source_id IS NULL)
                 OR ef.lead_source_id = sr.lead_source_id
            )
            ELSE NULL
          END
        )
        ORDER BY sr.leads_created DESC, sr.display_name
      )
      FROM source_rows sr
    ), '[]'::jsonb),
    'campaigns', coalesce((
      SELECT jsonb_agg(
        jsonb_build_object(
          'lead_campaign_id', cr.lead_campaign_id,
          'code', cr.code,
          'name', cr.name,
          'status', cr.status,
          'lead_source_id', cr.lead_source_id,
          'leads_created', cr.leads_created,
          'conversions_in_period', cr.conversions_in_period,
          'enrollments_from_conversions', cr.enrollments_from_conversions,
          'campaign_spend', cr.campaign_spend,
          'financials', CASE
            WHEN v_can_charge OR v_can_payment OR v_can_revenue THEN (
              SELECT jsonb_build_object(
                'charged_amount', CASE WHEN v_can_charge
                  THEN coalesce(sum(ef.charged_amount), 0) ELSE NULL END,
                'collected_amount', CASE WHEN v_can_payment
                  THEN coalesce(sum(ef.collected_amount), 0) ELSE NULL END,
                'recognized_revenue', CASE WHEN v_can_revenue
                  THEN coalesce(sum(ef.recognized_amount), 0) ELSE NULL END
              )
              FROM enrollment_finance ef
              WHERE (cr.lead_campaign_id IS NULL AND ef.lead_campaign_id IS NULL)
                 OR ef.lead_campaign_id = cr.lead_campaign_id
            )
            ELSE NULL
          END
        )
        ORDER BY cr.leads_created DESC, cr.name
      )
      FROM campaign_rows cr
    ), '[]'::jsonb),
    'lost_reasons', coalesce((
      SELECT jsonb_agg(
        jsonb_build_object(
          'lost_reason_id', lr.lost_reason_id,
          'code', lr.code,
          'display_name', lr.display_name,
          'lost_count', lr.lost_count,
          'share_of_lost', CASE WHEN (SELECT count(DISTINCT lead_id) FROM lost_events) > 0
            THEN round(lr.lost_count::numeric / (SELECT count(DISTINCT lead_id) FROM lost_events)::numeric, 4)
            ELSE 0 END
        )
        ORDER BY lr.lost_count DESC, lr.display_name
      )
      FROM lost_reason_rows lr
    ), '[]'::jsonb),
    'referrals', (
      SELECT jsonb_build_object(
        'guardian_referral_conversions', rr.guardian_referral_conversions,
        'student_referral_conversions', rr.student_referral_conversions
      )
      FROM referral_rows rr
    )
  )
  INTO v_result;

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.get_crm_attribution_report(date, date) IS
  'Read-only CRM attribution/funnel report. Requires lead.read; financial columns require charge.read, payment.read, revenue.read respectively.';

GRANT EXECUTE ON FUNCTION public.get_crm_attribution_report(date, date) TO authenticated;
