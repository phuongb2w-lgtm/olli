-- M0-T04: Protect historical charge amounts from silent mutation.

CREATE OR REPLACE FUNCTION public.protect_charge_amount()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF OLD.amount IS DISTINCT FROM NEW.amount THEN
    RAISE EXCEPTION 'Charge amount is immutable; use financial_adjustment for corrections';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER charge_protect_amount
  BEFORE UPDATE OF amount ON charge
  FOR EACH ROW EXECUTE FUNCTION public.protect_charge_amount();
