-- M0-T04: Link Olli app_user to Supabase Auth identity.

ALTER TABLE app_user
  ADD COLUMN auth_user_id uuid UNIQUE REFERENCES auth.users (id) ON DELETE SET NULL;

CREATE INDEX idx_app_user_auth_user_id ON app_user (auth_user_id);

COMMENT ON COLUMN app_user.auth_user_id IS
  'Maps to auth.users.id. ON DELETE SET NULL preserves app_user and historical references when Auth account is removed.';
