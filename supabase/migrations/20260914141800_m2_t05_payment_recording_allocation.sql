-- M2-T05: Payment recording, allocation workflow, and auditable corrections.

-- =============================================================================
-- PERMISSIONS
-- =============================================================================

INSERT INTO permission (code) VALUES
  ('payment.reverse')
ON CONFLICT (code) DO NOTHING;

-- =============================================================================
-- PAYMENT EXTENSIONS
-- =============================================================================

ALTER TABLE payment
  ADD COLUMN student_id uuid,
  ADD COLUMN payer_name_snapshot text,
  ADD COLUMN notes text,
  ADD COLUMN idempotency_key text,
  ADD COLUMN reversed_at timestamptz,
  ADD COLUMN reversal_of_payment_id uuid;

ALTER TABLE payment
  ADD CONSTRAINT payment_student_fk
    FOREIGN KEY (organization_id, student_id) REFERENCES student (organization_id, id) ON DELETE RESTRICT,
  ADD CONSTRAINT payment_reversal_of_fk
    FOREIGN KEY (organization_id, reversal_of_payment_id) REFERENCES payment (organization_id, id) ON DELETE RESTRICT;

ALTER TABLE payment DROP CONSTRAINT IF EXISTS payment_status_check;
ALTER TABLE payment
  ADD CONSTRAINT payment_status_check CHECK (status IN ('posted', 'void', 'reversed'));

ALTER TABLE payment DROP CONSTRAINT IF EXISTS payment_method_check;
ALTER TABLE payment
  ADD CONSTRAINT payment_method_check CHECK (
    method_code IN ('cash', 'bank_transfer', 'card', 'other')
  );

CREATE UNIQUE INDEX idx_payment_idempotency_key
  ON payment (organization_id, idempotency_key)
  WHERE idempotency_key IS NOT NULL;

COMMENT ON COLUMN payment.payer_name_snapshot IS
  'Historical payer label at receipt time; does not depend on current guardian relationship.';
COMMENT ON COLUMN payment.idempotency_key IS
  'Caller-supplied key; record_payment returns the existing row on retry within the organization.';
COMMENT ON COLUMN payment.student_id IS
  'Optional student context when cash is received on behalf of a learner.';

-- =============================================================================
-- PAYMENT ALLOCATION EXTENSIONS
-- =============================================================================

ALTER TABLE payment_allocation
  ADD COLUMN status text NOT NULL DEFAULT 'posted',
  ADD COLUMN reversed_at timestamptz,
  ADD COLUMN reversal_of_allocation_id uuid,
  ADD COLUMN allocation_batch_id uuid,
  ADD COLUMN notes text;

ALTER TABLE payment_allocation
  ADD CONSTRAINT payment_allocation_status_check CHECK (status IN ('posted', 'void')),
  ADD CONSTRAINT payment_allocation_reversal_of_fk
    FOREIGN KEY (organization_id, reversal_of_allocation_id)
    REFERENCES payment_allocation (organization_id, id) ON DELETE RESTRICT;

CREATE INDEX idx_payment_allocation_status
  ON payment_allocation (organization_id, charge_id, status)
  WHERE status = 'posted';

-- =============================================================================
-- ALLOCATION BATCH (idempotent multi-allocation operations)
-- =============================================================================

CREATE TABLE payment_allocation_batch (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organization (id) ON DELETE RESTRICT,
  payment_id      uuid NOT NULL,
  operation_key   text NOT NULL,
  created_at      timestamptz NOT NULL DEFAULT now(),
  created_by      uuid,
  UNIQUE (organization_id, id),
  UNIQUE (organization_id, operation_key),
  FOREIGN KEY (organization_id, payment_id) REFERENCES payment (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, created_by) REFERENCES app_user (organization_id, id) ON DELETE RESTRICT
);

ALTER TABLE payment_allocation
  ADD CONSTRAINT payment_allocation_batch_fk
    FOREIGN KEY (organization_id, allocation_batch_id)
    REFERENCES payment_allocation_batch (organization_id, id) ON DELETE RESTRICT;

COMMENT ON TABLE payment_allocation_batch IS
  'Idempotency anchor for allocate_payment batch retries. One operation_key per organization.';

-- =============================================================================
-- TRIGGER HELPERS
-- =============================================================================

CREATE OR REPLACE FUNCTION public.charge_effective_obligation(p_charge_id uuid)
RETURNS bigint
LANGUAGE sql
STABLE
AS $$
  SELECT c.amount + COALESCE((
    SELECT SUM(fa.amount_delta)
    FROM financial_adjustment fa
    WHERE fa.charge_id = c.id AND fa.status = 'posted'
  ), 0)::bigint
  FROM charge c
  WHERE c.id = p_charge_id;
$$;

CREATE OR REPLACE FUNCTION public.charge_allocated_amount(p_charge_id uuid)
RETURNS bigint
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE(SUM(pa.amount), 0)::bigint
  FROM payment_allocation pa
  WHERE pa.charge_id = p_charge_id AND pa.status = 'posted';
$$;

CREATE OR REPLACE FUNCTION public.payment_allocated_amount(p_payment_id uuid)
RETURNS bigint
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE(SUM(pa.amount), 0)::bigint
  FROM payment_allocation pa
  WHERE pa.payment_id = p_payment_id AND pa.status = 'posted';
$$;

CREATE OR REPLACE FUNCTION validate_payment_allocations()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_payment_id uuid;
  total_allocated bigint;
  payment_amount bigint;
  payment_status text;
BEGIN
  v_payment_id := COALESCE(NEW.payment_id, OLD.payment_id);

  SELECT amount, status INTO payment_amount, payment_status
  FROM payment WHERE id = v_payment_id FOR UPDATE;

  IF payment_status NOT IN ('posted') THEN
    RAISE EXCEPTION 'payment_not_allocatable';
  END IF;

  SELECT COALESCE(SUM(amount), 0) INTO total_allocated
  FROM payment_allocation
  WHERE payment_id = v_payment_id AND status = 'posted';

  IF total_allocated > payment_amount THEN
    RAISE EXCEPTION 'Total payment allocations (%) exceed payment amount (%)', total_allocated, payment_amount;
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE OR REPLACE FUNCTION validate_charge_allocation_cap()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_effective bigint;
  v_allocated bigint;
  v_charge_status text;
  v_charge_org uuid;
  v_payment_org uuid;
  v_charge_currency text;
  v_payment_currency text;
  v_payment_status text;
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.status = 'void' THEN
    RETURN NEW;
  END IF;

  IF NEW.status IS DISTINCT FROM 'posted' THEN
    RETURN NEW;
  END IF;

  SELECT c.status, c.organization_id, c.currency_code
    INTO v_charge_status, v_charge_org, v_charge_currency
  FROM charge c
  WHERE c.id = NEW.charge_id
  FOR UPDATE;

  IF v_charge_status NOT IN ('open', 'partially_paid') THEN
    RAISE EXCEPTION 'charge_not_allocatable';
  END IF;

  SELECT p.organization_id, p.currency_code, p.status
    INTO v_payment_org, v_payment_currency, v_payment_status
  FROM payment p
  WHERE p.id = NEW.payment_id
  FOR UPDATE;

  IF v_payment_status NOT IN ('posted') THEN
    RAISE EXCEPTION 'payment_not_allocatable';
  END IF;

  IF v_charge_org <> v_payment_org OR v_charge_org <> NEW.organization_id THEN
    RAISE EXCEPTION 'cross_organization_allocation_rejected';
  END IF;

  IF v_charge_currency <> v_payment_currency THEN
    RAISE EXCEPTION 'currency_mismatch';
  END IF;

  v_effective := public.charge_effective_obligation(NEW.charge_id);

  SELECT COALESCE(SUM(pa.amount), 0) INTO v_allocated
  FROM payment_allocation pa
  WHERE pa.charge_id = NEW.charge_id
    AND pa.status = 'posted'
    AND pa.id IS DISTINCT FROM NEW.id;

  IF v_allocated + NEW.amount > v_effective THEN
    RAISE EXCEPTION 'allocation_exceeds_outstanding';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER payment_allocation_validate_charge_cap
  BEFORE INSERT OR UPDATE ON payment_allocation
  FOR EACH ROW EXECUTE FUNCTION validate_charge_allocation_cap();

CREATE OR REPLACE FUNCTION sync_charge_collection_status()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_charge_id uuid;
  v_outstanding bigint;
  v_effective bigint;
BEGIN
  v_charge_id := COALESCE(NEW.charge_id, OLD.charge_id);

  v_effective := public.charge_effective_obligation(v_charge_id);
  v_outstanding := v_effective - public.charge_allocated_amount(v_charge_id);

  UPDATE charge
  SET status = CASE
    WHEN status = 'void' THEN 'void'
    WHEN v_outstanding <= 0 THEN 'paid'
    WHEN v_outstanding < v_effective THEN 'partially_paid'
    ELSE 'open'
  END,
  updated_at = now()
  WHERE id = v_charge_id AND status <> 'void';

  RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE TRIGGER payment_allocation_sync_charge_status
  AFTER INSERT OR UPDATE OR DELETE ON payment_allocation
  FOR EACH ROW EXECUTE FUNCTION sync_charge_collection_status();

-- =============================================================================
-- DERIVED VIEWS
-- =============================================================================

DROP VIEW IF EXISTS public.charge_balance;

CREATE VIEW charge_balance AS
SELECT
  c.id AS charge_id,
  c.organization_id,
  c.amount AS original_amount,
  COALESCE((
    SELECT SUM(fa.amount_delta)
    FROM financial_adjustment fa
    WHERE fa.charge_id = c.id AND fa.status = 'posted'
  ), 0)::bigint AS adjustments_total,
  (
    c.amount + COALESCE((
      SELECT SUM(fa.amount_delta)
      FROM financial_adjustment fa
      WHERE fa.charge_id = c.id AND fa.status = 'posted'
    ), 0)
  )::bigint AS effective_obligation,
  COALESCE((
    SELECT SUM(pa.amount)
    FROM payment_allocation pa
    WHERE pa.charge_id = c.id AND pa.status = 'posted'
  ), 0)::bigint AS allocated_total,
  (
    c.amount
    + COALESCE((
        SELECT SUM(fa.amount_delta)
        FROM financial_adjustment fa
        WHERE fa.charge_id = c.id AND fa.status = 'posted'
      ), 0)
    - COALESCE((
        SELECT SUM(pa.amount)
        FROM payment_allocation pa
        WHERE pa.charge_id = c.id AND pa.status = 'posted'
      ), 0)
  )::bigint AS outstanding_balance
FROM charge c
WHERE c.status <> 'void';

COMMENT ON VIEW charge_balance IS
  'Derived charge settlement read model. outstanding_balance = effective_obligation - allocated_total.';

ALTER VIEW public.charge_balance SET (security_invoker = true);

REVOKE ALL ON TABLE public.charge_balance FROM anon;
GRANT SELECT ON public.charge_balance TO authenticated;

-- =============================================================================
-- INTERNAL HELPERS
-- =============================================================================

CREATE OR REPLACE FUNCTION public._resolve_payer_name_snapshot(
  p_guardian_id uuid,
  p_student_id uuid,
  p_override text
)
RETURNS text
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_name text;
BEGIN
  IF p_override IS NOT NULL AND btrim(p_override) <> '' THEN
    RETURN btrim(p_override);
  END IF;

  IF p_student_id IS NOT NULL THEN
    SELECT btrim(coalesce(s.given_name, '') || ' ' || coalesce(s.family_name, ''))
      INTO v_name
    FROM student s WHERE s.id = p_student_id;
    IF v_name IS NOT NULL AND btrim(v_name) <> '' THEN
      RETURN btrim(v_name);
    END IF;
  END IF;

  SELECT btrim(coalesce(g.given_name, '') || ' ' || coalesce(g.family_name, ''))
    INTO v_name
  FROM guardian g WHERE g.id = p_guardian_id;

  RETURN NULLIF(btrim(v_name), '');
END;
$$;

CREATE OR REPLACE FUNCTION public._payment_allocation_status(p_payment_id uuid)
RETURNS text
LANGUAGE sql
STABLE
AS $$
  SELECT CASE
    WHEN p.status <> 'posted' THEN p.status
    WHEN public.payment_allocated_amount(p.id) = 0 THEN 'unallocated'
    WHEN public.payment_allocated_amount(p.id) < p.amount THEN 'partially_allocated'
    ELSE 'fully_allocated'
  END
  FROM payment p
  WHERE p.id = p_payment_id;
$$;

CREATE OR REPLACE FUNCTION public._charge_collection_status(p_charge_id uuid)
RETURNS text
LANGUAGE sql
STABLE
AS $$
  SELECT CASE
    WHEN c.status = 'void' THEN 'void'
    WHEN cb.outstanding_balance <= 0 THEN 'paid'
    WHEN cb.outstanding_balance < cb.effective_obligation THEN 'partially_paid'
    WHEN c.due_date IS NOT NULL AND c.due_date < CURRENT_DATE THEN 'overdue'
    ELSE 'unpaid'
  END
  FROM charge c
  JOIN charge_balance cb ON cb.charge_id = c.id
  WHERE c.id = p_charge_id;
$$;

CREATE OR REPLACE FUNCTION public._build_payment_details(p_payment_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_payment payment%ROWTYPE;
  v_allocated bigint;
  v_allocations jsonb;
BEGIN
  SELECT * INTO v_payment
  FROM payment
  WHERE id = p_payment_id AND organization_id = public.current_organization_id();

  IF NOT FOUND THEN
    RAISE EXCEPTION 'payment_not_found' USING ERRCODE = 'P0002';
  END IF;

  v_allocated := public.payment_allocated_amount(p_payment_id);

  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'allocation_id', pa.id,
      'charge_id', pa.charge_id,
      'amount', pa.amount,
      'status', pa.status,
      'allocated_at', pa.allocated_at
    ) ORDER BY pa.allocated_at
  ), '[]'::jsonb) INTO v_allocations
  FROM payment_allocation pa
  WHERE pa.payment_id = p_payment_id;

  RETURN jsonb_build_object(
    'payment_id', v_payment.id,
    'organization_id', v_payment.organization_id,
    'guardian_id', v_payment.guardian_id,
    'student_id', v_payment.student_id,
    'amount', v_payment.amount,
    'currency_code', v_payment.currency_code,
    'paid_at', v_payment.paid_at,
    'method_code', v_payment.method_code,
    'reference_number', v_payment.reference_number,
    'payer_name_snapshot', v_payment.payer_name_snapshot,
    'notes', v_payment.notes,
    'status', v_payment.status,
    'allocation_status', public._payment_allocation_status(p_payment_id),
    'allocated_amount', v_allocated,
    'unallocated_amount', v_payment.amount - v_allocated,
    'idempotency_key', v_payment.idempotency_key,
    'reversed_at', v_payment.reversed_at,
    'reversal_of_payment_id', v_payment.reversal_of_payment_id,
    'created_at', v_payment.created_at,
    'created_by', v_payment.created_by,
    'allocations', v_allocations
  );
END;
$$;

CREATE OR REPLACE FUNCTION public._insert_payment_allocations(
  p_payment_id uuid,
  p_allocations jsonb,
  p_batch_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_item jsonb;
  v_charge_id uuid;
  v_amount bigint;
  v_org uuid;
BEGIN
  v_org := public.current_organization_id();

  IF p_allocations IS NULL OR jsonb_typeof(p_allocations) <> 'array' THEN
    RETURN '[]'::jsonb;
  END IF;

  FOR v_item IN SELECT value FROM jsonb_array_elements(p_allocations)
  LOOP
    v_charge_id := (v_item->>'charge_id')::uuid;
    v_amount := (v_item->>'amount')::bigint;

    IF v_amount IS NULL OR v_amount <= 0 THEN
      RAISE EXCEPTION 'invalid_allocation_amount' USING ERRCODE = 'P0001';
    END IF;

    INSERT INTO payment_allocation (
      organization_id, payment_id, charge_id, amount, allocation_batch_id, status
    ) VALUES (
      v_org, p_payment_id, v_charge_id, v_amount, p_batch_id, 'posted'
    );
  END LOOP;

  RETURN public._build_payment_details(p_payment_id)->'allocations';
END;
$$;

-- =============================================================================
-- RPC: RECORD PAYMENT
-- =============================================================================

CREATE OR REPLACE FUNCTION public.record_payment(
  p_guardian_id uuid,
  p_amount bigint,
  p_paid_at timestamptz DEFAULT now(),
  p_method_code text DEFAULT 'cash',
  p_reference_number text DEFAULT NULL,
  p_notes text DEFAULT NULL,
  p_student_id uuid DEFAULT NULL,
  p_payer_name_snapshot text DEFAULT NULL,
  p_idempotency_key text DEFAULT NULL,
  p_allocations jsonb DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org uuid;
  v_payment_id uuid;
  v_currency text;
  v_existing payment%ROWTYPE;
  v_payer_snapshot text;
BEGIN
  IF NOT public.is_active_app_user() OR NOT public.has_permission('payment.record') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_org := public.current_organization_id();

  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'invalid_payment_amount' USING ERRCODE = 'P0001';
  END IF;

  IF p_method_code IS NULL OR p_method_code NOT IN ('cash', 'bank_transfer', 'card', 'other') THEN
    RAISE EXCEPTION 'invalid_payment_method' USING ERRCODE = 'P0001';
  END IF;

  IF p_idempotency_key IS NOT NULL AND btrim(p_idempotency_key) <> '' THEN
    SELECT * INTO v_existing
    FROM payment
    WHERE organization_id = v_org AND idempotency_key = btrim(p_idempotency_key);

    IF FOUND THEN
      RETURN public._build_payment_details(v_existing.id);
    END IF;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM guardian g
    WHERE g.id = p_guardian_id AND g.organization_id = v_org
  ) THEN
    RAISE EXCEPTION 'guardian_not_found' USING ERRCODE = 'P0002';
  END IF;

  IF p_student_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM student s
    WHERE s.id = p_student_id AND s.organization_id = v_org
  ) THEN
    RAISE EXCEPTION 'student_not_found' USING ERRCODE = 'P0002';
  END IF;

  SELECT o.currency_code INTO v_currency FROM organization o WHERE o.id = v_org;
  v_payer_snapshot := public._resolve_payer_name_snapshot(
    p_guardian_id, p_student_id, p_payer_name_snapshot
  );

  INSERT INTO payment (
    organization_id,
    guardian_id,
    student_id,
    amount,
    currency_code,
    paid_at,
    method_code,
    reference_number,
    notes,
    payer_name_snapshot,
    idempotency_key,
    status,
    created_by
  ) VALUES (
    v_org,
    p_guardian_id,
    p_student_id,
    p_amount,
    v_currency,
    COALESCE(p_paid_at, now()),
    p_method_code,
    NULLIF(btrim(p_reference_number), ''),
    NULLIF(btrim(p_notes), ''),
    v_payer_snapshot,
    NULLIF(btrim(p_idempotency_key), ''),
    'posted',
    public.current_app_user_id()
  )
  RETURNING id INTO v_payment_id;

  IF p_allocations IS NOT NULL AND jsonb_array_length(p_allocations) > 0 THEN
    PERFORM public._insert_payment_allocations(v_payment_id, p_allocations, NULL);
  END IF;

  RETURN public._build_payment_details(v_payment_id);
END;
$$;

-- =============================================================================
-- RPC: ALLOCATE PAYMENT
-- =============================================================================

CREATE OR REPLACE FUNCTION public.allocate_payment(
  p_payment_id uuid,
  p_allocations jsonb,
  p_operation_key text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org uuid;
  v_payment payment%ROWTYPE;
  v_batch_id uuid;
  v_total_requested bigint := 0;
  v_item jsonb;
  v_unallocated bigint;
BEGIN
  IF NOT public.is_active_app_user() OR NOT public.has_permission('payment.record') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_org := public.current_organization_id();

  SELECT * INTO v_payment
  FROM payment
  WHERE id = p_payment_id AND organization_id = v_org
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'payment_not_found' USING ERRCODE = 'P0002';
  END IF;

  IF v_payment.status <> 'posted' THEN
    RAISE EXCEPTION 'payment_not_allocatable' USING ERRCODE = 'P0001';
  END IF;

  IF p_allocations IS NULL OR jsonb_typeof(p_allocations) <> 'array' OR jsonb_array_length(p_allocations) = 0 THEN
    RAISE EXCEPTION 'allocations_required' USING ERRCODE = 'P0001';
  END IF;

  IF p_operation_key IS NOT NULL AND btrim(p_operation_key) <> '' THEN
    SELECT b.id INTO v_batch_id
    FROM payment_allocation_batch b
    WHERE b.organization_id = v_org AND b.operation_key = btrim(p_operation_key);

    IF FOUND THEN
      RETURN public._build_payment_details(p_payment_id);
    END IF;
  END IF;

  FOR v_item IN SELECT value FROM jsonb_array_elements(p_allocations)
  LOOP
    v_total_requested := v_total_requested + (v_item->>'amount')::bigint;
  END LOOP;

  v_unallocated := v_payment.amount - public.payment_allocated_amount(p_payment_id);

  IF v_total_requested > v_unallocated THEN
    RAISE EXCEPTION 'allocation_exceeds_unallocated' USING ERRCODE = 'P0001';
  END IF;

  IF p_operation_key IS NOT NULL AND btrim(p_operation_key) <> '' THEN
    INSERT INTO payment_allocation_batch (
      organization_id, payment_id, operation_key, created_by
    ) VALUES (
      v_org, p_payment_id, btrim(p_operation_key), public.current_app_user_id()
    )
    RETURNING id INTO v_batch_id;
  END IF;

  PERFORM public._insert_payment_allocations(p_payment_id, p_allocations, v_batch_id);

  RETURN public._build_payment_details(p_payment_id);
END;
$$;

-- =============================================================================
-- RPC: SUGGEST ALLOCATION
-- =============================================================================

CREATE OR REPLACE FUNCTION public.suggest_payment_allocation(
  p_payment_id uuid,
  p_enrollment_id uuid DEFAULT NULL,
  p_student_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org uuid;
  v_payment payment%ROWTYPE;
  v_remaining bigint;
  v_suggestions jsonb := '[]'::jsonb;
  v_rec record;
  v_apply bigint;
BEGIN
  IF NOT public.is_active_app_user() OR NOT public.has_permission('payment.read') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_org := public.current_organization_id();

  SELECT * INTO v_payment
  FROM payment
  WHERE id = p_payment_id AND organization_id = v_org;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'payment_not_found' USING ERRCODE = 'P0002';
  END IF;

  v_remaining := v_payment.amount - public.payment_allocated_amount(p_payment_id);

  IF v_remaining <= 0 THEN
    RETURN jsonb_build_object(
      'payment_id', p_payment_id,
      'unallocated_amount', 0,
      'suggestions', '[]'::jsonb
    );
  END IF;

  FOR v_rec IN
    SELECT
      c.id AS charge_id,
      c.due_date,
      cb.outstanding_balance
    FROM charge c
    JOIN charge_balance cb ON cb.charge_id = c.id
    WHERE c.organization_id = v_org
      AND c.status IN ('open', 'partially_paid')
      AND cb.outstanding_balance > 0
      AND c.currency_code = v_payment.currency_code
      AND (
        p_enrollment_id IS NULL OR c.enrollment_id = p_enrollment_id
      )
      AND (
        p_student_id IS NULL OR c.student_id = p_student_id
      )
    ORDER BY c.due_date NULLS LAST, c.charged_at, c.created_at
  LOOP
    EXIT WHEN v_remaining <= 0;

    v_apply := LEAST(v_remaining, v_rec.outstanding_balance);

    v_suggestions := v_suggestions || jsonb_build_array(jsonb_build_object(
      'charge_id', v_rec.charge_id,
      'amount', v_apply,
      'due_date', v_rec.due_date,
      'outstanding_balance', v_rec.outstanding_balance
    ));

    v_remaining := v_remaining - v_apply;
  END LOOP;

  RETURN jsonb_build_object(
    'payment_id', p_payment_id,
    'unallocated_amount', v_payment.amount - public.payment_allocated_amount(p_payment_id),
    'suggestions', v_suggestions
  );
END;
$$;

-- =============================================================================
-- RPC: REVERSE PAYMENT / ALLOCATION
-- =============================================================================

CREATE OR REPLACE FUNCTION public.reverse_payment(
  p_payment_id uuid,
  p_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org uuid;
  v_payment payment%ROWTYPE;
BEGIN
  IF NOT public.is_active_app_user() OR NOT public.has_permission('payment.reverse') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_org := public.current_organization_id();

  SELECT * INTO v_payment
  FROM payment
  WHERE id = p_payment_id AND organization_id = v_org
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'payment_not_found' USING ERRCODE = 'P0002';
  END IF;

  IF v_payment.status <> 'posted' THEN
    RAISE EXCEPTION 'payment_not_reversible' USING ERRCODE = 'P0001';
  END IF;

  UPDATE payment_allocation
  SET status = 'void', reversed_at = now()
  WHERE payment_id = p_payment_id AND status = 'posted';

  UPDATE payment
  SET status = 'reversed',
      reversed_at = now(),
      notes = COALESCE(NULLIF(btrim(p_notes), ''), notes)
  WHERE id = p_payment_id;

  RETURN public._build_payment_details(p_payment_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.reverse_payment_allocation(
  p_allocation_id uuid,
  p_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org uuid;
  v_allocation payment_allocation%ROWTYPE;
BEGIN
  IF NOT public.is_active_app_user() OR NOT public.has_permission('payment.reverse') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_org := public.current_organization_id();

  SELECT * INTO v_allocation
  FROM payment_allocation
  WHERE id = p_allocation_id AND organization_id = v_org
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'allocation_not_found' USING ERRCODE = 'P0002';
  END IF;

  IF v_allocation.status <> 'posted' THEN
    RAISE EXCEPTION 'allocation_not_reversible' USING ERRCODE = 'P0001';
  END IF;

  UPDATE payment_allocation
  SET status = 'void',
      reversed_at = now(),
      notes = COALESCE(NULLIF(btrim(p_notes), ''), notes)
  WHERE id = p_allocation_id;

  RETURN public._build_payment_details(v_allocation.payment_id);
END;
$$;

-- =============================================================================
-- RPC: GET PAYMENT DETAILS
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_payment_details(p_payment_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_active_app_user() OR NOT public.has_permission('payment.read') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  RETURN public._build_payment_details(p_payment_id);
END;
$$;

-- =============================================================================
-- RPC: ENROLLMENT OUTSTANDING CHARGES
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_enrollment_outstanding_charges(p_enrollment_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org uuid;
  v_charges jsonb;
BEGIN
  IF NOT public.is_active_app_user() OR NOT public.has_permission('charge.read') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_org := public.current_organization_id();

  IF NOT EXISTS (
    SELECT 1 FROM enrollment e
    WHERE e.id = p_enrollment_id AND e.organization_id = v_org
  ) THEN
    RAISE EXCEPTION 'enrollment_not_found' USING ERRCODE = 'P0002';
  END IF;

  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'charge_id', c.id,
      'amount', c.amount,
      'due_date', c.due_date,
      'charged_at', c.charged_at,
      'status', c.status,
      'collection_status', public._charge_collection_status(c.id),
      'effective_obligation', cb.effective_obligation,
      'allocated_total', cb.allocated_total,
      'outstanding_balance', cb.outstanding_balance
    ) ORDER BY c.due_date NULLS LAST, c.created_at
  ), '[]'::jsonb) INTO v_charges
  FROM charge c
  JOIN charge_balance cb ON cb.charge_id = c.id
  WHERE c.enrollment_id = p_enrollment_id
    AND c.organization_id = v_org
    AND c.status <> 'void'
    AND cb.outstanding_balance > 0;

  RETURN jsonb_build_object(
    'enrollment_id', p_enrollment_id,
    'charges', v_charges
  );
END;
$$;

-- =============================================================================
-- UPDATE ENROLLMENT FINANCIAL SUMMARY
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_enrollment_financial_summary(p_enrollment_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_terms enrollment_financial_terms%ROWTYPE;
  v_student_id uuid;
  v_billing_guardian_id uuid;
  v_scheduled bigint;
  v_charged bigint;
  v_adjustments bigint;
  v_allocated bigint;
  v_outstanding bigint;
  v_unapplied bigint;
BEGIN
  IF NOT public.is_active_app_user() OR NOT public.has_permission('charge.read') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_org_id := public.current_organization_id();

  SELECT e.student_id INTO v_student_id
  FROM enrollment e
  WHERE e.id = p_enrollment_id AND e.organization_id = v_org_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'enrollment_not_found' USING ERRCODE = 'P0002';
  END IF;

  SELECT * INTO v_terms
  FROM enrollment_financial_terms
  WHERE enrollment_id = p_enrollment_id
    AND organization_id = v_org_id
    AND status = 'active'
  LIMIT 1;

  SELECT public.resolve_enrollment_billing_guardian_id(p_enrollment_id)
    INTO v_billing_guardian_id;

  SELECT COALESCE(SUM(si.amount), 0) INTO v_scheduled
  FROM enrollment_payment_schedule_item si
  JOIN enrollment_financial_terms t ON t.id = si.enrollment_financial_terms_id
  WHERE t.enrollment_id = p_enrollment_id
    AND t.organization_id = v_org_id
    AND t.status = 'active'
    AND si.status = 'scheduled';

  SELECT COALESCE(SUM(c.amount), 0) INTO v_charged
  FROM charge c
  WHERE c.enrollment_id = p_enrollment_id
    AND c.organization_id = v_org_id
    AND c.charge_source_code = 'tuition'
    AND c.status <> 'void';

  SELECT COALESCE(SUM(fa.amount_delta), 0) INTO v_adjustments
  FROM financial_adjustment fa
  JOIN charge c ON c.id = fa.charge_id
  WHERE c.enrollment_id = p_enrollment_id
    AND c.organization_id = v_org_id
    AND fa.status = 'posted';

  SELECT COALESCE(SUM(pa.amount), 0) INTO v_allocated
  FROM payment_allocation pa
  JOIN charge c ON c.id = pa.charge_id
  WHERE c.enrollment_id = p_enrollment_id
    AND c.organization_id = v_org_id
    AND c.status <> 'void'
    AND pa.status = 'posted';

  SELECT COALESCE(SUM(cb.outstanding_balance), 0) INTO v_outstanding
  FROM charge_balance cb
  JOIN charge c ON c.id = cb.charge_id
  WHERE c.enrollment_id = p_enrollment_id
    AND cb.organization_id = v_org_id;

  IF v_billing_guardian_id IS NOT NULL THEN
    SELECT COALESCE(SUM(
      p.amount - public.payment_allocated_amount(p.id)
    ), 0) INTO v_unapplied
    FROM payment p
    WHERE p.organization_id = v_org_id
      AND p.status = 'posted'
      AND p.guardian_id = v_billing_guardian_id
      AND (p.student_id IS NULL OR p.student_id = v_student_id)
      AND p.amount > public.payment_allocated_amount(p.id);
  ELSE
    v_unapplied := 0;
  END IF;

  RETURN jsonb_build_object(
    'enrollment_id', p_enrollment_id,
    'active_terms_id', v_terms.id,
    'net_tuition', COALESCE(v_terms.net_tuition_amount, 0),
    'scheduled_amount', v_scheduled,
    'charged_amount', v_charged,
    'adjustments_amount', v_adjustments,
    'allocated_amount', v_allocated,
    'cash_allocated_to_enrollment', v_allocated,
    'outstanding_amount', v_outstanding,
    'outstanding_receivable', v_outstanding,
    'unapplied_payment_amount', v_unapplied,
    'recognized_revenue', NULL
  );
END;
$$;

-- =============================================================================
-- RLS: ALLOCATION BATCH
-- =============================================================================

ALTER TABLE payment_allocation_batch ENABLE ROW LEVEL SECURITY;
ALTER TABLE payment_allocation_batch FORCE ROW LEVEL SECURITY;

CREATE POLICY payment_allocation_batch_select ON payment_allocation_batch FOR SELECT TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('payment.read'));

CREATE POLICY payment_allocation_batch_insert ON payment_allocation_batch FOR INSERT TO authenticated
  WITH CHECK (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('payment.record'));

-- =============================================================================
-- GRANTS
-- =============================================================================

GRANT SELECT, INSERT ON payment_allocation_batch TO authenticated;

GRANT EXECUTE ON FUNCTION public.charge_effective_obligation(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.charge_allocated_amount(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.payment_allocated_amount(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_payment(uuid, bigint, timestamptz, text, text, text, uuid, text, text, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.allocate_payment(uuid, jsonb, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.suggest_payment_allocation(uuid, uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reverse_payment(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reverse_payment_allocation(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_payment_details(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_enrollment_outstanding_charges(uuid) TO authenticated;
