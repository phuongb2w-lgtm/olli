-- CW2-T02a: declaration draft enum value (separate migration — PG requires commit before use).

ALTER TYPE public.consultant_revenue_declaration_status ADD VALUE IF NOT EXISTS 'draft' BEFORE 'pending';

COMMENT ON TYPE public.consultant_revenue_declaration_status IS
  'Consultant declarations: draft (consultant-only) -> pending/submitted -> approved/returned/rejected. Not canonical cash or sales.';
