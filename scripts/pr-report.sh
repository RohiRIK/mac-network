#!/usr/bin/env bash
# Run the local gate and post the report as a comment on the current branch's PR,
# with preview renders from docs/previews/ embedded (commit and push them first).
# Posts even when checks fail, so the PR shows the truth; exits with the gate's status.
set -uo pipefail
cd "$(dirname "$0")/.."

scripts/check.sh >/dev/null
status=$?
readonly REPORT="build/check-report.md"
readonly REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
readonly SHA="$(git rev-parse HEAD)"

shopt -s nullglob
shots=(docs/previews/*.png)
if (( ${#shots[@]} )); then
  { echo; echo "## Preview renders"; echo
    echo "Rendered with Xcode \`RenderPreview\` (\`tools/render-previews.sh\`)."; echo
    for f in "${shots[@]}"; do
      echo "**$(basename "$f" .png)**"; echo
      echo "<img src=\"https://github.com/$REPO/blob/$SHA/$f?raw=true\" width=\"340\">"; echo
    done
  } >>"$REPORT"
fi
gh pr comment --body-file "$REPORT"
exit "$status"
