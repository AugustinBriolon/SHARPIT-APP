#!/usr/bin/env bash
# Runs, before a push, the checks that gate it (scripts/check.sh: one signed build, the
# cold-launch smoke test, then the serial unit tests), on the commit being pushed. CI only builds
# (.github/workflows/ci.yml), so the tests and the launch run here and nowhere else.
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

# PREPUSH_SIMULATOR_UDID pins the device when the last iPhone of the list (a custom one, say) will
# not boot a test runner.
udid=${PREPUSH_SIMULATOR_UDID:-$(xcrun simctl list devices available -j \
  | python3 -c "import json,sys; d=json.load(sys.stdin)['devices']; print([x['udid'] for k,v in sorted(d.items()) if 'iOS' in k for x in v if x['name'].startswith('iPhone')][-1])")}

echo "pre-push 1/3 · one signed build"
scripts/check.sh build "$udid" "$derived"
echo "pre-push 2/3 · cold-launch smoke test"
scripts/check.sh launch "$udid" "$derived"
echo "pre-push 3/3 · unit tests, serial"
scripts/check.sh test "$udid" "$derived"
echo "pre-push: all green"
