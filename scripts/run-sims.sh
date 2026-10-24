#!/bin/zsh
# Build once and run the app on several simulators side by side, so each
# change can be checked on iPhone Duo, a regular iPhone and an iPad at once.
#
#   scripts/run-sims.sh                 # default devices below
#   scripts/run-sims.sh "iPhone 17"     # or name your own
#
# Extra environment for the app (e.g. START_TAB=1) is passed through as
# SIMCTL_CHILD_* variables:  SIMCTL_CHILD_START_TAB=1 scripts/run-sims.sh
set -euo pipefail

cd "$(dirname "$0")/.."

BUNDLE_ID=com.shadetracemap.shadetracemap
DERIVED=build/dd
APP=$DERIVED/Build/Products/Debug-iphonesimulator/ShadeTraceMap.app

if (( $# )); then
    DEVICES=("$@")
else
    DEVICES=("iPhone Duo" "iPhone 18 Pro" "iPad Pro 13-inch (M5) (16GB)")
fi

echo "==> Building"
xcodebuild -project ShadeTraceMap.xcodeproj -scheme ShadeTraceMap \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "$DERIVED" -quiet build

for name in "${DEVICES[@]}"; do
    echo "==> $name"
    xcrun simctl boot "$name" 2>/dev/null || true   # already booted is fine
    xcrun simctl terminate "$name" "$BUNDLE_ID" 2>/dev/null || true
    xcrun simctl install "$name" "$APP"
    xcrun simctl launch "$name" "$BUNDLE_ID" >/dev/null
done

open -a DeviceHub
echo "==> Running on: ${(j:, :)DEVICES}"
