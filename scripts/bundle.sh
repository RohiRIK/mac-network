#!/usr/bin/env bash
# Build a release binary and wrap it in an ad-hoc signed .app bundle.
set -euo pipefail
cd "$(dirname "$0")/.."

# Keep SwiftPM build cache out of Google Drive (hundreds of MB, constant churn).
readonly SCRATCH="$HOME/Library/Caches/macplugins/$(basename "$PWD")"

readonly APP="MacNetwork"
swift build -c release --scratch-path "$SCRATCH" --product "$APP"
readonly BIN="$(swift build -c release --scratch-path "$SCRATCH" --show-bin-path)/$APP"
readonly OUT="build/$APP.app"

rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS"
cp "$BIN" "$OUT/Contents/MacOS/$APP"
cp Resources/Info.plist "$OUT/Contents/Info.plist"
codesign --force --sign - "$OUT"
echo "$OUT"
