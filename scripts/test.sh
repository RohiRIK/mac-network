#!/usr/bin/env bash
# swift test that also works with Command Line Tools only (no Xcode):
# CLT ships Testing.framework but not on the default search path.
set -euo pipefail
cd "$(dirname "$0")/.."

# Keep SwiftPM build cache out of Google Drive (hundreds of MB, constant churn).
readonly SCRATCH="$HOME/Library/Caches/macplugins/$(basename "$PWD")"

readonly CLT="/Library/Developer/CommandLineTools/Library/Developer"
if [[ "$(xcode-select -p)" == /Library/Developer/CommandLineTools* ]]; then
  exec swift test --scratch-path "$SCRATCH" \
    -Xswiftc -F -Xswiftc "$CLT/Frameworks" \
    -Xlinker -F -Xlinker "$CLT/Frameworks" \
    -Xlinker -rpath -Xlinker "$CLT/Frameworks" \
    -Xlinker -rpath -Xlinker "$CLT/usr/lib" "$@"
fi
exec swift test --scratch-path "$SCRATCH" "$@"
