#!/usr/bin/env node
/**
 * M5-T08: reporting period compare param parsing (form hidden compare=0 + checkbox compare=1).
 */

function parseReportingCompareParam(compareParam, defaultWhenAbsent = true) {
  const values = Array.isArray(compareParam)
    ? compareParam
    : compareParam != null
      ? [compareParam]
      : [];
  if (values.includes("1")) return true;
  if (values.includes("0")) return false;
  return defaultWhenAbsent;
}

function assert(name, condition) {
  if (!condition) {
    console.error(`FAIL: ${name}`);
    process.exitCode = 1;
    return;
  }
  console.log(`PASS: ${name}`);
}

assert("default when absent", parseReportingCompareParam(undefined) === true);
assert("explicit off", parseReportingCompareParam("0") === false);
assert("explicit on", parseReportingCompareParam("1") === true);
assert("form submit off", parseReportingCompareParam(["0"]) === false);
assert("form submit on", parseReportingCompareParam(["0", "1"]) === true);

if (process.exitCode) {
  process.exit(process.exitCode);
}
