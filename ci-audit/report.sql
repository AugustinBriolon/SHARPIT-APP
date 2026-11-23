-- CI audit over ci-audit/data/*.jsonl (written by fetch.sh). Run through report.sh, which sets
-- the window (after/before), the workflow and the per-minute rate.
--
-- Definitions
--   latency   push → verdict: the last job's completed_at minus the run's created_at (GitHub
--             creates the run on the push), for runs that reached a verdict (success / failure).
--   wait      job started_at − created_at.
--   setup     job start → start of the first step that is not runner or toolchain preparation.
--   run       the rest of the job.
--   flake     a commit whose CI went red, then green with the same SHA.
--   minutes   GitHub bills each job rounded up to the minute.

CREATE TEMP TABLE runs AS
SELECT * FROM read_json_auto('ci-audit/data/runs.jsonl', format = 'newline_delimited')
WHERE created_at >= getvariable('after')::TIMESTAMPTZ AND created_at < getvariable('before')::TIMESTAMPTZ;

CREATE TEMP TABLE jobs AS
SELECT j.* FROM read_json_auto('ci-audit/data/jobs.jsonl', format = 'newline_delimited') j
JOIN runs r ON r.id = j.run_id;

CREATE TEMP TABLE setup_steps AS
SELECT unnest(['Set up job', 'Checkout', 'Select the newest Xcode', 'Pick a simulator',
  'Cache Swift packages', 'Restore Swift packages', 'Restore the compilation cache']) AS name;

CREATE TEMP TABLE job_times AS
SELECT run_id, name, conclusion,
  epoch(started - created) AS wait_s,
  epoch(coalesce(first_real, completed) - started) AS setup_s,
  epoch(completed - started) AS job_s
FROM (
  SELECT j.run_id, j.id, j.name, j.conclusion,
    any_value(j.created_at::TIMESTAMPTZ) AS created, any_value(j.started_at::TIMESTAMPTZ) AS started,
    any_value(j.completed_at::TIMESTAMPTZ) AS completed,
    min(s.started_at::TIMESTAMPTZ) FILTER (WHERE s.name NOT IN (SELECT name FROM setup_steps)) AS first_real
  FROM jobs j, unnest(j.steps) AS t(s)
  WHERE j.started_at IS NOT NULL AND j.completed_at IS NOT NULL AND j.conclusion IN ('success', 'failure')
  GROUP BY j.run_id, j.id, j.name, j.conclusion
);

-- The days the window really covers, so a month's minutes are scaled from data, not from the bounds.
CREATE TEMP TABLE span AS
SELECT greatest(epoch(max(created_at::TIMESTAMPTZ) - min(created_at::TIMESTAMPTZ)) / 86400, 1) AS days FROM runs;

.print '## PR latency (push → verdict), workflow'
SELECT getvariable('workflow') AS workflow, count(*) AS n,
  round(quantile_cont(latency_s, 0.5)) AS p50_s, round(quantile_cont(latency_s, 0.95)) AS p95_s
FROM (
  SELECT r.id, epoch(max(j.completed_at::TIMESTAMPTZ) - r.created_at::TIMESTAMPTZ) AS latency_s
  FROM runs r JOIN jobs j ON j.run_id = r.id
  WHERE r.name = getvariable('workflow') AND r.conclusion IN ('success', 'failure')
  GROUP BY r.id, r.created_at
);

.print '## Per job: wait / setup / run (seconds)'
SELECT r.name AS workflow, t.name AS job, count(*) AS n,
  round(quantile_cont(wait_s, 0.5)) AS wait_p50, round(quantile_cont(wait_s, 0.95)) AS wait_p95,
  round(quantile_cont(setup_s, 0.5)) AS setup_p50, round(quantile_cont(setup_s, 0.95)) AS setup_p95,
  round(quantile_cont(job_s - setup_s, 0.5)) AS run_p50, round(quantile_cont(job_s - setup_s, 0.95)) AS run_p95
FROM job_times t JOIN runs r ON r.id = t.run_id
GROUP BY ALL ORDER BY workflow, job;

.print '## Critical path: the job that finished each run last'
SELECT job, count(*) AS runs FROM (
  SELECT j.run_id, arg_max(j.name, j.completed_at::TIMESTAMPTZ) AS job
  FROM jobs j JOIN runs r ON r.id = j.run_id
  WHERE r.name = getvariable('workflow') AND j.completed_at IS NOT NULL
  GROUP BY j.run_id
) GROUP BY job ORDER BY runs DESC;

.print '## Slowest steps (seconds)'
SELECT s.name AS step, count(*) AS n,
  round(quantile_cont(epoch(s.completed_at::TIMESTAMPTZ - s.started_at::TIMESTAMPTZ), 0.5)) AS p50,
  round(quantile_cont(epoch(s.completed_at::TIMESTAMPTZ - s.started_at::TIMESTAMPTZ), 0.95)) AS p95
FROM jobs j JOIN runs r ON r.id = j.run_id, unnest(j.steps) AS t(s)
WHERE r.name = getvariable('workflow') AND s.started_at IS NOT NULL AND s.completed_at IS NOT NULL
  AND s.conclusion = 'success'
GROUP BY ALL ORDER BY p50 DESC LIMIT 8;

.print '## Truth'
SELECT
  (SELECT count(*) FROM (
     SELECT head_sha FROM runs WHERE name = getvariable('workflow') GROUP BY head_sha
     HAVING bool_or(conclusion = 'failure') AND bool_or(conclusion = 'success'))) AS flaky_shas,
  (SELECT count(DISTINCT head_sha) FROM runs WHERE name = getvariable('workflow')
     AND conclusion IN ('success', 'failure')) AS shas,
  (SELECT count(*) FROM runs WHERE name = getvariable('workflow') AND conclusion = 'failure') AS red_runs;

.print '## Runner minutes and cost (every workflow, scaled to 30 days)'
SELECT r.name AS workflow, coalesce(j.labels[1], '?') AS runner,
  sum(ceil(epoch(j.completed_at::TIMESTAMPTZ - j.started_at::TIMESTAMPTZ) / 60)) AS billed_min,
  round(sum(ceil(epoch(j.completed_at::TIMESTAMPTZ - j.started_at::TIMESTAMPTZ) / 60)) * 30
    / any_value(span.days)) AS min_per_30d,
  round(sum(ceil(epoch(j.completed_at::TIMESTAMPTZ - j.started_at::TIMESTAMPTZ) / 60)) * 30
    / any_value(span.days) * getvariable('rate'), 2) AS usd_per_30d
FROM jobs j JOIN runs r ON r.id = j.run_id, span
WHERE j.started_at IS NOT NULL AND j.completed_at IS NOT NULL
GROUP BY r.name, j.labels[1] ORDER BY billed_min DESC;
