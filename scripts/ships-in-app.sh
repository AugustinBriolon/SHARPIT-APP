#!/usr/bin/env bash
# Says whether anything that ships in the app changed between two commits: prints "true" or
# "false". The TestFlight workflow uploads a build only when it did, so a commit that touches
# only CI, hooks, scripts or docs sends testers nothing.
#
# Usage: scripts/ships-in-app.sh <base> <head>
# No usable base (first upload, history rewritten) → "true": when in doubt, upload.
set -euo pipefail

base=${1:-}
head=${2:-HEAD}

if [ -z "$base" ] || ! files=$(git diff --name-only "$base" "$head" 2>/dev/null); then
  echo true
  exit 0
fi

# Everything ships except what is listed here.
if grep -qvE '^(\.github/|\.githooks/|ci-audit/|scripts/|docs/)|\.md$' <<<"$files"; then
  echo true
else
  echo false
fi
