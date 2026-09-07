# Architecture

## The shape

```
Requirement
  → Route              picks stages and model tier
  → Understand         read-only map of the affected code
  → Plan               typed contract out
  → Design             spec → mock → human locks it   (UI work only)
  → Build              TDD, driven by the contract
  → Gates              fail closed
  → Review             partition, one reviewer per slice, skeptic per finding
  → Fix loop           bounded, escalating
  → Render             ADHD shape, plain voice
  → You
```

Stages that do not apply are skipped. A one-file change with a rulebook precedent runs
Understand, Build, Gates, Review.

## The kernel

Six parts. Everything built on top uses all six.

### 1. Context

`CODEBASE_RULEBOOK.md`. How this repo builds: conventions, patterns, banned APIs, test
layout.

Loaded on every run, so it is capped at 30 rules. At the cap, adding a rule evicts the
weakest. A rule that has prevented nothing in 20 runs is demoted to the archive.

The cap is the point. An uncapped rulebook makes every run slower and dilutes the rules
that matter.

### 2. Contracts

Every stage boundary is a typed JSON schema. A stage that cannot produce a valid contract
fails loudly rather than degrading into prose the next stage misreads.

Nine schemas in `plugins/hyperpower/schemas/`, one per stage: `route`, `understand`,
`plan`, `design`, `build`, `gates`, `review`, `fix`, `render`. Every one is Draft 2020-12
with `additionalProperties: false`, so a stage that invents a field fails.

`scripts/hp-validate <step> --file <path>` checks a contract and prints every violation
with its JSON path. Exit 0 valid, 1 invalid, 2 usage error, 78 no schema for that stage.
Anything but 0 is a hard stop. It is Python standard library only and implements seven
keywords; a schema using an eighth is refused at load time rather than silently ignored.

Every contract carries an `assumptions` array. `hp-validate` refuses to load a schema that
drops it or varies its seven fields.

### 3. Gates

See [gates.md](gates.md). Commands and exit codes, no model judgment.

`scripts/hp-gates` is the runner. It reads the effective config, runs every enabled gate in
config order, writes `gates.json` and one `gate:<name>` usage record per gate into the run
journal, and exits 1 only when a blocking gate failed. A gate that could not run reports
`did_not_run`, which is never a pass and never a failure; the caller stops on it.

### 4. Evals

Every prompt change is scored before it ships.

- `evals/cases.jsonl` — one case per line
- `evals/rubric.md` — weighted dimensions and the release rule
- `scripts/run_evals.py` — blind A/B/C labelling, paired-row enforcement

Weights: correctness 32, autonomy 22, actionability 18, safety 9, concision 9, render
conformance 10.

Release rule: no blockers, correctness and safety within 0.1 of baseline or better, and
weighted score beats baseline.

### 5. Orchestration

Primitives, not a graph engine.

| Primitive | Behaviour |
|---|---|
| Fan-out | pipeline semantics. Downstream starts when its input is ready, not when the batch finishes. |
| Fix loop | five rounds max. Rounds 1–3 resume the same builder. Rounds 4–5 use a fresh builder one model tier up. Round 5 failing is a hard stop. |
| Adjudication | every finding gets a skeptic that tries to refute it. CONFIRMED, PLAUSIBLE, or REFUTED. Never refute for lack of a reproduction. |
| Routing | task class picks stages and model tier. |

`plugins/hyperpower/task-classes.yml` is the routing table: seven classes — `trivial`,
`one-file-fix`, `dependency`, `bug`, `refactor`, `feature`, `ui-feature` — each with the
stages it runs, the tier per stage, its review slice ceiling, and whether it waits for a
human. `skills/route` picks the class and `skills/run` executes the stages it named.

That list is one vocabulary in three places: `task-classes.yml`, the `task_class` enum in
`schemas/route.json`, and the same enum in `schemas/plan.json`. Route writes the class into
`meta.json`, the planner copies it into `plan.json`, and `/hyperpower:usage` groups by it.
`hp-selfcheck task-classes` fails when the three lists stop agreeing.

### 6. Render

The single boundary where machine output becomes human output. Every harness exits here.

Two rule sets, and they apply **only** here:

- **ADHD shaping** — lead with the action, number multi-step work, restate state, suppress
  tangents, specific time estimates, matter-of-fact on errors, cap lists at five.
- **Voice** — short sentences. No idioms, no metaphors, no wordplay. Technical terms stay
  exact.

**Rank, never cap.** Cap-at-five is lossy, so it applies to the rendered view only. The
full list stays in the contract, ranked. The view shows five and says how many remain.

These rules never apply inside agent-to-agent handoffs or findings lists before they reach
the render boundary. Applying them there silently drops findings.

## Run journal

A run is a folder, not a conversation. Sessions are disposable.

```
.hyperpower/runs/<run-id>/
  meta.json           base sha, task class, model tiers, config hash
  <step>.json         that step's output contract
  mistakes.jsonl      failure events
  usage.jsonl         one line per model call
  corrections.jsonl   corrections from /hyperpower:correct
  resume.jsonl        one line per /hyperpower:resume replay
  gates/<gate>.log    full output of each gate command
  superseded/<ts>/    step contracts a resume invalidated
```

`scripts/hp-journal` writes the folder. Nothing else creates it, and nothing appends to a
`.jsonl` in it with a shell redirect: two agents doing that interleave a partial record and
the file stops parsing.

| File | Written by | Read by |
|---|---|---|
| `meta.json` | `hp-journal new`, `hp-journal finish` | why, resume, review, archivist, telemetry |
| `<step>.json` | `hp-journal step`, `hp-journal hash` | why, resume, correct, usage, archivist |
| `usage.jsonl` | `hp-journal usage`, `hp-gates` | usage, cost, telemetry |
| `mistakes.jsonl` | `hp-journal mistake`, the archivist | promoter, why, telemetry |
| `gates.json` | `hp-gates`, through `hp-journal step` | run, the fix loop, why, archivist |
| `gates/<gate>.log` | `gates/_lib.sh` | the gate report, telemetry |
| `corrections.jsonl` | `/hyperpower:correct` | why, resume, archivist |
| `resume.jsonl`, `superseded/` | `/hyperpower:resume` | telemetry, history |

The run id is `sha256("<base_sha>:<counter>")` truncated to four hex characters. It comes
from the base sha, not from a clock and not from randomness. `hp-journal new` claims the
folder with `mkdir`, which is atomic, so two callers racing never share one. Do not parse a
run id for meaning.

`latest` is a valid run id everywhere.

Steps, in pipeline order: `route`, `understand`, `plan`, `design`, `build`, `gates`,
`review`, `fix`, `render`. A missing step file means the stage was skipped. It is not a
failure and not a pass.

Each step's cache key is the hash of `(prompt, upstream contract, git tree sha of files
read)`.

Hashing the prompt alone would be a bug: after you hand-edit code, a resumed run would
reuse a contract describing code that no longer exists, and review a fiction. Resume
re-hashes the working tree and reports drift first.

`hp-journal hash` computes the key and stores the three inputs separately, so a drift
report can name which one moved. `hp-journal drift <run> --from <step>` re-hashes and
prints the report `/hyperpower:resume` shows. A step with no recorded key reports
`UNHASHED`, which is drifted, never `ok`.

The blob hash is computed in process and equals `git hash-object`, so an uncommitted edit
counts as drift. A committed-only hash would miss it.

## Kernel scripts

Five executables in `plugins/hyperpower/scripts/`. Python 3, standard library only. No
third-party imports and no network access. They are what makes the harness more than
prose: skills and agents call them rather than parsing YAML, hashing files, or writing the
journal themselves. A second implementation of any of these drifts from the first, and
nothing in the output shows it.

| Script | Does | Exit codes |
|---|---|---|
| `hp-config` | merges `hyperpower.yml` and `hyperpower.local.yml` and prints the effective config, the per-field source, and the config hash | 0 ok, 1 parse error, 78 no config |
| `hp-journal` | writes and reads `.hyperpower/runs/<run-id>/`: `new`, `step`, `hash`, `usage`, `mistake`, `drift`, `finish`, `list`, `path` | 0 written, 1 refused, 78 no config |
| `hp-validate` | checks a stage contract against `schemas/<stage>.json` | 0 valid, 1 invalid, 2 usage, 78 no schema |
| `hp-gates` | runs every enabled gate and records the aggregate | 0 no blocking failure, 1 blocking failure, 2 could not run |
| `hp-selfcheck` | checks the plugin against its own documentation, 13 checks | 0 clean, 1 findings |

`run_evals.py` sits beside them and is documented in `plugins/hyperpower/scripts/README.md`
with the rest.

Who calls what:

| Caller | Calls |
|---|---|
| `/hyperpower:run` | all four of `hp-config`, `hp-journal`, `hp-validate`, `hp-gates` |
| `/hyperpower:route` | `hp-config`, `hp-validate`, and `hp-journal` only after route returns |
| `/hyperpower:resume` | `hp-journal drift`, `hp-config`, `hp-gates` |
| `/hyperpower:config` | `hp-config --source` |
| `/hyperpower:doctor` | `hp-config --source`, then `hp-gates --only <gate>` per gate |
| the mapper, planner, designer | `hp-validate` on their own contract before returning it |
| CI | `hp-selfcheck --strict` |

## Assumptions

Every step records what it assumed. Nothing waits on a human.

```json
{"id":"a1","claim":"settings API returns a bare array","source":"inferred",
 "confidence":"low","declared_at":"plan","checkable":"src/api/settings.ts",
 "status":"declared"}
```

`status` moves `declared → verified | refuted | unresolved`.

An assumption made at plan time is a guess. By gate time the code exists, so the check is
mechanical and cheap. A cheap-model pass re-reads each `checkable` target and stamps the
status.

The `refuted` bucket is the highest-value output: assumptions that were wrong and shipped
code anyway. Found without anyone reviewing anything.

Undeclared assumptions are the residual risk. The reviewer has a second job: extract
undeclared assumptions from the diff and report them as findings.

## Memory

Two stores. Different jobs. Never merged.

| | Rulebook | Decision archive |
|---|---|---|
| Contains | how to behave here | why things are the way they are |
| Size | capped | unbounded |
| Loaded | every run | never |
| Written by | promoter, and `forever` corrections | archivist |
| Read | always | only on command |

A decision record is a markdown file in `decisions/`, committed. Markdown and git, not a
database: free history, readable without tooling, greppable, survives a rewrite of the
harness.

The body captures what a one-line conclusion loses:

1. Options rejected, and why
2. Assumptions and their final status
3. Fix-loop rounds — what was tried and failed
4. Findings the skeptic refuted, and on what grounds
5. The constraint that forced the choice

The archivist writes these from the run journal. It is telemetry, not recollection.

Never delete. Supersession only.

## Background agents

Five. All off the critical path. Nothing here costs a normal run anything.

| Agent | Trigger | Reads | Writes |
|---|---|---|---|
| Archivist | post-run | run journal | `decisions/`, `mistakes.jsonl` |
| Promoter | post-run | mistakes log, archive on a hit | rulebook |
| Gardener | on command | archive | archive (compacts) |
| Scout | post-run or on command | run journal, or git diff | `backlog.jsonl` |
| Janitor | post-run or on command | lockfiles, diff, repo tools | `hygiene.jsonl` |

### How the loop closes

Archive → mistakes log → promoter → rulebook → fewer mistakes.

The promoter uses thresholds, not judgment:

| Signal | Threshold |
|---|---|
| Same `forever` correction from you, twice | 1 |
| Same assumption refuted across runs | 3 |
| Same gate failing for the same reason | 3 |
| Same finding class CONFIRMED across reviews | 3 |

At the cap, promotion is competitive. The new rule must beat the weakest existing rule,
and that rule is demoted.

The mistakes log is what keeps the promoter cheap. It scans that tiny append-only file and
only opens a full decision record for candidates that cross threshold.

### One wire back

The background plane never touches a run. Exactly one thing crosses into the hot path: the
rulebook.

If the design ever needs a second crossing, it has drifted.

## Cost

Speed and intelligence are in tension. This is how it is handled.

1. Route by task class. A one-file change does not spawn nine agents.
2. `models.mechanical` for mechanical stages. It is most of the call volume.
3. `models.judgment` for planning, review adjudication, design.
4. Pipeline semantics on fan-out, so verification starts before the sweep finishes.
5. Nothing in the background plane costs a normal run anything.

Check it with `/hyperpower:cost --by stage` rather than assuming.
