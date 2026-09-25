const LOCAL_SUPABASE_URL_PATTERNS = [
  /^https?:\/\/127\.0\.0\.1/i,
  /^https?:\/\/localhost/i,
  /^http:\/\/127\.0\.0\.1:54421/i,
];

export function isLocalSupabaseUrl(url: string | undefined): boolean {
  if (!url?.trim()) return false;
  return LOCAL_SUPABASE_URL_PATTERNS.some((pattern) => pattern.test(url.trim()));
}

export function parseSupabaseCloudProjectRef(url: string | undefined): string | null {
  if (!url?.trim()) return null;
  try {
    const host = new URL(url.trim()).hostname;
    const match = host.match(/^([a-z0-9]+)\.supabase\.co$/i);
    return match ? match[1] : null;
  } catch {
    return null;
  }
}

export function assertCloudSupabasePublicUrl(url: string | undefined, label = "NEXT_PUBLIC_SUPABASE_URL"): string {
  if (!url?.trim()) {
    throw new Error(`${label} is not configured`);
  }
  if (isLocalSupabaseUrl(url)) {
    throw new Error(`${label} must not point at local Supabase in this environment (${url})`);
  }
  const ref = parseSupabaseCloudProjectRef(url);
  if (!ref) {
    throw new Error(`${label} must be a Supabase Cloud URL (https://<ref>.supabase.co)`);
  }
  return ref;
}
