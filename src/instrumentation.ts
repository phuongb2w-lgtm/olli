export async function register() {
  if (process.env.NEXT_RUNTIME !== "nodejs") {
    return;
  }
  const { assertProductionAppEnv } = await import("@/lib/env/assert-production-app-env");
  assertProductionAppEnv();
}
