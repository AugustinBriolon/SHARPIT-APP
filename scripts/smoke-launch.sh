#!/bin/bash
# Cold-launches the built app several times and fails if it does not stay up. A launch crash
# that unit tests never reach (APPLE-IOS-4, a main-actor callback trapping a second after
# launch) died on every cold launch here.
#
# Usage: scripts/smoke-launch.sh <simulator-udid> <path/to/SharpIt.app> [launches] [seconds]
set -euo pipefail

UDID="$1"
APP="$2"
LAUNCHES="${3:-5}"
HOLD="${4:-10}"
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP/Info.plist")

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl install "$UDID" "$APP"

for launch in $(seq 1 "$LAUNCHES"); do
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl launch "$UDID" "$BUNDLE_ID" >/dev/null
  sleep "$HOLD"
  # Read the list whole first: `grep -q` closing the pipe early would fail it under pipefail.
  RUNNING=$(xcrun simctl spawn "$UDID" launchctl list)
  if ! grep -q "$BUNDLE_ID" <<<"$RUNNING"; then
    echo "Launch $launch: $BUNDLE_ID is gone after ${HOLD}s. Its last words:"
    xcrun simctl spawn "$UDID" log show --last 1m --style compact \
      --predicate "process == \"SharpIt\" AND (messageType == fault OR eventMessage CONTAINS \"BUG IN CLIENT\" OR eventMessage CONTAINS \"Fatal error\")" \
      | tail -20 || true
    exit 1
  fi
  echo "Launch $launch: up after ${HOLD}s"
done
