import "server-only";

import { createClient } from "@supabase/supabase-js";
import type { Database } from "@/types/database";

function requireSecretKey(): string {
  const key = process.env.SUPABASE_SECRET_KEY;
  if (!key) {
    throw new Error("SUPABASE_SECRET_KEY is not configured");
  }
  return key;
}

/** Server-only Supabase client with Auth Admin privileges. Never import from client components. */
export function createAdminClient() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  if (!url) {
    throw new Error("NEXT_PUBLIC_SUPABASE_URL is not configured");
  }

  return createClient<Database>(url, requireSecretKey(), {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
      detectSessionInUrl: false,
    },
  });
}
