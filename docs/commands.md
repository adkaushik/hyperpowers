# Commands

Twenty commands in six groups. Everything is namespaced `hyperpower:`, so nothing
collides with commands you already have.

## Setup

### `/hyperpower:init`

Set up the current repository. Detects the stack, asks at most six questions, writes
`hyperpower.yml`, generates the rulebook, verifies every gate.

Run once per repo. Safe to re-run — it reads the existing config and fills only gaps.

| Flag | Does |
|---|---|
| `--refresh` | regenerate the rulebook, keep the config |
| `--no-interview` | detection only, skip all questions |

### `/hyperpower:doctor`

Re-verify gates and tools. Reports what is broken and the exact fix.

Run after changing config, upgrading dependencies, or switching machines.

### `/hyperpower:config`

Print the effective config, field by field, with the file each value came from.

### `/hyperpower:paths`

Show which directories the harness may edit. Pass a list to change it.

```
/hyperpower:paths src/ packages/core/src/
```

## Run

### `/hyperpower:run "<requirement>"`

Drive one requirement through the pipeline: route, understand, plan, design, build, gates,
review, the bounded fix loop, render.

Opens a run journal under `.hyperpower/runs/<run-id>/`, validates every stage contract
before the next stage reads it, and stops hard on a blocking gate the fix loop cannot
clear. About twelve minutes on a `feature`-class run with a ten-file diff, about ninety
seconds on `trivial`.

Design is the only stage that waits for you. Everything else runs to completion or stops.

A blocking gate that could not run is a hard stop, not a pass.

### `/hyperpower:route "<requirement>"`

Classify a requirement into a task class and print the stages it would run.

Read-only. It writes no run folder, so use it to see what `/hyperpower:run` would do before
paying for it. When two classes fit it picks the heavier one and names both.

```
Route  ui-feature. The requirement adds a settings screen, which is rendered output a human reads.
       feature also fit. Picked ui-feature, the heavier one.
Stages understand, plan, design, build, gates, review, fix, render. Design waits for you.
```

### `/hyperpower:resume <run-id> --from <step>`

Invalidate that step and everything downstream, then replay.

Re-hashes the working tree first and reports drift before doing anything:

```
Resume run 4f2a from Gates.
  Understand   ok
  Plan         ok
  Build        DRIFTED — 3 files changed since this step
Re-run from Build instead? [build / gates-anyway / abort]
```

`gates-anyway` is available when your own edit was the fix. It is never the default.

### `/hyperpower:why <run-id>`

What the run decided, and why.

| Flag | Does |
|---|---|
| `--assumptions` | list assumptions with status: verified, refuted, unresolved |
| `--rejected` | options considered and dropped, with reasons |

Read the `refuted` list first. Those are assumptions that were wrong and shipped code
anyway.

### `/hyperpower:correct <run> <step> <id> "<text>" --scope <once|run|forever>`

Correct a recorded assumption.

| Scope | Applies to |
|---|---|
| `once` | this replay only |
| `run` | every remaining step in this run |
| `forever` | promoted into the rulebook, with a diff for you to approve |

If your correction contradicts code the harness can read, it says so once and then obeys.

## Memory

### `/hyperpower:decisions [query]`

Search the decision archive. Never loaded into context — this command is the only way it
gets read.

| Flag | Does |
|---|---|
| `--by <who>` | filter: `human`, `human_directed`, `agent_autonomous`, `agent_proposed_approved` |
| `--stale` | decisions whose `reversal_condition` is now true |

`--by agent_autonomous` is your audit list: decisions made without anyone asking you.

### `/hyperpower:rules`

Show the rulebook.

| Flag | Does |
|---|---|
| `--recent` | what the promoter added, and on what evidence |
| `--unused` | rules that have prevented nothing in the last 20 runs |

Run `--unused` before raising `limits.rulebook_max_rules`.

### `/hyperpower:gc`

Run the gardener. Compacts the archive. Marks stale decisions, merges near-duplicates,
folds superseded chains.

It does not delete anything except records that are superseded, about files that no longer
exist, and older than six months. Everything is in git, so a bad compaction is
recoverable.

## Suggestors

### `/hyperpower:scout`

Log opportunities noticed during the work — bug risks, tech debt, test gaps, perf, ux,
feature ideas. Writes `.hyperpower/backlog.jsonl` and a markdown view.

Every entry cites evidence from the actual work. No evidence, no entry.

Caps at three new entries per run. Repeats increment a counter instead of adding a row, so
`occurrences` becomes your priority order for free.

### `/hyperpower:janitor`

Log dependency and migration debt. Writes `.hyperpower/hygiene.jsonl`.

| Flag | Does |
|---|---|
| `--all` | whole repo instead of the current diff |

Runs the tools your repo already configures. It never installs one, and it never upgrades
anything.

## Analytics

### `/hyperpower:usage`

Run counts, stage pass rates, fix-loop round distribution, gate failure counts, assumption
verified/refuted ratio, median duration.

| Flag | Does |
|---|---|
| `--since <7d\|30d\|all>` | time window |
| `--by <stage\|agent\|model\|run>` | grouping |

Watch two numbers: gate failure rate, and fix-loop rounds per task. Both rising means the
rulebook has drifted from the codebase. Run `/hyperpower:init --refresh`.

### `/hyperpower:cost`

Tokens and money by stage, agent, model, or run. Cache reads shown separately, since they
dominate and are cheap.

| Flag | Does |
|---|---|
| `--since <window>` | time window |
| `--by <stage\|agent\|model\|run>` | grouping |

Prices come from `pricing.yml` with a `last_verified` date. Stale prices are labelled
stale rather than shown as fact.

### `/hyperpower:telemetry [status|off|on|purge]`

| Subcommand | Does |
|---|---|
| `status` | what is recorded and where |
| `off` / `on` | stop or start recording |
| `purge` | delete all recorded telemetry, report the file count |

Everything is local. See [analytics.md](analytics.md).

## Quality

### `/hyperpower:sweep`

Layer 2 slop sweep on the current diff. Catches what static analysis cannot: over-
abstraction, wrong-fit code, swallowed exceptions, comments explaining what instead of why,
invented helpers that duplicate existing ones.

### `/hyperpower:review`

Partition the diff into coherent slices, review each, then send a skeptic at every finding.

Findings come back as CONFIRMED (traced end to end) or PLAUSIBLE (undecidable from the code
alone). PLAUSIBLE findings are never dropped for want of a reproduction.

### `/hyperpower:eval`

Run the eval suite and print the release verdict.

| Flag | Does |
|---|---|
| `--baseline` | record the current scores as the baseline to beat |

A prompt change ships only when it has no blockers, correctness and safety are within 0.1
of baseline or better, and the weighted score beats baseline.

Fifteen stack-neutral cases ship. Add your own after a few real runs, written against work
you have read, then record the baseline with `--baseline`. Neither `init` nor this command
generates cases from your commit history: a case taken from a commit nobody reviewed is a
baseline nobody trusts, and every later comparison inherits it.

## Scripts

The commands above are what you type. Underneath, six executables in
`plugins/hyperpower/scripts/` do the mechanical work: config merging, journal writing,
contract validation, gate running, path redaction, and the plugin self-check. Skills and
agents call them instead of reimplementing any of it, so `/hyperpower:config` reports the
config a run actually used and `/hyperpower:resume` re-derives the cache key
`/hyperpower:run` wrote.

Python 3, standard library only. No third-party imports and no network access. You rarely
run them by hand, but they are the contract, so they are documented here.

### `hp-config`

Merge `hyperpower.yml` and `hyperpower.local.yml` and print the result.

```sh
hp-config              # the effective config, indented
hp-config --json       # the same, on one line
hp-config --source     # config, sources, overrides, unknown_keys, type_errors, hash
hp-config --hash       # the config hash alone, which is what meta.json records
```

Exit 0 printed, 1 a file did not parse, 78 no `hyperpower.yml`. It never guesses a config.

`--source` maps every dotted leaf to `hyperpower.yml`, `hyperpower.local.yml`, or
`default`. A list is one leaf, so a local list replaces the committed one whole.

### `hp-journal`

Write and read the run journal under `.hyperpower/runs/<run-id>/`. Every append is atomic,
so parallel agents can write the same run.

```sh
hp-journal new --task-class feature            # creates the folder, prints the run id
hp-journal step <run> plan --file plan.json    # write a step's output contract
hp-journal hash <run> plan --files a.ts,b.ts --prompt-file p.txt
hp-journal usage <run> --stage plan --model claude-opus-5 --input 900 --output 120
hp-journal mistake <run> --kind gate_failed --key generated-import-drift
hp-journal drift <run> --from gates            # per-step drift, in resume's format
hp-journal finish <run> --outcome ok
hp-journal list                                # recorded runs, newest first
hp-journal path latest                         # the folder for a run id
```

Exit 0 written, 1 bad input or a refused write, 78 no `hyperpower.yml`. `latest` is a valid
run id everywhere. Record shapes are in `plugins/hyperpower/scripts/JOURNAL.md`.

### `hp-validate`

Check a stage contract against its JSON Schema.

```sh
hp-validate build --file .hyperpower/runs/4f2a/build.json
hp-validate plan --stdin < plan.json
hp-validate --list      # the nine stages and their required fields
```

Exit 0 valid, 1 invalid, 2 usage error, 78 no schema for that stage. Anything but 0 is a
hard stop: the next stage never runs on an unvalidated contract. Every violation prints
with its JSON path, not just the first one.

The schemas are nine files in `plugins/hyperpower/schemas/`, one per stage boundary:
`route`, `understand`, `plan`, `design`, `build`, `gates`, `review`, `fix`, `render`. Every
one is Draft 2020-12 with `additionalProperties: false`, so a stage that invents a field
fails validation. Field lists are in `plugins/hyperpower/schemas/README.md`.

### `hp-gates`

Run every enabled gate and record the aggregate.

```sh
hp-gates --run <run> --files src/a.ts,src/b.ts --config config.json --json
hp-gates --only types --files src/a.ts --config config.json --json    # probe one gate
```

Exit 0 every enabled blocking gate passed, 1 a blocking gate failed or timed out, 78 a
blocking gate could not run, 2 hp-gates could not run at all. Results are `pass`, `fail`, and `did not run`; a did-not-run gate is never
counted as a pass and never fails the run, and the caller stops on it.

`--only` with no `--run` is a probe: it runs the gate, prints the result, and records
nothing, because a one-gate aggregate is not the run's gate result. A run that already
finished is never adopted by the fallback either. Pass `--run` to write into one anyway.

### `hp-redact`

Hash file paths in run records before they reach an aggregate view.

```sh
cat .hyperpower/runs/4f2a/usage.jsonl | hp-redact --stdin
hp-journal drift latest --json | hp-redact --stdin --explain
```

Reads JSON or JSONL on stdin, writes the same shape on stdout. A path becomes
`path:<8 hex>`, and a `file:line` citation keeps its line number: `src/a.ts:42` becomes
`path:9f2a1c04:42`. Gate names, step names, agent names, model ids, git shas, run ids,
config hashes, URLs and timestamps pass through whole.

Use it wherever `telemetry.redact_paths` applies: the aggregate views behind
`/hyperpower:usage` and `/hyperpower:cost`, and anything you paste elsewhere. It is a
read-side transform. Per-run journals keep real paths, because they already live inside the
repo they describe, so nothing here changes what `hp-journal` recorded.

With `telemetry.redact_paths` set to `false` it passes the input through unchanged and says
on stderr that every path in it is real. With no config it treats redaction as on.

The salt is `.hyperpower/redact-salt`, derived from the repo's root commit the first time
the script runs. Do not commit it. Deleting it changes every token, and aggregates from
before the change stop lining up with aggregates after.

Redaction is not anonymity. Anyone holding the repo and the salt can hash a path and
compare it.

### `hp-selfcheck`

Check the plugin against its own documentation. This is a contributor tool, not something a
user of the harness runs.

```sh
hp-selfcheck                    # 13 checks
hp-selfcheck --strict           # warnings are errors. Run this before a pull request.
hp-selfcheck --only task-classes
hp-selfcheck --fix              # repairs frontmatter, agent names, gate file modes only
hp-selfcheck --list-checks
```

Exit 0 clean, 1 findings. Each finding names the file, the line, and the repair. Checks
cover frontmatter, agent naming and dispatch, `docs/commands.md` against `skills/` in both
directions, gate scripts and their schema entries, placeholder markers, config fields
against the schema, the eval suite, model pricing, the agent index, and the task-class
vocabulary.

### `run_evals.py`

Validate, run, and score the eval suite. Documented in full in
`plugins/hyperpower/scripts/README.md`.

## Tests

`plugins/hyperpower/tests/run-tests` executes the kernel scripts and asserts on what they
print, write, and exit. This is a contributor tool. Using the harness never runs it.

```sh
./run-tests                    # every case in tests/cases/
./run-tests --only hp-gates    # the cases whose file name matches
./run-tests --verbose          # every assertion, and each case's own output
./run-tests --list             # the cases that would run, then stop
```

Exit 0 when every assertion passed. Exit 1 when any assertion failed, any case crashed, or
a case wrote inside the plugin repository. Each case runs in a fresh git repository under a
temporary directory with its own `HOME`, so a case never touches the repo it is testing.

Run it with `hp-selfcheck --strict` before opening a pull request. Selfcheck compares the
tree against the documentation. The suite runs the code.
