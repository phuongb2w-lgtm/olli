-- M0-T05: charge_balance invoker security, narrow helper RPC exposure.

-- Views default to SECURITY DEFINER (owner privileges) in PostgreSQL 15 unless
-- security_invoker is set. Force invoker so underlying charge/payment RLS applies.
ALTER VIEW public.charge_balance SET (security_invoker = true);

REVOKE ALL ON TABLE public.charge_balance FROM anon;

-- Helper functions: authenticated only (required for RLS policy evaluation and UX).
REVOKE EXECUTE ON FUNCTION public.current_app_user_id() FROM anon;
REVOKE EXECUTE ON FUNCTION public.current_organization_id() FROM anon;
REVOKE EXECUTE ON FUNCTION public.has_permission(text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.is_active_app_user() FROM anon;

-- Remove blanket function grant added in M0-T04; re-grant only intended helpers.
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM authenticated;

GRANT EXECUTE ON FUNCTION public.has_permission(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_active_app_user() TO authenticated;
GRANT EXECUTE ON FUNCTION public.current_app_user_id() TO authenticated;
GRANT EXECUTE ON FUNCTION public.current_organization_id() TO authenticated;

COMMENT ON VIEW public.charge_balance IS
  'Derived outstanding balance per charge. security_invoker=true — subject to underlying table RLS.';
