#!/usr/bin/env bash
# Runs, before a push, what GitHub's CI runs (.github/workflows/ci.yml), on the commit being
# pushed: the unit tests, serial and unsigned, then the signed cold-launch smoke test.
#
# Why a clean worktree: the checks passed here while CI failed, because ignored files
# (Config/Local.xcconfig) and a warm working copy satisfied them. The commit is checked out
# into one persistent worktree under .git, so SwiftPM and the build products stay warm between
# pushes while the sources are exactly what the push carries.
set -euo pipefail

root=$(git rev-parse --show-toplevel)
worktree="$(git rev-parse --git-common-dir)/prepush-worktree"
derived="$HOME/Library/Developer/Xcode/DerivedData/prepush"

if [ -d "$worktree" ]; then
  git -C "$worktree" checkout -q --detach --force "$(git -C "$root" rev-parse HEAD)"
  git -C "$worktree" clean -qfdx -e SourcePackages
else
  git worktree add -q --detach "$worktree" HEAD
fi
cd "$worktree"

udid=$(xcrun simctl list devices available -j \
  | python3 -c "import json,sys; d=json.load(sys.stdin)['devices']; print([x['udid'] for k,v in sorted(d.items()) if 'iOS' in k for x in v if x['name'].startswith('iPhone')][-1])")

echo "pre-push 1/2 · unit tests, serial and unsigned"
xcodebuild test \
  -project SHARPIT-APP.xcodeproj -scheme SHARPIT-APP \
  -destination "id=$udid" -derivedDataPath "$derived" \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO \
  | grep -E "error:|✘|Test run with|TEST (SUCCEEDED|FAILED)" | tee /dev/stderr | grep -q "TEST SUCCEEDED"

echo "pre-push 2/2 · cold-launch smoke test"
xcodebuild build \
  -project SHARPIT-APP.xcodeproj -scheme SHARPIT-APP \
  -destination "id=$udid" -derivedDataPath "$derived" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER= \
  | grep -E "error:|BUILD (SUCCEEDED|FAILED)" | tee /dev/stderr | grep -q "BUILD SUCCEEDED"
scripts/smoke-launch.sh "$udid" "$derived/Build/Products/Debug-iphonesimulator/SharpIt.app"
echo "pre-push: all green"
