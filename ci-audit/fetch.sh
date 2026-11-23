#!/usr/bin/env bash
# Pulls the repository's workflow runs, and the jobs and steps of each, from the GitHub API into
# ci-audit/data/*.jsonl, the raw input of report.sql. Raw timestamps only: every number in the
# report is computed from them, never copied by hand.
#
# Usage: ci-audit/fetch.sh [days]   (default 42)
set -euo pipefail

days=${1:-42}
repo=${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}
data="$(cd "$(dirname "$0")" && pwd)/data"
since=$(date -u -v-"${days}"d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "-${days} days" +%Y-%m-%dT%H:%M:%SZ)
mkdir -p "$data"

gh api "repos/$repo/actions/runs?per_page=100&created=>=$since" --paginate \
  --jq '.workflow_runs[] | {id, name, event, status, conclusion, head_sha, head_branch, run_attempt,
        created_at, run_started_at, updated_at}' > "$data/runs.jsonl"

jq -r 'select(.status == "completed") | .id' "$data/runs.jsonl" \
  | xargs -P 8 -I{} gh api "repos/$repo/actions/runs/{}/attempts/1/jobs?per_page=100" \
      --jq '.jobs[] | {run_id, id, name, conclusion, created_at, started_at, completed_at, runner_name,
            labels, steps: [.steps[] | {number, name, conclusion, started_at, completed_at}]}' \
  > "$data/jobs.jsonl"

echo "Fetched $(wc -l < "$data/runs.jsonl" | tr -d ' ') runs and $(wc -l < "$data/jobs.jsonl" | tr -d ' ') jobs since $since"
