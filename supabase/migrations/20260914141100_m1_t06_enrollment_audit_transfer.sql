-- M1-T06: Enrollment audit FKs and atomic transfer RPC (SECURITY INVOKER).

ALTER TABLE enrollment
  ADD CONSTRAINT enrollment_created_by_fk
  FOREIGN KEY (organization_id, created_by) REFERENCES app_user (organization_id, id),
  ADD CONSTRAINT enrollment_updated_by_fk
  FOREIGN KEY (organization_id, updated_by) REFERENCES app_user (organization_id, id);

CREATE OR REPLACE FUNCTION public.transfer_enrollment(
  p_source_enrollment_id uuid,
  p_destination_class_id uuid,
  p_destination_start_date date,
  p_destination_status text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_actor uuid;
  v_source enrollment%ROWTYPE;
  v_dest_class class%ROWTYPE;
  v_operational_count integer;
  v_new_id uuid;
  v_end_date date;
BEGIN
  IF NOT public.is_active_app_user() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  IF NOT public.has_permission('enrollment.update') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_org_id := public.current_organization_id();
  v_actor := public.current_app_user_id();

  SELECT * INTO v_source
  FROM enrollment
  WHERE id = p_source_enrollment_id
    AND organization_id = v_org_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found' USING ERRCODE = 'P0002';
  END IF;

  IF v_source.status NOT IN ('pending', 'active') THEN
    RAISE EXCEPTION 'invalid_status' USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO v_dest_class
  FROM class
  WHERE id = p_destination_class_id
    AND organization_id = v_org_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'invalid_class' USING ERRCODE = 'P0002';
  END IF;

  IF v_dest_class.status = 'closed' THEN
    RAISE EXCEPTION 'class_closed' USING ERRCODE = 'P0001';
  END IF;

  IF v_dest_class.capacity IS NOT NULL AND v_dest_class.capacity > 0 THEN
    SELECT count(*)::integer INTO v_operational_count
    FROM enrollment
    WHERE organization_id = v_org_id
      AND class_id = p_destination_class_id
      AND status IN ('pending', 'active');

    IF v_operational_count >= v_dest_class.capacity THEN
      RAISE EXCEPTION 'capacity_reached' USING ERRCODE = 'P0001';
    END IF;
  END IF;

  IF p_destination_status NOT IN ('pending', 'active') THEN
    RAISE EXCEPTION 'invalid_status' USING ERRCODE = 'P0001';
  END IF;

  IF p_destination_start_date IS NULL THEN
    RAISE EXCEPTION 'invalid_date' USING ERRCODE = 'P0001';
  END IF;

  v_end_date := GREATEST(v_source.start_date, p_destination_start_date);

  UPDATE enrollment
  SET
    status = 'transferred',
    end_date = COALESCE(end_date, v_end_date),
    updated_by = v_actor
  WHERE id = p_source_enrollment_id;

  INSERT INTO enrollment (
    organization_id,
    student_id,
    class_id,
    start_date,
    status,
    created_by,
    updated_by
  )
  VALUES (
    v_org_id,
    v_source.student_id,
    p_destination_class_id,
    p_destination_start_date,
    p_destination_status,
    v_actor,
    v_actor
  )
  RETURNING id INTO v_new_id;

  RETURN v_new_id;
EXCEPTION
  WHEN exclusion_violation THEN
    RAISE EXCEPTION 'overlap_conflict' USING ERRCODE = '23P01';
END;
$$;

GRANT EXECUTE ON FUNCTION public.transfer_enrollment(uuid, uuid, date, text) TO authenticated;
