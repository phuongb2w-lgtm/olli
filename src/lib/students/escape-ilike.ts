/** Escape user input for safe use inside PostgREST ilike patterns. */
export function escapeIlike(value: string): string {
  return value.replace(/[%_\\]/g, "\\$&");
}
