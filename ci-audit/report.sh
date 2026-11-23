#!/usr/bin/env bash
# Prints the CI audit (latency, wait / setup / run, critical path, flakes, minutes, cost) as
# computed by report.sql from the data fetch.sh pulled. Compare two windows to measure a change:
#
#   ci-audit/report.sh --after 2026-11-01 --before 2026-11-23   # before
#   ci-audit/report.sh --after 2026-11-23                       # after
#
# --rate is the runner's price in USD per minute (GitHub › Settings › Billing). The cost column
# reads 0 until it is given.
set -euo pipefail

after=1970-01-01
before=2999-01-01
workflow=CI
rate=0
fetch=yes
while [ $# -gt 0 ]; do
  case "$1" in
    --after) after=$2; shift 2 ;;
    --before) before=$2; shift 2 ;;
    --workflow) workflow=$2; shift 2 ;;
    --rate) rate=$2; shift 2 ;;
    --no-fetch) fetch=no; shift ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
done

cd "$(dirname "$0")/.."
[ "$fetch" = yes ] && ci-audit/fetch.sh

duckdb -no-agent -markdown \
  -cmd "SET VARIABLE after = '$after'; SET VARIABLE before = '$before'; SET VARIABLE workflow = '$workflow'; SET VARIABLE rate = $rate;" \
  < ci-audit/report.sql
