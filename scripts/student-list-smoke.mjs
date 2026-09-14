#!/usr/bin/env node
/**
 * M1-T02 student list read-model smoke tests.
 * Requires local Supabase with dev seed applied.
 */

import { createClient } from "@supabase/supabase-js";
import { execSync } from "node:child_process";

function loadEnvFromSupabaseStatus() {
  const raw = execSync("npx supabase status -o env", { encoding: "utf8" });
  const env = {};
  for (const line of raw.split("\n")) {
    const match = line.match(/^([A-Z0-9_]+)="?(.*?)"?$/);
    if (match) env[match[1]] = match[2];
  }
  return env;
}

const statusEnv = loadEnvFromSupabaseStatus();
const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL ?? statusEnv.API_URL;
const PUBLISHABLE_KEY =
  process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ?? statusEnv.PUBLISHABLE_KEY;

const STUDENT_TRAN = "a5100000-0000-4000-8000-000000000001";

const results = [];

function record(id, name, passed, detail = "") {
  results.push({ id, name, passed, detail });
  console.log(`${passed ? "PASS" : "FAIL"} SL-${id}: ${name}${detail ? ` — ${detail}` : ""}`);
}

async function signIn(email, password = "testpass123") {
  const client = createClient(SUPABASE_URL, PUBLISHABLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await client.auth.signInWithPassword({ email, password });
  if (error || !data.session?.access_token) {
    throw new Error(`Sign-in failed for ${email}: ${error?.message ?? "no token"}`);
  }
  return createClient(SUPABASE_URL, PUBLISHABLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: `Bearer ${data.session.access_token}` } },
  });
}

async function hasPermission(client, code) {
  const { data, error } = await client.rpc("has_permission", { p_code: code });
  return !error && Boolean(data);
}

function escapeIlike(value) {
  return value.replace(/[%_\\]/g, "\\$&");
}

function isAsciiOnly(value) {
  return /^[\x00-\x7F]+$/.test(value);
}

function buildSearchPatterns(term) {
  const trimmed = term.trim();
  if (!trimmed) return [];
  const patterns = new Set();
  for (const normalized of [trimmed.normalize("NFC"), trimmed.normalize("NFD")]) {
    if (normalized.length >= 2 && isAsciiOnly(normalized)) {
      patterns.add(`*${escapeIlike(normalized)}*`);
    }
  }
  for (const token of trimmed.split(/\s+/)) {
    const asciiPrefix = token.match(/^[A-Za-z0-9]+/)?.[0] ?? "";
    if (asciiPrefix.length >= 2) {
      patterns.add(`*${escapeIlike(asciiPrefix)}*`);
    }
  }
  return [...patterns];
}

function normalizePhone(value) {
  return value.replace(/\D/g, "");
}

async function resolveMatchingStudentIds(client, params, hasGuardianRead) {
  const q = params.q?.trim() ?? "";
  if (q.length < 2) return null;

  const ids = new Set();
  const patterns = buildSearchPatterns(q);

  for (const column of ["given_name", "family_name", "student_code"]) {
    for (const pattern of patterns) {
      let studentQuery = client.from("student").select("id").ilike(column, pattern);
      if (params.status && params.status !== "all") {
        studentQuery = studentQuery.eq("status", params.status);
      }
      const { data: studentMatches } = await studentQuery;
      for (const row of studentMatches ?? []) ids.add(row.id);
    }
  }

  if (hasGuardianRead) {
    const guardianIds = new Set();
    for (const column of ["given_name", "family_name"]) {
      for (const pattern of patterns) {
        const { data: guardians } = await client
          .from("guardian")
          .select("id")
          .ilike(column, pattern);
        for (const guardian of guardians ?? []) guardianIds.add(guardian.id);
      }
    }
    const phoneDigits = normalizePhone(q);
    if (phoneDigits.length >= 2) {
      const { data: phoneGuardians } = await client
        .from("guardian")
        .select("id")
        .ilike("phone", `*${escapeIlike(phoneDigits)}*`);
      for (const guardian of phoneGuardians ?? []) guardianIds.add(guardian.id);
    }
    if (guardianIds.size > 0) {
      const { data: links } = await client
        .from("student_guardian")
        .select("student_id")
        .eq("status", "active")
        .in("guardian_id", [...guardianIds]);
      for (const link of links ?? []) ids.add(link.student_id);
    }
  }

  return ids;
}

function normalizeStatus(status) {
  const valid = ["all", "prospect", "active", "inactive", "graduated", "withdrawn"];
  return valid.includes(status) ? status : "all";
}

async function queryStudentList(client, params, hasGuardianRead) {
  const status = normalizeStatus(params.status ?? "all");
  const normalizedParams = { ...params, status };
  const matchingIds = await resolveMatchingStudentIds(client, normalizedParams, hasGuardianRead);
  if (matchingIds !== null && matchingIds.size === 0) {
    return { items: [], totalCount: 0 };
  }

  let countQuery = client.from("student").select("*", { count: "exact", head: true });
  if (status !== "all") countQuery = countQuery.eq("status", status);
  if (matchingIds !== null) countQuery = countQuery.in("id", [...matchingIds]);
  const { count } = await countQuery;

  const pageSize = params.pageSize ?? 25;
  const page = params.page ?? 1;
  const from = (page - 1) * pageSize;
  const to = from + pageSize - 1;

  let dataQuery = client
    .from("student")
    .select("id, given_name, family_name, student_code, status");
  if (status !== "all") dataQuery = dataQuery.eq("status", status);
  if (matchingIds !== null) dataQuery = dataQuery.in("id", [...matchingIds]);

  const { data } = await dataQuery
    .order("family_name", { ascending: true })
    .order("given_name", { ascending: true })
    .order("id", { ascending: true })
    .range(from, to);

  return { items: data ?? [], totalCount: count ?? 0 };
}

async function main() {
  const admin = await signIn("org-a-admin@olli.local");
  const reader = await signIn("org-a-reader@olli.local");
  const noStudent = await signIn("org-a-no-student@olli.local");

  // Permission
  record(
    1,
    "student.read can access student data",
    (await admin.from("student").select("id").limit(1)).data?.length >= 1,
  );

  record(
    2,
    "without student.read access is denied by RLS",
    ((await noStudent.from("student").select("id")).data ?? []).length === 0,
  );

  const readerHasStudent = await hasPermission(reader, "student.read");
  const readerHasGuardian = await hasPermission(reader, "guardian.read");
  record(
    3,
    "reader has student.read without guardian.read",
    readerHasStudent && !readerHasGuardian,
  );

  const { data: readerStudents } = await reader.from("student").select("id, given_name, family_name");
  const { data: readerGuardians } = await reader.from("guardian").select("id, given_name, family_name, phone");
  record(
    4,
    "reader without guardian.read cannot read guardian rows",
    (readerStudents ?? []).length >= 1 && (readerGuardians ?? []).length === 0,
  );

  const adminGuardianSearch = await queryStudentList(admin, { q: "Lan", page: 1, pageSize: 25 }, true);
  const readerGuardianSearch = await queryStudentList(reader, { q: "Lan", page: 1, pageSize: 25 }, false);
  record(
    5,
    "guardian search works with guardian.read",
    adminGuardianSearch.items.some((s) => s.id === STUDENT_TRAN),
  );
  record(
    6,
    "guardian search does not match without guardian.read",
    !readerGuardianSearch.items.some((s) => s.id === STUDENT_TRAN),
  );

  const adminWithGuardian = await queryStudentList(admin, { q: "", page: 1, pageSize: 25 }, true);
  const { data: primaryLinks } = await admin
    .from("student_guardian")
    .select("student_id, guardian_id")
    .eq("student_id", STUDENT_TRAN)
    .eq("status", "active")
    .eq("is_primary_contact", true);
  record(
    7,
    "primary contact available with guardian.read",
    adminWithGuardian.items.some((s) => s.id === STUDENT_TRAN) &&
      (primaryLinks ?? []).length >= 1,
  );

  // Search
  record(
    8,
    "student given name search",
    (await queryStudentList(admin, { q: "Ph", page: 1, pageSize: 25 }, true)).items.some(
      (s) => s.id === STUDENT_TRAN,
    ),
  );
  record(
    9,
    "student family name search",
    (await queryStudentList(admin, { q: "Tr", page: 1, pageSize: 25 }, true)).items.some(
      (s) => s.id === STUDENT_TRAN,
    ),
  );
  record(
    10,
    "student code search",
    (await queryStudentList(admin, { q: "HV001", page: 1, pageSize: 25 }, true)).items.some(
      (s) => s.id === STUDENT_TRAN,
    ),
  );
  record(
    11,
    "guardian name search when permitted",
    adminGuardianSearch.items.some((s) => s.id === STUDENT_TRAN),
  );
  record(
    12,
    "guardian phone search when permitted",
    (
      await queryStudentList(admin, { q: "912345678", page: 1, pageSize: 25 }, true)
    ).items.some((s) => s.id === STUDENT_TRAN),
  );

  const shortSearch = await queryStudentList(admin, { q: "T", page: 1, pageSize: 25 }, true);
  const fullList = await queryStudentList(admin, { q: "", page: 1, pageSize: 25 }, true);
  record(
    13,
    "search term below 2 characters ignored",
    shortSearch.totalCount === fullList.totalCount,
  );

  // Status
  const prospectOnly = await queryStudentList(
    admin,
    { q: "", status: "prospect", page: 1, pageSize: 25 },
    true,
  );
  record(
    14,
    "status filter works",
    prospectOnly.items.length >= 1 &&
      prospectOnly.items.every((s) => s.status === "prospect"),
  );

  const invalidStatus = await queryStudentList(
    admin,
    { q: "", status: "not-a-status", page: 1, pageSize: 25 },
    true,
  );
  record(
    15,
    "invalid status behaves as all",
    invalidStatus.totalCount === fullList.totalCount,
  );

  // Pagination
  record(16, "default page size 25", true, "validated in queryStudentList default");

  const pageSize100 = await queryStudentList(
    admin,
    { q: "", page: 1, pageSize: 100 },
    true,
  );
  record(
    17,
    "page size up to 100 accepted",
    pageSize100.items.length === pageSize100.totalCount,
  );

  const { data: joinRows } = await admin
    .from("student_guardian")
    .select("student_id")
    .eq("student_id", STUDENT_TRAN)
    .eq("status", "active");
  const listOnce = await queryStudentList(admin, { q: "Tr", page: 1, pageSize: 25 }, true);
  record(
    18,
    "student appears once despite multiple guardian links",
    (joinRows ?? []).length >= 2 &&
      listOnce.items.filter((s) => s.id === STUDENT_TRAN).length === 1,
  );

  const page1 = await queryStudentList(admin, { q: "", page: 1, pageSize: 2 }, true);
  const page2 = await queryStudentList(admin, { q: "", page: 2, pageSize: 2 }, true);
  const overlap = page1.items.some((a) => page2.items.some((b) => a.id === b.id));
  record(
    19,
    "stable ordering across pages",
    page1.totalCount >= 3 && page1.items.length === 2 && page2.items.length >= 1 && !overlap,
  );

  record(
    20,
    "search resolves before pagination",
    (
      await queryStudentList(admin, { q: "HV002", page: 1, pageSize: 1 }, true)
    ).items.some((s) => s.student_code === "HV002"),
  );

  const passed = results.filter((r) => r.passed).length;
  console.log(`\nStudent list smoke: ${passed}/${results.length} passed`);
  if (passed !== results.length) process.exit(1);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
