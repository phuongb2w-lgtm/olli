-- CW2-T11: Tuition declaration V2 — billing configuration, periodic ledger, declaration extensions.

ALTER TABLE public.enrollment_financial_terms
  ADD COLUMN IF NOT EXISTS tuition_plan_established_at timestamptz;

COMMENT ON COLUMN public.enrollment_financial_terms.tuition_plan_established_at IS
  'Set when Accounting confirms an authoritative tuition plan (course or periodic). Until set, net tuition on placeholder terms is not canonical.';

CREATE TABLE IF NOT EXISTS public.organization_academic_year (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organization (id) ON DELETE RESTRICT,
  label text NOT NULL,
  start_date date NOT NULL,
  end_date date NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, id),
  CONSTRAINT organization_academic_year_dates_check CHECK (end_date > start_date)
);

CREATE INDEX IF NOT EXISTS idx_organization_academic_year_org
  ON public.organization_academic_year (organization_id, start_date DESC);

COMMENT ON TABLE public.organization_academic_year IS
  'Authoritative school-year boundaries per organization (no hardcoded regional calendar).';

CREATE TABLE IF NOT EXISTS public.enrollment_tuition_billing (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  enrollment_id uuid NOT NULL,
  enrollment_financial_terms_id uuid NOT NULL,
  billing_mode text NOT NULL,
  period_unit text,
  period_quantity integer,
  amount_per_period bigint,
  organization_academic_year_id uuid,
  established_at timestamptz NOT NULL DEFAULT now(),
  established_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, id),
  UNIQUE (organization_id, enrollment_id),
  CONSTRAINT enrollment_tuition_billing_mode_check CHECK (
    billing_mode IN ('course_lump_sum', 'periodic')
  ),
  CONSTRAINT enrollment_tuition_billing_period_unit_check CHECK (
    period_unit IS NULL OR period_unit IN ('lesson', 'week', 'month', 'school_year')
  ),
  CONSTRAINT enrollment_tuition_billing_period_quantity_check CHECK (
    period_quantity IS NULL OR period_quantity > 0
  ),
  CONSTRAINT enrollment_tuition_billing_amount_check CHECK (
    amount_per_period IS NULL OR amount_per_period > 0
  ),
  CONSTRAINT enrollment_tuition_billing_periodic_fields_check CHECK (
    billing_mode <> 'periodic'
    OR (
      period_unit IS NOT NULL
      AND period_quantity IS NOT NULL
      AND amount_per_period IS NOT NULL
      AND (
        period_unit <> 'school_year'
        OR organization_academic_year_id IS NOT NULL
      )
    )
  ),
  FOREIGN KEY (organization_id, enrollment_id)
    REFERENCES public.enrollment (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, enrollment_financial_terms_id)
    REFERENCES public.enrollment_financial_terms (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, organization_academic_year_id)
    REFERENCES public.organization_academic_year (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, established_by)
    REFERENCES public.app_user (organization_id, id) ON DELETE RESTRICT
);

CREATE INDEX IF NOT EXISTS idx_enrollment_tuition_billing_terms
  ON public.enrollment_tuition_billing (organization_id, enrollment_financial_terms_id);

CREATE TABLE IF NOT EXISTS public.enrollment_periodic_tuition_balance (
  organization_id uuid NOT NULL,
  enrollment_id uuid NOT NULL,
  carry_forward_credit bigint NOT NULL DEFAULT 0,
  lessons_remaining_in_block integer,
  lessons_per_block integer,
  amount_per_block bigint,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (organization_id, enrollment_id),
  CONSTRAINT enrollment_periodic_balance_credit_check CHECK (carry_forward_credit >= 0),
  CONSTRAINT enrollment_periodic_balance_lessons_check CHECK (
    lessons_remaining_in_block IS NULL OR lessons_remaining_in_block >= 0
  ),
  FOREIGN KEY (organization_id, enrollment_id)
    REFERENCES public.enrollment (organization_id, id) ON DELETE RESTRICT
);

CREATE TABLE IF NOT EXISTS public.enrollment_periodic_period_obligation (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  enrollment_id uuid NOT NULL,
  period_key text NOT NULL,
  obligation_amount bigint NOT NULL,
  satisfied_amount bigint NOT NULL DEFAULT 0,
  status text NOT NULL DEFAULT 'open',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, id),
  UNIQUE (organization_id, enrollment_id, period_key),
  CONSTRAINT enrollment_periodic_obligation_amount_check CHECK (obligation_amount > 0),
  CONSTRAINT enrollment_periodic_obligation_satisfied_check CHECK (satisfied_amount >= 0),
  CONSTRAINT enrollment_periodic_obligation_status_check CHECK (
    status IN ('open', 'satisfied', 'underpaid')
  ),
  FOREIGN KEY (organization_id, enrollment_id)
    REFERENCES public.enrollment (organization_id, id) ON DELETE RESTRICT
);

CREATE TABLE IF NOT EXISTS public.enrollment_periodic_session_consumption (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  enrollment_id uuid NOT NULL,
  teaching_session_id uuid NOT NULL,
  enrollment_tuition_billing_id uuid NOT NULL,
  consumed_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, id),
  UNIQUE (organization_id, enrollment_id, teaching_session_id),
  FOREIGN KEY (organization_id, enrollment_id)
    REFERENCES public.enrollment (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, teaching_session_id)
    REFERENCES public.teaching_session (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, enrollment_tuition_billing_id)
    REFERENCES public.enrollment_tuition_billing (organization_id, id) ON DELETE RESTRICT
);

ALTER TABLE public.consultant_revenue_declaration
  ADD COLUMN IF NOT EXISTS tuition_billing_mode text,
  ADD COLUMN IF NOT EXISTS proposed_net_tuition_amount bigint,
  ADD COLUMN IF NOT EXISTS periodic_period_unit text,
  ADD COLUMN IF NOT EXISTS periodic_period_quantity integer,
  ADD COLUMN IF NOT EXISTS periodic_amount_per_period bigint,
  ADD COLUMN IF NOT EXISTS periodic_academic_year_id uuid,
  ADD COLUMN IF NOT EXISTS payment_method_code text,
  ADD COLUMN IF NOT EXISTS declaration_kind text NOT NULL DEFAULT 'payment_only',
  ADD COLUMN IF NOT EXISTS depends_on_declaration_id uuid;

ALTER TABLE public.enrollment_periodic_session_consumption
  ADD COLUMN IF NOT EXISTS reversed_at timestamptz,
  ADD COLUMN IF NOT EXISTS lesson_units_consumed integer NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS period_key text;

CREATE TABLE IF NOT EXISTS public.enrollment_periodic_consumption_audit (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  enrollment_id uuid NOT NULL,
  teaching_session_id uuid NOT NULL,
  action text NOT NULL,
  reason text,
  actor_user_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT enrollment_periodic_consumption_audit_action_check CHECK (
    action IN ('consume', 'reverse')
  )
);

ALTER TABLE public.consultant_revenue_declaration
  DROP CONSTRAINT IF EXISTS consultant_revenue_declaration_depends_on_fk;
ALTER TABLE public.consultant_revenue_declaration
  ADD CONSTRAINT consultant_revenue_declaration_depends_on_fk
    FOREIGN KEY (organization_id, depends_on_declaration_id)
    REFERENCES public.consultant_revenue_declaration (organization_id, id)
    ON DELETE RESTRICT;

ALTER TABLE public.consultant_revenue_declaration
  DROP CONSTRAINT IF EXISTS consultant_revenue_declaration_tuition_billing_mode_check;
ALTER TABLE public.consultant_revenue_declaration
  ADD CONSTRAINT consultant_revenue_declaration_tuition_billing_mode_check CHECK (
    tuition_billing_mode IS NULL OR tuition_billing_mode IN ('course_lump_sum', 'periodic')
  );

ALTER TABLE public.consultant_revenue_declaration
  DROP CONSTRAINT IF EXISTS consultant_revenue_declaration_declaration_kind_check;
ALTER TABLE public.consultant_revenue_declaration
  ADD CONSTRAINT consultant_revenue_declaration_declaration_kind_check CHECK (
    declaration_kind IN ('payment_only', 'initial_tuition_setup')
  );

ALTER TABLE public.consultant_revenue_declaration
  DROP CONSTRAINT IF EXISTS consultant_revenue_declaration_periodic_unit_check;
ALTER TABLE public.consultant_revenue_declaration
  ADD CONSTRAINT consultant_revenue_declaration_periodic_unit_check CHECK (
    periodic_period_unit IS NULL OR periodic_period_unit IN ('lesson', 'week', 'month', 'school_year')
  );

CREATE UNIQUE INDEX IF NOT EXISTS idx_cw2_one_pending_initial_tuition_setup
  ON public.consultant_revenue_declaration (organization_id, enrollment_id)
  WHERE workflow_kind = 'cw2_payment'
    AND status = 'pending'
    AND declaration_kind = 'initial_tuition_setup';

ALTER TABLE public.enrollment_tuition_billing ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.enrollment_tuition_billing FORCE ROW LEVEL SECURITY;
ALTER TABLE public.enrollment_periodic_tuition_balance ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.enrollment_periodic_tuition_balance FORCE ROW LEVEL SECURITY;
ALTER TABLE public.enrollment_periodic_period_obligation ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.enrollment_periodic_period_obligation FORCE ROW LEVEL SECURITY;
ALTER TABLE public.enrollment_periodic_session_consumption ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.enrollment_periodic_session_consumption FORCE ROW LEVEL SECURITY;
ALTER TABLE public.organization_academic_year ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.organization_academic_year FORCE ROW LEVEL SECURITY;

CREATE POLICY organization_academic_year_select ON public.organization_academic_year
  FOR SELECT USING (organization_id = public.current_organization_id());

CREATE POLICY enrollment_tuition_billing_select ON public.enrollment_tuition_billing
  FOR SELECT USING (organization_id = public.current_organization_id());

CREATE POLICY enrollment_periodic_balance_select ON public.enrollment_periodic_tuition_balance
  FOR SELECT USING (organization_id = public.current_organization_id());

CREATE POLICY enrollment_periodic_obligation_select ON public.enrollment_periodic_period_obligation
  FOR SELECT USING (organization_id = public.current_organization_id());

CREATE POLICY enrollment_periodic_consumption_select ON public.enrollment_periodic_session_consumption
  FOR SELECT USING (organization_id = public.current_organization_id());
