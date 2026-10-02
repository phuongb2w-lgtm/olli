-- CW2-T11: Conservative backfill — only enrollments with net tuition > 0 AND posted payment evidence.

UPDATE public.enrollment_financial_terms t
SET tuition_plan_established_at = COALESCE(t.charges_generated_at, t.updated_at, t.created_at)
WHERE t.status = 'active'
  AND t.net_tuition_amount > 0
  AND t.tuition_plan_established_at IS NULL
  AND EXISTS (
    SELECT 1
    FROM public.charge c
    WHERE c.enrollment_financial_terms_id = t.id
      AND c.organization_id = t.organization_id
      AND c.status <> 'void'
      AND c.amount > 0
  )
  AND EXISTS (
    SELECT 1
    FROM public.payment_allocation pa
    JOIN public.charge c ON c.id = pa.charge_id
    WHERE c.enrollment_financial_terms_id = t.id
      AND c.organization_id = t.organization_id
      AND pa.status = 'posted'
      AND pa.amount > 0
  );

INSERT INTO public.enrollment_tuition_billing (
  organization_id, enrollment_id, enrollment_financial_terms_id, billing_mode, established_at
)
SELECT
  t.organization_id,
  t.enrollment_id,
  t.id,
  'course_lump_sum',
  t.tuition_plan_established_at
FROM public.enrollment_financial_terms t
WHERE t.status = 'active'
  AND t.tuition_plan_established_at IS NOT NULL
  AND t.net_tuition_amount > 0
ON CONFLICT (organization_id, enrollment_id) DO NOTHING;
