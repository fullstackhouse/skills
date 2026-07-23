#!/usr/bin/env bash
# Run a Playwright spec multiple times and emit a JSON report for flake analysis.
#
# Usage:
#   flake-run.sh <spec-path> <runs> <workers> <out-dir>
#
# Run this from the Playwright project root (the directory containing
# playwright.config.{ts,js}). <spec-path> is relative to that directory.
#
# If the consuming repo ships its own flake-runner, prefer that — it likely
# encodes project-specific launch details (env vars, a non-default config path,
# a custom dev server). This bundled copy is the portable fallback: it shells
# out to `npx playwright test`, so it works in any repo with Playwright on PATH.
#
# Exits 0 regardless of test pass/fail — caller inspects <out-dir>/results.json
# (Playwright's JSON reporter output) to compute pass/fail counts and fingerprints.

set -uo pipefail

SPEC="${1:?spec path (relative to the Playwright project root) required}"
RUNS="${2:?runs count required}"
WORKERS="${3:?workers count required}"
OUT_DIR="${4:?output directory required}"

mkdir -p "$OUT_DIR"
OUT_DIR_ABS="$(cd "$OUT_DIR" && pwd)"

PLAYWRIGHT_JSON_OUTPUT_NAME="$OUT_DIR_ABS/results.json" \
  npx playwright test \
    "$SPEC" \
    --repeat-each="$RUNS" \
    --workers="$WORKERS" \
    --reporter=list,json \
    --output="$OUT_DIR_ABS/test-results" || true

if [ ! -f "$OUT_DIR_ABS/results.json" ]; then
  echo "::error::Playwright did not produce results.json at $OUT_DIR_ABS/results.json" >&2
  exit 1
fi

COUNT_JS='const r=require(process.argv[1]); let p=0,f=0; function walk(s){for(const sp of s.suites||[]){walk(sp);} for(const t of s.specs||[]){for(const test of t.tests||[]){for(const res of test.results||[]){if(res.status==="passed")p++; else if(res.status==="failed"||res.status==="timedOut")f++;}}}} for(const s of r.suites||[])walk(s); console.log(process.argv[2]==="f"?f:p);'

PASSED=$(node -e "$COUNT_JS" "$OUT_DIR_ABS/results.json" p)
FAILED=$(node -e "$COUNT_JS" "$OUT_DIR_ABS/results.json" f)

echo ""
echo "flake-run summary: passed=$PASSED failed=$FAILED runs=$RUNS workers=$WORKERS spec=$SPEC"
echo "Results JSON: $OUT_DIR_ABS/results.json"

exit 0
