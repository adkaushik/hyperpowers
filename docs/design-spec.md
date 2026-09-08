# hyperpower — design

Date: 2026-09-07
Status: approved for planning
Author: Kaushik, with Claude

## What this is

An agentic development harness. It takes a requirement, runs it through a pipeline of
specialist agents, and blocks the result on gates that execute real commands. It records
what it did and why, learns from its own repeated mistakes, and logs the work it noticed
but did not do.

It is stack-agnostic. It ships as a Claude Code plugin, is installed once per machine, and
adapts to each repository through a setup command that detects the stack and writes a
config file.

## Goals

1. A verification loop that can fail. Not a prompt that asks an agent to check its work.
2. Decisions that survive the session that made them.
3. Improvement over time without adding cost to a normal run.
4. Output shaped for one reader, who has ADHD and does not want ornamental English.
5. Measurable. Every prompt change is gated by an eval score.
6. Works in any repo after one setup command.

## Non-goals

- Not a replacement for an issue tracker. The harness writes to the repo only.
- Not a spec-driven-development system. No living spec layer, no per-change spec folders.
- Not a persona showcase. Agents exist where a distinct job exists, not to fill a roster.
- Not a hosted service. Nothing leaves the machine unless the user turns it on.

## Prior art and licences

Both MIT. Both credited in `ATTRIBUTION.md`.

- Superpowers (Jesse Vincent) — process skills: TDD, brainstorming, systematic debugging,
  writing plans, worktrees, verification before completion.
- superflow (Ashwani Kumar) — typed handoff contracts, the bounded fix loop with model
  escalation, the review-sweep partition-then-verify shape, the rulebook idea.
- i-have-adhd — output shaping rules, and the eval runner shape.

What hyperpower adds that none of them has: gates that execute, a durable run journal with
resume, an assumption lifecycle, a cold decision archive with a promotion path into the hot
context, background suggestors, per-repo config from a detection-driven setup, local cost
and usage analytics, and an eval layer that gates prompt changes.

## Distribution

Standalone repository, published as a Claude Code plugin marketplace.

```bash
claude plugin marketplace add https://github.com/adkaushik/hyperpowers
claude plugin install hyperpower@hyperpowers
```

Then, once per repository:

```
/hyperpower:init
```

Everything is namespaced `hyperpower:<name>`. No bare command names, so nothing collides
with commands the user already has.

## Onboarding

`/hyperpower:init` is the first thing that runs in a new repo. Nothing else works properly
until it has.

Design rule: **detect first, ask only what cannot be detected.** Every question carries a
detected default, so pressing enter is a valid answer.

### Step 1 — detect, ask nothing

| Signal | Read from |
|---|---|
| Repo root, default branch, remote | git |
| Package manager | lockfile: `pnpm-lock.yaml`, `package-lock.json`, `yarn.lock`, `bun.lockb`, `uv.lock`, `poetry.lock`, `go.sum`, `Cargo.lock`, `Gemfile.lock` |
| Languages | file extensions by volume |
| Monorepo layout | workspace fields, `nx.json`, `turbo.json`, `pnpm-workspace.yaml`, `Cargo.toml` members |
| Test framework | dev dependencies and config files |
| Build and dev commands | `scripts` in the manifest, `Makefile`, `justfile`, `Taskfile` |
| Existing conventions | `CLAUDE.md`, `AGENTS.md`, `.claude/rules/`, `.editorconfig`, lint config |
| CI commands | workflow files — the most reliable source of the real gate commands |

CI config is the best source. What CI runs is what the repo actually considers a gate.

### Step 2 — ask, at most six questions

Only what detection could not settle. Each is multiple choice with a default.

1. Project type — web frontend, backend service, monorepo, library, CLI, mobile, other
2. Which directories hold source the harness may edit
3. Which detected command is the real test command, when several look plausible
4. Which gates should block versus warn
5. Model tiers — one strong, one cheap
6. Whether to enable the browser and visual gates, which need a running app

Skip any question detection already answered. A clean repo often gets two questions.

### Step 3 — write config

Write `hyperpower.yml` at the repo root. See the schema below. Users may also write this
file by hand and skip the interview; `init` reads an existing file and only fills gaps.

### Step 4 — generate the rulebook

Scan the repo and write `CODEBASE_RULEBOOK.md`. Capped at 30 rules from the start. Seed it
from `CLAUDE.md`, `.claude/rules/`, lint config, and observed patterns.

### Step 5 — verify

Run every configured gate command once, with a timeout. Any command that fails to execute
is marked `enabled: false` with a reason in the config. The harness never claims a gate it
cannot run.

### Step 6 — report

Print what was detected, what was asked, which gates are live, which are disabled and why,
and the single next command to try.

`/hyperpower:doctor` re-runs steps 5 and 6 at any time.

## Configuration

`hyperpower.yml` at the repo root, committed. `hyperpower.local.yml` overrides it and is
gitignored, for per-machine paths and model choices.

```yaml
version: 1

project:
  name: acme-web
  type: web-frontend          # web-frontend | backend | monorepo | library | cli | mobile | other
  languages: [typescript, css]
  package_manager: pnpm

paths:
  source: [src/]              # the harness may edit these
  tests: [src/**/*.test.ts]
  docs: [docs/]
  ignore: [dist/, node_modules/, generated/]

commands:
  install: pnpm install --frozen-lockfile
  typecheck: tsc --noEmit
  test: pnpm vitest run
  test_scoped: pnpm vitest run {files}
  lint: pnpm eslint {files}
  build: pnpm build
  dev_server: pnpm dev
  dev_url: http://localhost:5173
  e2e: null

gates:
  types:   { enabled: true,  blocking: true }
  unit:    { enabled: true,  blocking: true }
  lint:    { enabled: true,  blocking: false }
  build:   { enabled: true,  blocking: true }
  slop:    { enabled: true,  blocking: true,  profile: core }
  e2e:     { enabled: false, blocking: false, reason: "no e2e command configured" }
  browser: { enabled: false, blocking: false, reason: "no dev_url configured" }
  a11y:    { enabled: false, blocking: false }
  visual:  { enabled: false, blocking: false }

models:
  judgment: claude-opus-5
  mechanical: claude-haiku-4-5

limits:
  rulebook_max_rules: 30
  fix_loop_max_rounds: 5
  scout_max_new_per_run: 3
  janitor_max_new_per_run: 5
  gate_timeout_seconds: 600

memory:
  decisions_dir: decisions/
  archivist: true
  promoter: true

telemetry:
  enabled: true
  destination: local          # local only. no remote destination exists.
  redact_paths: true

voice:
  adhd_shaping: true
  plain_english: true
```

`{files}` and `{route}` are the only template variables. They are substituted with the
scoped file list and the changed route.

A repo with no `hyperpower.yml` gets a single message telling the user to run
`/hyperpower:init`. The harness does not guess.

## The kernel

Six parts. Every harness built on top uses all six.

### 1. Context

`CODEBASE_RULEBOOK.md` at the repo root. Generated by `init`, refreshed on command. Holds
how this repo builds: conventions, patterns, banned APIs, test layout.

Loaded on every run. Therefore capped: **30 rules maximum**, configurable. At the cap,
adding a rule requires evicting one. A rule that has not prevented anything in 20 runs is
demoted back to the decision archive.

The cap is the point. An uncapped rulebook makes every run slower and dilutes the rules
that matter.

### 2. Contracts

Every stage boundary is a typed JSON schema. A stage that cannot produce a valid contract
fails loudly rather than degrading into prose the next stage misreads.

Nine schemas, one per stage, in `plugins/hyperpower/schemas/`. `scripts/hp-validate` checks
a contract against its schema and prints every violation with its JSON path. Anything but
exit 0 is a hard stop; the next stage never reads an unvalidated contract.

Every contract carries an `assumptions` array. See below.

### 3. Gates

The only part of the pipeline that can stop a run. Gates execute commands from
`hyperpower.yml` and read exit codes. No model judgment.

Nine gates. The same nine appear in the `gates:` schema in [configuration.md](configuration.md)
and in the table in [gates.md](gates.md). Those three lists are one roster, and
`hp-selfcheck` fails when a schema gate has no script and no not-shipped marker.

| Gate | Runs | Applies to |
|---|---|---|
| types | `commands.typecheck` | any typed language |
| unit | `commands.test_scoped` | any repo with tests |
| lint | `commands.lint` | any repo with a linter |
| build | `commands.build` | any repo that builds |
| slop | `antislop --profile core`, `ai-slop-detector` | any repo |
| e2e | `commands.e2e` | any repo with an end-to-end suite |
| browser | boot `dev_server`, load `{route}`, assert render | web only |
| a11y | axe assertions on `{route}` | web only |
| visual | screenshot diff against the locked mock | web with a mock |

Gates fail closed. A gate that cannot run reports that it did not run. It never reports a
pass it did not verify.

A gate marked `blocking: false` reports as a warning and does not stop the run.

`scripts/hp-gates` is the runner. It reads the effective config, runs every enabled gate in
config order, writes `gates.json` and one `gate:<name>` usage record into the run journal,
and exits 1 only when a blocking gate failed. A gate that could not run reports
`did_not_run`, which is neither a pass nor a failure, and the caller stops on it.

#### Gates run in place

Settled during planning. Gates run in the working tree. They do not run in a git worktree.

The reason: a worktree costs a checkout per run, and the gates are read-only with respect
to source. They run a configured command and read its exit code. None of them edits a file
the repo tracks. Paying for a checkout on every run buys isolation from a write that the
design does not make.

`gates/_lib.sh` implements this. `hp_init` calls `hp_cd_root`, which moves to
`HYPERPOWER_REPO_ROOT`, or to `git rev-parse --show-toplevel`, and runs the command there.

The accepted risk: a gate whose command writes build output pollutes the working tree.
`commands.build` writing `dist/` is the ordinary case. Keep those paths in `paths.ignore`
and in `.gitignore`, and the pollution stays invisible to the file scope and to git.

A gate that edits source is a defect in that gate. It is not a case this choice covers.
Revisit the worktree if a gate ever needs to write to a tracked path.

### 4. Evals

Shape copied from the `i-have-adhd` plugin, the only prior art here with a working release
gate.

- `evals/cases.jsonl` — one case per line: id, category, prompt, risk, criteria
- `evals/rubric.md` — weighted dimensions, blocker rule, release criteria
- `scripts/run_evals.py` — blind A/B/C labelling, paired-row enforcement, aggregation

Dimensions and weights: correctness 32, autonomy 22, actionability 18, safety 9,
concision 9, render conformance 10. Render conformance scores whether output followed the
ADHD and voice rules.

Release rule: a prompt change ships only when it has no blockers, correctness and safety
are within 0.1 of baseline or better, and the weighted score beats baseline.

Ship with 15 stack-neutral seed cases. Users add their own.

`init` does not generate cases from recent commits, and does not offer to. Settled during
planning. A case generated from a commit nobody reviewed is a case nobody trusts, and an
untrusted baseline is worse than an empty one: every later comparison inherits it, and the
release rule then gates prompt changes on a number that was never checked.

Do this instead. Run a few real tasks. Write cases against the work you have read, one per
behaviour you care about. Then record the baseline:

```
/hyperpower:eval --baseline
```

An empty suite is honest. `run_evals.py validate` reports `0 cases` and warns once per
empty category, so the gap is visible rather than filled with cases nobody read.

### 5. Orchestration

Primitives, not a graph engine.

- **Fan-out with pipeline semantics.** Downstream work starts as soon as its input is
  ready, not when the whole upstream batch finishes.
- **Bounded fix loop.** Five rounds maximum per task. Rounds 1–3 resume the same builder.
  Rounds 4–5 use a fresh builder on a model one tier up, told how many attempts preceded
  it. Round 5 failing is a hard stop that reports; it never spins.
- **Adjudication.** Every review finding gets a dedicated skeptic that tries to refute it.
  Verdicts are CONFIRMED, PLAUSIBLE, or REFUTED. Never refute for lack of a reproduction.
- **Routing.** Task class picks the stages and the model tier. Mechanical stages run on
  `models.mechanical`. Judgment stages run on `models.judgment`.

### 6. Render

The single boundary where machine output becomes human output. Every harness exits here.

Two rule sets apply, and they apply **only** here.

**ADHD shaping**, when `voice.adhd_shaping` is true: lead with the action, number
multi-step work, restate state, suppress tangents, specific time estimates, make wins
visible, matter-of-fact on errors, cap lists at five, no preamble or recap or closer.

**Voice**, when `voice.plain_english` is true: short sentences, subject-verb-object. No
idioms, no metaphors, no wordplay. No rhetorical build-up. Technical terms stay exact.

**Rank, never cap.** The cap-at-five rule is lossy. It applies to the rendered view only.
The full list stays in the contract, ranked. The view shows the top five and says how many
remain.

These rules do not apply inside agent-to-agent handoffs, subagent prompts, or findings
lists before they reach the render boundary. Applying them there silently drops findings.

## The pipeline

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

## Run journal and resume

A run is a folder, not a conversation. Sessions are disposable.

```
.hyperpower/runs/<run-id>/
  meta.json           base sha, task class, model tiers used, config hash
  <step>.json         that step's output contract
  mistakes.jsonl      failure events appended during the run
  usage.jsonl         one line per model call: stage, model, tokens, duration
  corrections.jsonl   corrections from /hyperpower:correct
  resume.jsonl        one line per /hyperpower:resume replay
  gates/<gate>.log    full output of each gate command
  superseded/<ts>/    step contracts a resume invalidated
```

`scripts/hp-journal` writes it. Nothing else creates a run folder, and nothing appends to a
`.jsonl` in one with a shell redirect: two agents doing that interleave a partial record and
the file stops parsing. Record shapes are in `plugins/hyperpower/scripts/JOURNAL.md`.

The run id is `sha256("<base_sha>:<counter>")` truncated to four hex characters. It comes
from the base sha, not from a clock and not from randomness, so the same run is the same id
on any machine. `hp-journal new` claims the folder with `mkdir`, which is atomic, so two
callers racing never share one.

Each step's cache key is the hash of `(prompt, upstream contract, git tree sha of files
read)`. Not the prompt alone — that is the bug that would let a resumed run review code
that no longer exists.

`/hyperpower:resume <run-id> --from <step>` invalidates that step and everything
downstream, then replays. Before doing anything it re-hashes the working tree and reports
drift:

```
Resume run 4f2a from Gates.
  Understand   ok
  Plan         ok
  Build        DRIFTED — 3 files changed since this step
Re-run from Build instead? [build / gates-anyway / abort]
```

`gates-anyway` stays available. It cannot be the silent default.

Claude Code's built-in `Workflow` resume caches within one session only. It is useful
inside a single run and is not sufficient for this. The journal is the durable mechanism.

## Assumptions

Every step contract carries them. Nothing waits on a human.

```json
{"id":"a1","claim":"settings API returns a bare array","source":"inferred",
 "confidence":"low","declared_at":"plan","checkable":"src/api/settings.ts",
 "status":"declared"}
```

`source` is `rulebook`, `inferred`, or `asked`. `status` moves
`declared → verified | refuted | unresolved`.

An assumption made at plan time becomes checkable once the code exists. A mechanical-model
pass at gate time re-reads each `checkable` target and stamps the status. No human
involved.

The `refuted` bucket is the highest-value output: an assumption that was wrong and shipped
code anyway.

Assumptions the agent never declared are the residual risk. Mitigation: the reviewer has a
second job — extract undeclared assumptions from the diff and report them as findings.

## Corrections

```
/hyperpower:correct <run> <step> <assumption-id> "<correction>" --scope <once|run|forever>
```

| Scope | Applies to |
|---|---|
| `once` | this replay only |
| `run` | every remaining step in this run |
| `forever` | promoted into the rulebook |

`forever` writes a rulebook diff for approval, because the rulebook is shared and loaded
everywhere.

If a correction contradicts code the harness can read, it says so once and then obeys. One
challenge, bounded. The human decides.

## Memory

Two stores with different jobs. Do not merge them.

| | Rulebook | Decision archive |
|---|---|---|
| Contains | how to behave here | why things are the way they are |
| Size | capped | unbounded |
| Loaded | every run | never |
| Written by | the promoter, and `forever` corrections | the archivist |
| Read | always | only on command |

### Decision record format

One markdown file per decision, in `decisions/`, committed to the repo. Markdown and git,
not a database: free history, readable without tooling, greppable, survives a rewrite of
the harness.

```yaml
---
id: 2026-09-07-preview-masking-location
run: 4f2a
ticket: null
decided_by: agent_autonomous
question: Where does field masking happen for preview mode?
chose: server-side masking before serialization
status: active
superseded_by: null
reversal_condition: >
  Revisit if preview needs unmasked values for client-side search.
artifacts:
  diff: a3f19c2
  mock: docs/mocks/preview.html
  eval_case: evals/cases/preview-masking.json
---
```

`decided_by` is one of `human`, `human_directed`, `agent_autonomous`,
`agent_proposed_approved`. The `agent_autonomous` bucket is the audit list: decisions made
without the human being asked.

The body captures what a one-line conclusion loses:

1. Options rejected, and why each was rejected
2. Assumptions and their final status
3. Fix-loop rounds — what was tried and failed before the shipped version
4. Findings the skeptic refuted, and on what grounds
5. The constraint that actually forced the choice

The archivist writes these from the run journal. It is telemetry, not recollection.

Never delete. Supersession only: a new decision sets `superseded_by` on the old one and the
chain is preserved.

## Background agents

Five. All off the critical path. All on `models.mechanical` except the gardener.

| Agent | Trigger | Reads | Writes |
|---|---|---|---|
| Archivist | post-run | run journal | `decisions/`, `mistakes.jsonl` |
| Promoter | post-run | mistakes log, then archive on a hit | rulebook |
| Gardener | on command | archive | archive (compacts) |
| Scout | post-run or on command | run journal, or git diff | `.hyperpower/backlog.jsonl` |
| Janitor | post-run or on command | lockfiles, diff, repo tools | `.hyperpower/hygiene.jsonl` |

### Promoter thresholds

Mechanical only. No judgment.

| Signal | Threshold |
|---|---|
| Same `forever` correction from the human, twice | 1 |
| Same assumption refuted across runs | 3 |
| Same gate failing for the same reason | 3 |
| Same finding class CONFIRMED across reviews | 3 |

At the rulebook cap, promotion is competitive: the new rule must beat the weakest existing
rule, and that rule is demoted.

The promoter writes without asking. Every promotion is logged and visible via
`/hyperpower:rules --recent` and git diff. Visible after the fact, not blocking before it.

### Mistakes log

Append-only, one line per failure event. This is what keeps the promoter cheap — it scans
this, and only opens a full decision record for candidates that cross threshold.

```jsonl
{"run":"4f2a","kind":"assumption_refuted","key":"settings-api-shape","ref":"decisions/2026-09-07-preview-masking-location.md"}
{"run":"4f2a","kind":"gate_failed","key":"a11y-contrast-token","ref":"..."}
```

### Gardener

Compacts, does not delete.

1. Mark decisions whose `reversal_condition` is now true as `stale`
2. Merge near-duplicates into one record carrying both provenances
3. Fold superseded chains into a compacted file
4. Delete only what is superseded, about files that no longer exist, and older than six
   months

Everything is in git, so a bad compaction is recoverable. That is why it may run without
asking.

### Scout and janitor

The rule that makes the scout useful: **every entry cites evidence from the actual work**.
No evidence, no entry. A backlog of generic AI ideas is worse than no backlog.

Both dedup by a stable `key`. A repeat increments `occurrences` and appends evidence; it
does not add a row. `occurrences` becomes the priority order for free. A key marked
`rejected` never comes back.

Scout categories: `bug-risk`, `tech-debt`, `test-gap`, `perf`, `ux`, `feature`.
Janitor categories: `dep-outdated`, `dep-deprecated`, `dep-unused`, `unmigrated`,
`config-drift`.

The janitor runs configured repo tools only. It never installs one.

Neither files to an external tracker. The sheets stay in the repo. The human promotes.

## Slop control

Static first, model second. This is the pattern every working tool in this space uses.

**Layer 1, in the gate, every run.** `antislop --profile core` plus `ai-slop-detector`.
Deterministic, offline, about a second, no tokens. Catches placeholders, deferrals,
hedging, stubs, redundant comments, unresolved imports, dead pipelines, clones.

Core in the gate, Standard in the sweep. Never Strict — it fights the codebase.

**Layer 2, on command, before review.** A mechanical-model sweep for what static analysis
cannot see:

1. Over-abstraction — a factory with one implementation, an interface with one implementer
2. Wrong fit — works, but not how this repo does it. Rulebook is the input.
3. Defensive junk — swallowed exceptions returning a default nobody checks
4. Comments explaining what instead of why
5. Invented API surface — a helper that exists because the model did not look for the
   existing one

**Layer 3.** Sweep corrects, layer 1 re-runs. Two passes maximum. Still failing goes to the
fix loop as a normal finding.

## Telemetry, usage and cost

All local. There is no remote destination in the codebase. Nothing is uploaded, and no
opt-in exists that would upload it, because none is implemented.

### What is recorded

`usage.jsonl` in each run folder, one line per model call:

```jsonl
{"ts":"2026-09-07T11:04:12Z","stage":"review","agent":"reviewer","model":"claude-opus-5","input_tokens":18422,"output_tokens":1130,"cache_read":16000,"duration_ms":9400,"outcome":"ok"}
```

Gate results go to the same file with `stage: "gate:types"` and no token counts.

When `telemetry.redact_paths` is true, file paths are hashed before being written to any
aggregate. Per-run journals keep real paths, because they are already inside the repo.

### Commands

`/hyperpower:usage [--since 7d] [--by stage|agent|model|run]`

Run counts, stage pass rates, fix-loop round distribution, gate failure counts by gate,
assumption verified/refuted/unresolved ratio, median run duration.

The two numbers that matter: **gate failure rate** and **fix-loop rounds per task**. Both
rising means the rulebook is drifting from the codebase.

`/hyperpower:cost [--since 30d] [--by stage|agent|model|run]`

Token totals and money, per stage, per agent, per model, per run. Cache-read tokens shown
separately, since they dominate and are cheap.

Prices live in `pricing.yml` in the plugin, with a `last_verified` date. Stale prices are
labelled stale rather than silently wrong.

`/hyperpower:telemetry [status|off|on|purge]`

Shows what is collected and where. `purge` deletes all recorded telemetry and prints how
many files were removed.

## Command surface

Everything namespaced. Nothing shadows an existing command.

**Setup**

| Command | Does |
|---|---|
| `/hyperpower:init` | detect, interview, write `hyperpower.yml`, generate rulebook, verify gates |
| `/hyperpower:doctor` | re-verify gates and tools, report what is broken and the fix |
| `/hyperpower:config` | show effective config, including local overrides and their source |
| `/hyperpower:paths` | show or set which directories the harness may edit |

**Run**

| Command | Does |
|---|---|
| `/hyperpower:run "<requirement>"` | drive one requirement through the pipeline, writing the run journal |
| `/hyperpower:route "<requirement>"` | classify the requirement and print the stages it would run, writing nothing |
| `/hyperpower:resume <run> --from <step>` | drift-check, invalidate downstream, replay |
| `/hyperpower:why <run> [--assumptions]` | what it decided and what it assumed |
| `/hyperpower:correct <run> <step> <id> "..." --scope` | correct a recorded assumption |

**Memory**

| Command | Does |
|---|---|
| `/hyperpower:decisions [query] [--by decided_by] [--stale]` | search the archive |
| `/hyperpower:rules [--recent] [--unused]` | show the rulebook and what the promoter added |
| `/hyperpower:gc` | run the gardener |

**Suggestors**

| Command | Does |
|---|---|
| `/hyperpower:scout` | log opportunities from the last run or the current diff |
| `/hyperpower:janitor [--all]` | log dependency and migration debt |

**Analytics**

| Command | Does |
|---|---|
| `/hyperpower:usage [--since] [--by]` | runs, pass rates, fix-loop rounds, gate failures |
| `/hyperpower:cost [--since] [--by]` | tokens and money by stage, agent, model, run |
| `/hyperpower:telemetry [status\|off\|on\|purge]` | what is recorded, and delete it |

**Quality**

| Command | Does |
|---|---|
| `/hyperpower:sweep` | layer 2 slop sweep on the current diff |
| `/hyperpower:review` | partition, review, adjudicate the current diff |
| `/hyperpower:eval [--baseline]` | run the eval suite and print the release verdict |

## Cost model

Speed and intelligence are in tension. This is how it is handled rather than wished away.

1. Route by task class. A one-file change does not spawn nine agents.
2. `models.mechanical` for mechanical stages: assumption checking, archiving, promoting,
   scouting, janitoring, partitioning.
3. `models.judgment` for planning, review adjudication, design.
4. Pipeline semantics on fan-out so verification starts before the whole sweep finishes.
5. Nothing in the background plane costs a normal run anything.

`/hyperpower:cost --by stage` is how this gets checked rather than assumed.

## Directory layout

The plugin repository:

```
hyperpowers/
  .claude-plugin/marketplace.json
  plugins/hyperpower/
    .claude-plugin/plugin.json
    agents/                    one file per agent role
    skills/                    one directory per command
    hooks/                     session start, commit gate
    gates/                     executable gate scripts, and _lib.sh
    schemas/                   the nine stage contracts
    scripts/                   the kernel executables, and run_evals.py
    tests/                     run-tests, and the shell cases it runs
    workflows/                 review sweep, council
    evals/
      cases.jsonl
      rubric.md
      baseline.json
    pricing.yml
    task-classes.yml           the routing table
  docs/
  ATTRIBUTION.md
  LICENSE
```

The plugin lives under `plugins/`, not at the repository root, because the repository is
also the marketplace that serves it.

A repository using it:

```
hyperpower.yml                 committed
hyperpower.local.yml           gitignored
CODEBASE_RULEBOOK.md           committed
decisions/                     committed
.hyperpower/                   runs gitignored, sheets committed
  runs/<run-id>/               gitignored
  evals/                       gitignored. run_evals.py writes run directories here.
  backlog.jsonl                the scout's sheet
  backlog.md
  hygiene.jsonl                the janitor's sheet
  hygiene.md
  promotions.jsonl             one line per promoter action
  redact-salt                  do not commit. See below.
  commit-gate                  optional. Its presence arms the commit hook.
```

`init` writes three `.gitignore` entries: `.hyperpower/runs/`, `.hyperpower/evals/`, and
`hyperpower.local.yml`. It never ignores `.hyperpower/` whole, because the three sheets are
meant to be committed.

`redact-salt` is the one file here that must not be committed, and `init` does not ignore
it. Add it yourself. It is derived from the repo's root commit on first use, so a committed
salt lets anyone holding the repo hash a path and match it against a redacted aggregate,
which is the whole point of redacting. Deleting it changes every token, and aggregates from
before the change stop lining up with aggregates after.

## Build order

0. `init`, `doctor`, `config`, and the `hyperpower.yml` schema. Nothing else works without
   them.
1. Kernel: context, contracts, gates, render, run journal, usage recording
2. Code and review harness, with 15 seed eval cases
3. Analytics: `usage`, `cost`, `telemetry`
4. Memory: archivist, decision archive, mistakes log, promoter, gardener
5. Suggestors wired to the run journal
6. QA harness: browser and a11y gates
7. Design harness: mock lock, visual diff, design-token conformance

Scout and janitor already exist as standalone skills and gain run-journal input at step 5.

Product and business harnesses come after the kernel is proven. They add stages before
Route; they add no new kernel.

This is dependency order, not a status list, and it is not maintained as one. Steps 6 and 7
name gates that now ship inert: `browser.sh`, `a11y.sh` and `visual.sh` are in the tree and
report did-not-run until the repo supplies a dev server, a route, and the tooling each
needs. Read [gates.md](gates.md) and [architecture.md](architecture.md) for what exists.
Do not read a numbered step here as work outstanding.

## Known deviations

Where the tree does not match a rule this project states. Each one is a decision on record.

### Skill length

`docs/contributing.md` says a skill past 150 lines is doing two jobs. Seven are past it:
`run`, `init`, `eval`, `telemetry`, `usage`, `cost`, and `route`. `run` is the longest by a
wide margin.

Do not trust that list. Line counts move. Count the current set:

```sh
wc -l plugins/hyperpower/skills/*/SKILL.md | sort -rn
```

A skill over the line and not among the seven above is new debt, not a new exception.

The rule takes an exception, and `init` is not split: it is one procedure of six ordered
steps with one exit, so splitting it would publish a half that runs without the half it
depends on, which is the failure the rule exists to prevent.

A driver skill runs a fixed sequence end to end, and no section of it is worth invoking on
its own. That is the whole exception. Six of the seven are drivers: `run`, `init`, `eval`,
`route`, `usage`, and `cost` are each numbered steps to one output.

`telemetry` is the seventh, and it is not a driver. It is four subcommands — `status`, `off`,
`on`, `purge` — and each could be a command by itself, so it fails the test above. It stays
one skill because `/hyperpower:telemetry` is one command in the surface above, so its length
is debt and not structure. Shorten it. Do not split it into four skills, and do not widen the
exception to cover it.

Do not read the exception as a raised cap. The test is whether a section could be a command
by itself, not the line count. A skill that is not a driver and is past 150 lines is doing
two jobs, and the repair is a shorter skill.

## Open questions

One left, and it does not block. Two were settled during planning and moved into the body.

| Question | Answer | Now in |
|---|---|---|
| Do gates run in a worktree or in place? | In place | The kernel, part 3, under Gates run in place |
| Should `init` generate eval cases from recent commits? | No | The kernel, part 4 |

1. Whether the rulebook cap is a rule count or a token budget. A token budget is more
   honest about the real constraint but harder to reason about while writing a rule.
