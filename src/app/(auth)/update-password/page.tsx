import { UpdatePasswordForm } from "@/components/update-password-form";
import { RecoveryLinkExpired } from "@/components/recovery-link-expired";
import { createClient } from "@/lib/supabase/server";

export default async function UpdatePasswordPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return <RecoveryLinkExpired />;
  }

  return <UpdatePasswordForm />;
}
