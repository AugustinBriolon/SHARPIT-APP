#!/usr/bin/env bash
# The checks that gate main. The pre-push hook (scripts/pre-push.sh) runs all three; CI
# (.github/workflows/ci.yml) runs the build only, its runner being too small for a simulator:
#
#   scripts/check.sh build <udid> <derived-data>   one signed build for the tests and the launch
#   scripts/check.sh launch <udid> <derived-data>  cold-launch the app five times
#   scripts/check.sh test <udid> <derived-data>    the whole unit suite, serial
#
# Run them in that order. The launch comes before the tests: xcodebuild shuts the simulator down
# some time after a test run, and a launch caught in that shutdown failed a push with
# « Unable to lookup in current state: Shutting Down ».
set -euo pipefail

step=$1
udid=$2
derived=$3
cd "$(git rev-parse --show-toplevel)"

case "$step" in
  build)
    # An unsigned app dies at launch on Clerk's Keychain (-34018): the simulator reads the
    # entitlements linked into the binary, so a signature added afterwards is not enough. Sign to
    # run locally, as Xcode does. The compilation cache is content-addressed: an output is reused
    # only for the exact inputs that produced it.
    set -o pipefail
    xcodebuild build-for-testing \
      -project SHARPIT-APP.xcodeproj -scheme SHARPIT-APP \
      -destination "id=$udid" -derivedDataPath "$derived" \
      -showBuildTimingSummary \
      COMPILATION_CACHE_ENABLE_CACHING=YES COMPILER_INDEX_STORE_ENABLE=NO \
      CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER= \
      | tee xcodebuild.log | grep -E "error:|TEST BUILD (SUCCEEDED|FAILED)"
    sed -n '/Build Timing Summary/,/TEST BUILD/p' xcodebuild.log | head -25
    ;;
  launch)
    # Unit tests never cold-launch the app: a crash at launch only shows when it is opened.
    scripts/smoke-launch.sh "$udid" "$derived/Build/Products/Debug-iphonesimulator/SharpIt.app"
    ;;
  test)
    # Serial: parallel runners once killed the simulator mid-suite.
    set -o pipefail
    xcodebuild test-without-building \
      -project SHARPIT-APP.xcodeproj -scheme SHARPIT-APP \
      -destination "id=$udid" -derivedDataPath "$derived" \
      -parallel-testing-enabled NO \
      | perl -MPOSIX -pe 'BEGIN { $| = 1 } print strftime("%H:%M:%S ", gmtime)' \
      | tee tests.log | grep -E "error:|✘|Test run with|TEST EXECUTE (SUCCEEDED|FAILED)"
    ;;
  *)
    echo "usage: scripts/check.sh build|launch|test <udid> <derived-data>" >&2
    exit 2
    ;;
esac
