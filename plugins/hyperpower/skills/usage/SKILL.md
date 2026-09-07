---
name: usage
description: Report what the harness did - run counts, stage pass rates, fix-loop round distribution, gate failure counts by gate, assumption verified/refuted/unresolved ratio, median run duration. Reads .hyperpower/runs/*/usage.jsonl and the step contracts beside it. No money and no token prices - that is /hyperpower:cost. Use /hyperpower:usage, with --since <7d|30d|all> and --by <stage|agent|model|run>.
---

# Usage

Report what the harness did. Read the run journal. Report nothing that is not in it.

This skill is read only. It never writes to a run folder and never replays a step.

## The rule

Every number comes from a record in `.hyperpower/runs/<run-id>/usage.jsonl`, or from an
`assumptions` array in a `<step>.json` in the same folder.

A stage with no record either did not run or was not recorded. Report which one. Never
guess between them.

## Flags

| Flag | Values | Default |
|---|---|---|
| `--since` | `7d`, `30d`, `all` | `7d` |
| `--by` | `stage`, `agent`, `model`, `run` | `stage` |

`--since` filters on the record `ts`, not on the run folder mtime. A run that started
before the window keeps the records that fall inside it.

## Step 1 - read the records

One JSON object per line.

| Field | Holds |
|---|---|
| `ts` | ISO 8601 UTC timestamp of the call |
| `stage` | pipeline stage, or `gate:<name>` for a gate result |
| `agent` | agent role that made the call |
| `model` | model id |
| `input_tokens`, `output_tokens`, `cache_read` | token counts. Absent on gate records. |
| `duration_ms` | wall clock for that call |
| `outcome` | `ok`, or a failure string |

A record whose `stage` starts with `gate:` is a gate result. It carries no token counts.
Never count it as a model call.

`ok` is the only pass value. Treat every other `outcome` as not-pass, and list the distinct
failure strings, top five by count. Do not map them onto a vocabulary the recorder does not
use. Skip a malformed line, count it, and print the count. Do not drop it silently.

## Step 2 - compute the metrics

| Metric | Computed as |
|---|---|
| Run count | run folders holding at least one record inside the window |
| Stage pass rate | per stage, records with `outcome: ok` over all records for that stage |
| Fix-loop rounds | per run, count of model-call records with `stage: fix` |
| Gate failures | per gate name, records `stage: gate:<name>` with `outcome` other than `ok` |
| Assumption ratio | `status` values across the run's `<step>.json` assumption arrays |
| Median run duration | per run, last `ts` minus first `ts`, then the median across runs |

Do not sum `duration_ms` to get a run duration. Fan-out runs calls in parallel, so the sum
overstates wall clock, often by three times. Use the timestamp span.

One assumption id appears in more than one step contract: declared at plan, stamped at gate
time. Take the status from the latest step in pipeline order. Counting every occurrence
inflates the `declared` bucket.

## Step 3 - group

`--by` selects the group column: `stage` (gates listed separately as `gate:<name>`),
`agent`, `model`, or `run` newest first.

Every grouping prints the same four columns: calls, pass rate, median call duration, share
of calls. Divide totals by totals. Never average per-run rates.

## Output

```
Usage - last 7 days, 14 runs

  Gate failure rate     18%   (11 of 62 gate runs)
  Fix-loop rounds       1.4 median, 3 max
  Stage pass rate       91%   (204 of 224 calls)
  Assumptions           38 declared: 29 verified, 4 refuted, 5 unresolved
  Median run duration   6m 40s

By stage
  stage         calls   pass    median
  understand       14   100%       12s
  plan             14    93%       48s
  build            31    87%     2m 10s
  review           28    96%       31s
  fix               9    78%     1m 05s

Fix-loop rounds per task
  0 rounds    8 runs
  1 round     4 runs
  2 rounds    1 run
  3 rounds    1 run

Gate failures
  gate:unit     6 of 14
  gate:types    3 of 14
  gate:lint     2 of 14
```

Print the assumption line even when every assumption verified. Its absence reads as zero
assumptions, which is a different fact.

## Interpretation

Two numbers matter: gate failure rate, and fix-loop rounds per task.

| Pattern | Means | Do |
|---|---|---|
| Both rising | the rulebook has drifted from the codebase | `/hyperpower:init --refresh` |
| Cost rising, neither rising | paying for stages that are not earning it | `/hyperpower:cost --by stage` |
| Gate failures rising alone | one gate is newly broken, not the rulebook | `/hyperpower:doctor` |

Do not call a trend from fewer than ten runs in the window. Print the numbers and say the
sample is small.

## Missing data

| Case | Do |
|---|---|
| `.hyperpower/runs/` missing | report that no runs are recorded. Stop. Do not create it. |
| run folder with no `usage.jsonl` | count the folder, report it as unrecorded, exclude it from every rate |
| `telemetry.enabled` is false | say recording is off, then report what was recorded before it was |
| window has no records | report zero runs and the date of the newest record on disk |
| no `hyperpower.yml` | use the defaults below. Do not ask the user to create one. |

## Config

If `hyperpower.yml` exists at the repo root, read `limits.fix_loop_max_rounds` for the
histogram width and `telemetry.redact_paths` for output. Without it, use 5 rounds and treat
redaction as on.

Records carry no file paths, so redaction usually has nothing to do here. When a failure
string contains one and `redact_paths` is true, hash it as `/hyperpower:telemetry` describes.

## Do not

- Do not print money or token prices. That is `/hyperpower:cost`.
- Do not read source files, git history, or the diff. The journal is the only input.
- Do not write to `.hyperpower/`. This command records nothing.
- Do not report a stage as passing when it has no records.
- Do not report a gate as run when only the model calls around it were recorded.
