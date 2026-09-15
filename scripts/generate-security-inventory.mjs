#!/usr/bin/env node
/**
 * M0-T06: generate public schema security inventory from live local Supabase.
 * Writes docs/m0/32-security-surface-inventory.md
 */

import { execSync } from "node:child_process";
import { writeFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const outPath = join(root, "docs", "m0", "32-security-surface-inventory.md");

const sql = `
SELECT json_build_object(
  'generated_at', now()::text,
  'tables', (
    SELECT coalesce(json_agg(row_to_json(t) ORDER BY t.name), '[]'::json)
    FROM (
      SELECT c.relname AS name,
             c.relrowsecurity AS rls_enabled,
             c.relforcerowsecurity AS force_rls
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public' AND c.relkind = 'r'
    ) t
  ),
  'views', (
    SELECT coalesce(json_agg(row_to_json(v) ORDER BY v.name), '[]'::json)
    FROM (
      SELECT c.relname AS name,
             (SELECT option_value FROM pg_options_to_table(c.reloptions) o
              WHERE o.option_name = 'security_invoker') AS security_invoker
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public' AND c.relkind = 'v'
    ) v
  ),
  'functions', (
    SELECT coalesce(json_agg(row_to_json(f) ORDER BY f.name), '[]'::json)
    FROM (
      SELECT p.proname AS name,
             CASE p.prosecdef WHEN true THEN 'DEFINER' ELSE 'INVOKER' END AS security,
             pg_get_userbyid(p.proowner) AS owner,
             pg_get_function_identity_arguments(p.oid) AS args,
             (SELECT string_agg(option_value, ', ')
              FROM pg_options_to_table(p.proconfig) o
              WHERE o.option_name = 'search_path') AS search_path,
             EXISTS (
               SELECT 1 FROM pg_proc p2
               WHERE p2.oid = p.oid
                 AND has_function_privilege('anon', p.oid, 'EXECUTE')
             ) AS anon_execute,
             EXISTS (
               SELECT 1 FROM pg_proc p2
               WHERE p2.oid = p.oid
                 AND has_function_privilege('authenticated', p.oid, 'EXECUTE')
             ) AS authenticated_execute
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public'
        AND p.prokind = 'f'
        AND p.proname NOT LIKE '\\_%'
        AND p.proname IN (
          'current_app_user_id',
          'current_organization_id',
          'has_permission',
          'is_active_app_user',
          'set_own_preferred_locale',
          'protect_app_user_sensitive_fields',
          'protect_charge_amount',
          'set_updated_at',
          'initialize_organization_cost_groups',
          'seed_organization_cost_categories',
          'protect_cost_group_domain_code',
          'prevent_expense_category_reparent',
          'validate_expense_cost_group',
          'protect_completed_session_teacher',
          'validate_attendance_context',
          'validate_payment_allocations',
          'protect_finalized_assessment_result',
          'validate_teacher_user_org'
        )
    ) f
  )
) AS inventory;
`;

function runInventory() {
  const raw = execSync(
    `docker exec supabase_db_olli-local psql -U postgres -d postgres -t -A -c "${sql.replace(/"/g, '\\"').replace(/\n/g, " ")}"`,
    { cwd: root, encoding: "utf8" },
  ).trim();
  return JSON.parse(raw);
}

function tableMarkdown(rows) {
  if (!rows.length) return "_None_\n";
  const lines = [
    "| Object | RLS | FORCE RLS |",
    "|--------|-----|-----------|",
    ...rows.map(
      (r) => `| \`${r.name}\` | ${r.rls_enabled ? "yes" : "no"} | ${r.force_rls ? "yes" : "no"} |`,
    ),
  ];
  return lines.join("\n") + "\n";
}

function viewMarkdown(rows) {
  if (!rows.length) return "_None_\n";
  const lines = [
    "| View | security_invoker |",
    "|------|------------------|",
    ...rows.map((r) => `| \`${r.name}\` | ${r.security_invoker ?? "default"} |`),
  ];
  return lines.join("\n") + "\n";
}

function fnMarkdown(rows) {
  if (!rows.length) return "_None_\n";
  const lines = [
    "| Function | Security | Owner | search_path | anon EXECUTE | authenticated EXECUTE |",
    "|----------|----------|-------|-------------|--------------|----------------------|",
    ...rows.map(
      (r) =>
        `| \`${r.name}(${r.args})\` | ${r.security} | ${r.owner} | ${r.search_path ?? "—"} | ${r.anon_execute ? "yes" : "no"} | ${r.authenticated_execute ? "yes" : "no"} |`,
    ),
  ];
  return lines.join("\n") + "\n";
}

const inv = runInventory();
const md = `# M0-T06 — Public Schema Security Surface Inventory

**Generated:** ${inv.generated_at} (from live local Supabase)

This document is the M0 security baseline for regression comparison. Any future view exposed through the Data API must undergo explicit RLS / \`security_invoker\` review.

## Summary

| Category | Count |
|----------|------:|
| Tables | ${inv.tables.length} |
| Views | ${inv.views.length} |
| Custom functions | ${inv.functions.length} |

## Tables (${inv.tables.length})

${tableMarkdown(inv.tables)}

## Views (${inv.views.length})

${viewMarkdown(inv.views)}

## Custom Functions (${inv.functions.length})

${fnMarkdown(inv.functions)}

## Exposure Rules (M0)

- **anon:** no table SELECT/INSERT/UPDATE/DELETE; helper RPC EXECUTE revoked except where noted.
- **authenticated:** DML gated by RLS; narrow helper RPC grants only.
- **Normal users:** no hard DELETE policies in M0 foundation.
- **Future views:** must set \`security_invoker = true\` unless explicitly reviewed otherwise.

## Regeneration

\`\`\`powershell
npm run db:inventory
\`\`\`

Requires local Supabase running with migrations applied.
`;

writeFileSync(outPath, md, "utf8");
console.log(`Wrote ${outPath} (${inv.tables.length} tables, ${inv.views.length} views, ${inv.functions.length} functions)`);
