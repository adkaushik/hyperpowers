# Commands

Eighteen commands in six groups. Everything is namespaced `hyperpower:`, so nothing
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
