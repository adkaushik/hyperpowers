---
name: run
description: Drive one requirement through the hyperpower pipeline - route, understand, plan, design, build, gates, review, the bounded fix loop, render. Opens a run journal under .hyperpower/runs/, validates every stage contract before the next stage reads it, stops hard on a blocking gate the fix loop cannot clear, and triggers the background agents after Render. Use /hyperpower:run "<requirement>".
---

# Run

Drive one requirement through the pipeline. Stop hard on anything that cannot be verified.

Run is the driver. It executes stages, writes the journal, and owns the fix loop. It does
not implement, review, or adjudicate. Those are agents, and it spawns them.

About twelve minutes on a `feature`-class run with a ten-file diff. About ninety seconds on
`trivial`. Design adds an unbounded wait, because a human locks the mock.

## Kernel scripts

Four executables in `${CLAUDE_PLUGIN_ROOT}/scripts/`. Run calls them. It never parses
`hyperpower.yml` itself and never writes the journal with a shell redirect.

| Script | Called as | Exit codes |
|---|---|---|
| `hp-config` | `--json`, which prints the effective config on one line | 0 ok, 1 parse error, 78 no config |
| `hp-journal` | `new`, `hash`, `step`, `usage`, `mistake`, `finish` | 0 written, 1 refused, 78 no config |
| `hp-validate` | `hp-validate <step> --stdin`, or `--file <path>` | 0 valid, 1 invalid, 2 usage error, 78 no schema |
| `hp-gates` | `--run <id> --files a,b --route <r> --config <path> --json` | 0 no blocking failure, 1 blocking failure, 78 blocking gate could not run, 2 hp-gates itself could not run |

Write the config JSON to one file and pass it to `hp-gates --config`. Both then read the
same bytes, and the run records one config hash rather than two.

## Step 1 - preflight

Call `hp-config --json`. Read its exit code before its output.

| Exit | Do |
|---|---|
| 0 | keep the JSON in one file. Every later step reads that copy. |
| 78 | print `No hyperpower.yml. Run /hyperpower:init.` Stop. Write nothing. |
| 1 | print the file, the line number, and the parser error from stderr. Stop. |

Do not guess a config, and do not run a stage on defaults you invented. A repo with no
config gets one message and no run folder.

## Step 2 - route

Run the `route` skill with the requirement and the config you just loaded. It returns the
route contract: the task class, the ordered `stages` list, and the `tiers` map.

Route runs before the journal exists, because `hp-journal new --task-class` needs the class
route is about to pick, and nothing else can set that field afterwards. Route reads no
source and writes no file, so a run that stops here leaves no folder behind. Say why it
stopped.

Print the route lines. The human sees the class and the stage list before the work starts.

## Step 3 - open the run

```sh
hp-journal new --task-class <class>       # prints the run id
```

It creates `.hyperpower/runs/<run-id>/`, writes `meta.json` with the base sha, the config
hash, the model tiers, and the class, then prints the id. Hold that id in every later call.

Record the route contract straight away, with the three calls in step 4. Everything from
here writes to that folder.

## Step 4 - the stage loop

Execute the stages in `stages`, in that order. Every stage in `skipped` writes no step file,
and `/hyperpower:why` reports it as skipped. Never add a stage the contract did not name,
and never reorder the ones it did.

| Stage | Runs | Writes `<step>.json` |
|---|---|---|
| `understand` | `hyperpower:mapper`, read-only | run records it |
| `plan` | `hyperpower:planner` | run records it |
| `design` | `hyperpower:designer`, then the human locks the mock | run records it |
| `build` | `hyperpower:builder` | the builder writes it. Run records it anyway. |
| `gates` | `hp-gates`, then the assumption-stamping pass | `hp-gates` records it |
| `review` | the `review` skill: partition, reviewers, skeptics | the skill writes it. Run records it anyway. |
| `fix` | the fix loop in step 6 | run records it, one file per run |
| `render` | step 7 | run records it |

The builder writes `build.json` and the review skill writes `review.json` by hand, so
neither carries a cache key. Put both through the three calls below anyway. Without the key
`/hyperpower:resume` cannot detect drift on that step, and reports it as `UNHASHED`.

Pass `tiers.<stage>`, resolved to a model id through `models`, to every agent you spawn.
`hyperpower:mapper`, `hyperpower:planner`, `hyperpower:designer`, and `hyperpower:builder`
set `model: inherit`, so the tier you pass is the model that runs. The fix-loop escalation
below depends on that: the builder honours `tiers.fix`. `hyperpower:reviewer` and
`hyperpower:skeptic` pin `opus` in frontmatter, so record the model the call actually used
in `usage.jsonl` rather than the tier you asked for.

Spawn every agent by its namespaced name. A bare name silently resolves to a same-named
agent in the user's own `~/.claude/agents/`, which returns a contract this pipeline cannot
read.

### Recording a step - three calls, in this order

```sh
hp-journal hash <run> <step> --prompt-file <prompt> --files src/a.ts,src/b.ts --json
hp-validate <step> --stdin < contract.json
hp-journal step <run> <step> --stdin < contract.json
```

1. `hash` computes `prompt_hash` and the cache key from the prompt, the upstream contract,
   and the blob hash of every file the stage read, and stamps all three on the step file.
   With `--json` it prints that whole block; take the `prompt_hash` key out of it for the
   contract. Use `--files-from <file>` when a path holds a comma, and pass an empty file
   when the stage read nothing.
2. `hp-validate` checks the contract against `schemas/<step>.json`.
3. `step` writes the contract and keeps the `cache_key` already on disk.

Keep the `--json`. Without it `hash` prints the cache key on one line, not the prompt hash,
and a contract carrying the cache key in `prompt_hash` still validates, still records, and
makes `/hyperpower:resume` report drift on a step that never moved. `route` and `gates`
require `prompt_hash`; the other seven schemas do not, and a contract that omits it keeps
what `hash` already stamped.

Do not put `cache_key` on the contract you validate. `hp-journal hash` writes that field as
an object, and the schema does not accept it there. Do not compute the cache key yourself:
`/hyperpower:resume` re-derives it, and two writers would drift.

`hp-gates` runs all three calls for `gates` itself. Validate its output and leave the
recording to it.

### The step envelope

Every `<step>.json` carries these fields, whatever else the stage adds.

| Field | Holds |
|---|---|
| `step` | the stage name |
| `run_id` | the run folder name. Emit `null` and let `hp-journal step` stamp it. |
| `prompt_hash` | printed by `hp-journal hash` |
| `files_read` | every path the stage read, so resume can hash them |
| `assumptions` | the assumption array. Present even when empty. |
| `rejected` | options considered and dropped, as `{"option","reason"}` |
| `notes` | anything the next stage needs |

An absent `assumptions` array reads to `/hyperpower:why` as zero assumptions declared. Emit
`[]`, never nothing.

Each stage adds its own required fields on top of the envelope. Run `hp-validate --list` to
print them. Do not carry a field list in your head.

### An invalid contract is a hard stop

| `hp-validate` exit | Do |
|---|---|
| 0 | record the contract and continue |
| 1 | hard stop. Print the stage, the violations from stderr, and the run id. |
| 2 | hard stop. The flags were wrong, so nothing was checked. |
| 78 | hard stop. There is no schema for that step, so nothing was checked. |

A stage that cannot produce a valid contract is a hard stop, not a warning. Do not repair
the contract yourself. Do not continue on a partial one. Do not fall back to the stage's
prose output. The next stage would misread it, and the misreading is invisible.

On a hard stop: append a `mistakes.jsonl` line, run Render on what the journal holds, call
`hp-journal finish <run> --outcome failed`, and report.

### Record every model call

One line per model call, at the moment it returns.

```sh
hp-journal usage <run> --stage plan --agent planner --model claude-opus-5 \
  --input 18422 --output 1130 --cache-read 16000 --duration-ms 9400 --outcome ok
```

`--outcome` is `ok` on success and a short failure string otherwise. `/hyperpower:usage`
treats every value other than `ok` as not-pass, so do not write `ok` for a call that
returned a blocked status. Do not fold `--cache-read` into `--input`.

## Step 5 - gates

```sh
hp-gates --run <run> --files <changed,files> --config <config.json> --json
```

It runs every enabled gate, writes `gates.json` and one `gate:<name>` record per gate into
`usage.jsonl`, and prints the aggregate. Do not write `gates.json` yourself.

Read the per-gate records in the aggregate's `gates` array. Do not branch on the exit code
alone.

| `result` | `blocking` | Do |
|---|---|---|
| `pass` | either | continue |
| `fail`, `timed_out` false | `true` | enter the fix loop |
| `fail`, `timed_out` true | `true` | hard stop. The command never finished. Name `/hyperpower:doctor`. |
| `fail` | `false` | warning. Carry it into Render. Never a fix round. |
| `did_not_run` | `true` | hard stop. Name the gate, its `detail`, and `/hyperpower:doctor`. |
| `did_not_run` | `false` | warning. Carry it into Render. |

`hp-gates` exits 78 when a blocking gate could not run, and 0 only when every enabled blocking gate passed. A gate you disabled does
not change that exit code. A repo with no gate commands configured returns exit 0 with
`counts.did_not_run` equal to `counts.total`. The stop in row five is the caller's job, and
it is the reason gates fail closed. A `did_not_run` is never a pass. Never report a gate you
did not observe pass.

A timeout and a missing tool are both environment faults. Sending either to a builder makes
it chase a defect that may not exist.

Then run the assumption-stamping pass on `tiers.gates`. Re-read each declared assumption's
`checkable` target and move `status` to `verified`, `refuted`, or `unresolved`.

The stamped statuses go in the `assumptions` array of `gates.json`. `hp-gates` writes that
array empty, because it runs commands and adjudicates nothing. Record the stamped array by
reading `gates.json` back, dropping `recorded_at` and `cache_key`, putting every stamped
assumption in `assumptions`, and passing the whole aggregate through the usual two calls:

```sh
hp-validate gates --stdin < stamped.json
hp-journal step <run> gates --stdin < stamped.json
```

`hp-journal step` keeps the `prompt_hash`, `files_read` and `cache_key` `hp-gates` already
wrote, so the step stays hashed and `/hyperpower:resume` still sees it. Change nothing else:
the gate results, the counts and the exit code are `hp-gates` output, and this pass only
fills the array it left empty. This is the one write to `gates.json` that is not `hp-gates`,
and it is why "do not write `gates.json` yourself" above means do not compose the aggregate,
not do not stamp it.

`/hyperpower:why --assumptions` and `/hyperpower:usage` take an assumption's status from the
latest step in pipeline order. An assumption stamped nowhere reads as still `declared`, so a
refuted one never reaches the human.

Append one mistake per refuted assumption:

```sh
hp-journal mistake <run> --kind assumption_refuted --key settings-api-shape \
  --ref .hyperpower/runs/<run>/plan.json
```

No human is involved in this pass.

## Step 6 - the fix loop

Bounded. Read the ceiling from `limits.fix_loop_max_rounds`. Use 5 when the config omits it.

Enter on either: a blocking gate returned `fail`, or Review returned a `CONFIRMED` finding.

Do not enter on a `did_not_run`, a gate timeout, a non-blocking failure, or a `PLAUSIBLE`
finding. A `PLAUSIBLE` finding goes to Render for a human to decide.

| Round | Builder | Input carries |
|---|---|---|
| 1 through max minus 2 | the same builder, resumed. `builder: "same"` | the failure from the previous round only |
| the last two rounds | a fresh `hyperpower:builder`. `builder: "fresh"` | `round`, and `prior_attempts` with one entry per earlier round |
| after max | nothing. Hard stop. | |

At the default ceiling of 5 that is rounds 1 to 3 resumed, and rounds 4 and 5 fresh. At a
ceiling of 2 or less, every round is fresh.

The round's `builder` field takes `same` or `fresh` and nothing else. `resumed` is the
English for the first row, not a value the schema accepts.

Each round, in order:

1. Build the fix input: `task`, `files`, `acceptance`, `assumptions`, `round`,
   `prior_attempts`.
2. Spawn the builder on the model in `tiers.fix`.
3. Re-run `hp-gates` with `--files` set to the files this round changed.
4. Append one `hp-journal mistake` line per distinct failure.
5. Append one `hp-journal usage` record with `--stage fix`.
6. Rewrite `fix.json` with every round so far.

One `fix.json` per run, not one per round. It carries `status`, `rounds`, `findings_fixed`,
`findings_open`, and `max_rounds`. `status` is `done` or `blocked`. There is no third value,
and `fixed` is not one of them. One round entry:

```json
{"round":4,"builder":"fresh","model":"claude-opus-5","targets":["f1"],
 "approach":"typed the response before mapping it","changed_files":["src/api/settings.ts"],
 "result":"fail","failure":"gate:types exited 2, Settings[] has no property items"}
```

The builder's `prior_attempts` input is derived from this array: one entry per earlier round
carrying `round`, `approach`, and `failure`. Do not hand the builder the whole `fix.json`.

`findings_open` is every finding still open when the loop stopped. It is reported, never
dropped.

### mistakes.jsonl is the only thing the promoter reads

Every round appends, even a round that succeeded after failing. The promoter scans this file
and nothing else, and it counts distinct runs per `(kind, key)` pair.

```jsonl
{"run":"4f2a","kind":"gate_failed","key":"types-settings-bare-array","ref":".hyperpower/runs/4f2a/gates.json"}
{"run":"4f2a","kind":"finding_confirmed","key":"empty-response-map","ref":".hyperpower/runs/4f2a/review.json"}
```

`--kind` is one of `forever_correction`, `assumption_refuted`, `gate_failed`,
`finding_confirmed`. `--key` is a stable kebab-case slug describing the failure, not the run
and not the round. The same failure in a later run must produce the same key, or the
threshold never fires and the loop never closes. `--ref` must resolve, because the promoter
skips a candidate whose ref does not.

### The escalation the config cannot do

The design says rounds 4 and 5 use a fresh builder one model tier up. `hyperpower.yml` has
two tiers, `models.judgment` and `models.mechanical`. For every class except `trivial` and
`dependency`, build already runs on `models.judgment`. There is no tier above it.

What the harness actually does in rounds 4 and 5:

| Class | Round 4 and 5 build model | Real escalation |
|---|---|---|
| `trivial`, `dependency` | `models.judgment` | yes. `tiers.fix` is `judgment` while `tiers.build` is `mechanical`. |
| every other class | `models.judgment`, unchanged | no. The builder is fresh, the model is the same. |

For the second row the change is the context, not the model: a builder with no history of
the failed attempts, handed `prior_attempts` describing what each earlier round tried and
how it failed. Write the round's `builder` as `fresh` and its `model` as the model that
actually ran. The pair is the honest record.

Do not report an escalation that did not happen. Do not add a third tier to
`hyperpower.yml`. The schema has two, and inventing a third breaks `/hyperpower:config`.

### Round max failing is a hard stop

Write `fix.json` with `status: blocked` and every round. Run Render. Call
`hp-journal finish <run> --outcome blocked`. Report what each round tried.

Do not start another round. Do not lower the acceptance criteria. Do not weaken, skip, or
delete a test to end the loop. The loop reports; it never spins.

## Step 7 - render

This is the single boundary where machine output becomes human output. Everything before it
is agent-to-agent.

`render.json` records what the human saw and what the view left out. `view` is the rendered
text verbatim. `shaping` is the two `voice` flags as they were read. `sections` is one entry
per ranked list in the view, each carrying `title`, `shown`, `total`, and the `source`
contract file that holds the full list.

The full list never lives in `render.json`. It stays in the contract that produced it, and
`source` points at that file.

| Flag | True | False |
|---|---|---|
| `voice.adhd_shaping` | lead with the action, number multi-step work, restate state, suppress tangents, give specific time estimates, make wins visible, stay matter-of-fact on errors, no preamble and no recap and no closing pleasantry | no shaping |
| `voice.plain_english` | short sentences, subject-verb-object, no idioms, no metaphors, no wordplay, no rhetorical build-up | no voice rule |

Both false: write plainly anyway.

**Rank, never cap.** The cap-at-five rule applies to this view only. The view shows the top
five, then says how many remain and which file holds the rest. Record the same three numbers
in the matching `sections` entry, so a reader can check the view against the contract.

```
Run 4f2a  ui-feature, shipped in 11m. 12 files changed, 2 fix rounds.

Gates    types ok, unit ok, build ok, slop ok, lint warned
Review   7 findings, 5 CONFIRMED, 2 PLAUSIBLE
  CONFIRMED  high    src/api/settings.ts:34       204 response yields undefined, .map throws
  CONFIRMED  medium  src/hooks/useSettings.ts:12  cache key not updated after the rename
  PLAUSIBLE  high    src/pay/webhook.ts:88        depends on the payments API error shape
  +4 more. Full list in .hyperpower/runs/4f2a/review.json.

Assumptions  4 declared: 1 refuted, 1 unresolved, 2 verified
  REFUTED  a1  settings API returns a bare array

Next
  2 PLAUSIBLE findings need your decision. Run /hyperpower:why 4f2a --assumptions.
```

Print the assumption tally even when every assumption verified. Its absence reads as zero
assumptions declared.

Never apply either rule set to a builder input, a reviewer input, a skeptic input, a step
contract, or a findings list that has not reached this stage. Capping a findings list at
five before Render silently drops findings, and nothing in the output shows the drop.

## Step 8 - finish, then the background plane

1. `hp-journal finish <run> --outcome <o>`. The four values are `ok`, `failed`, `blocked`,
   and `aborted`.
2. Spawn `hyperpower:archivist` with the run id, unless `memory.archivist` is `false`.
3. Spawn `hyperpower:promoter` after the archivist returns, unless `memory.promoter` is
   `false`. Order matters. The promoter counts what the archivist wrote.
4. Run the `scout` skill, capped at `limits.scout_max_new_per_run`.
5. Run the `janitor` skill, capped at `limits.janitor_max_new_per_run`.

| Outcome | Use when |
|---|---|
| `ok` | every blocking gate passed and the fix loop cleared, or never ran |
| `blocked` | the fix loop hit `limits.fix_loop_max_rounds` and still failed |
| `failed` | an invalid contract, or a blocking gate that could not run or timed out |
| `aborted` | the human stopped the run |

The background plane runs after Render, never before it. Nothing here can change the run's
result. Exactly one thing crosses back into a future run: `CODEBASE_RULEBOOK.md`.

## What a human sees

| Stage | Human sees | Waits for a human |
|---|---|---|
| preflight | one line, and only when there is no config | no |
| route | the class, the one-sentence reason, the stage list | no |
| understand, plan | one progress line each | no |
| design | the spec, the mock, and the lock prompt | yes |
| build | one progress line | no |
| gates | one line per gate, pass or fail | no |
| review | one progress line with the slice count | no |
| fix | one line per round entered, with the round number and the failure | no |
| render | everything in step 7 | no |
| archivist, promoter, scout, janitor | nothing | no |

Design is the only stage that blocks on a person. Everything else runs to completion or
stops.

Silent: every `hp-journal` call, every `hp-validate` call, the assumption-stamping pass, and
the whole background plane. They write files and print nothing to the human.

A progress line is status, not rendered output. It carries no list, so it is never capped
and never shaped. The render rules start at Render.

## Do not

- Do not run a stage the route contract did not name, and do not reorder the ones it did.
- Do not continue past an invalid contract, a blocking gate failure, or a blocking gate that
  could not run.
- Do not treat a `did_not_run` gate as a pass, and do not send one to the fix loop.
- Do not branch on the `hp-gates` exit code alone. Read the per-gate results.
- Do not start a fix round past `limits.fix_loop_max_rounds`, and do not raise that limit to
  fit one more round.
- Do not apply ADHD shaping or the cap-at-five rule anywhere before Render.
- Do not spawn an agent by a bare name. Always `hyperpower:<name>`.
- Do not append to `usage.jsonl` or `mistakes.jsonl` with a shell redirect. Two writers
  interleave a partial record and the file stops parsing.
- Do not commit, push, or open a pull request. Run writes files and the journal.
- Do not re-run this skill to replay a stage. Use `/hyperpower:resume <run> --from <step>`,
  which reports working-tree drift first.
