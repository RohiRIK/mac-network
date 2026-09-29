#!/usr/bin/env bash
# Local pre-PR gate: tests + release bundle. Writes a Markdown report to build/check-report.md
# for posting on the PR (`scripts/pr-report.sh`). Exit code is non-zero if any step fails.
set -uo pipefail
cd "$(dirname "$0")/.."

mkdir -p build
readonly REPORT="build/check-report.md"
status=0

step() {  # step <name> <command...>
  local name="$1"; shift
  local log; log="$(mktemp)"
  local start=$SECONDS
  if "$@" >"$log" 2>&1; then
    echo "| $name | ✅ pass | $((SECONDS - start))s |" >>"$REPORT.rows"
  else
    status=1
    echo "| $name | ❌ fail | $((SECONDS - start))s |" >>"$REPORT.rows"
  fi
  { echo "<details><summary>$name output</summary>"; echo; echo '```'; tail -40 "$log"; echo '```'; echo "</details>"; echo; } >>"$REPORT.logs"
  rm -f "$log"
}

rm -f "$REPORT" "$REPORT.rows" "$REPORT.logs"
step "Unit tests (scripts/test.sh)" scripts/test.sh
step "Release bundle (scripts/bundle.sh)" scripts/bundle.sh
step "Info.plist lint" plutil -lint Resources/Info.plist

{
  echo "## Local checks"
  echo
  echo "Commit \`$(git rev-parse --short HEAD)\` · $(sw_vers -productName) $(sw_vers -productVersion) · $(swift --version 2>&1 | head -1 | sed 's/.*Apple Swift version \([0-9.]*\).*/Swift \1/')"
  echo
  echo "| Step | Result | Time |"
  echo "|---|---|---|"
  cat "$REPORT.rows"
  echo
  cat "$REPORT.logs"
} >"$REPORT"
rm -f "$REPORT.rows" "$REPORT.logs"

cat "$REPORT" | head -12
exit "$status"
