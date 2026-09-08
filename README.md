# hyperpower

An agentic development harness for Claude Code.

It runs a requirement through a gated pipeline, records what it decided and what it
assumed, and learns from repeated mistakes without making normal runs slower.

Stack-agnostic. One setup command adapts it to any repository.

## Install

```bash
claude plugin marketplace add https://github.com/adkaushik/hyperpowers
claude plugin install hyperpower@hyperpowers
```

Restart the session, then run this once per repository:

```
/hyperpower:init
```

`init` detects your stack, asks at most six questions, and writes `hyperpower.yml`. Budget
five minutes the first time.

## How it works

### The pipeline

One command drives one requirement to the end:

```
/hyperpower:run "add a settings screen"
```

```
Requirement
  → Route              picks stages and model tier
  → Understand         read-only map of the affected code
  → Plan               typed contract out
  → Design             spec → mock → you lock it   (UI work only)
  → Build              TDD, driven by the contract
  → Gates              fail closed
  → Review             partition, one reviewer per slice, skeptic per finding
  → Fix loop           bounded, escalating
  → Render             shaped output
  → You
```

Every stage writes a typed JSON contract, and the contract is checked against its schema
before the next stage reads it. A stage that cannot produce a valid contract stops the run
instead of handing the next stage prose it will misread.

The contracts land in `.hyperpower/runs/<run-id>/` while the run happens, not afterwards.
That folder is the record: what each stage decided, what it assumed, what every gate
printed, and every model call it made.

Stages that do not apply are skipped. A one-file change with a rulebook precedent runs
Understand, Build, Gates, Review. `/hyperpower:route "<requirement>"` prints the stage list
it would use, and writes nothing, so you can see the cost before paying it.

### Gates execute commands

A gate runs a command from your config — `tsc --noEmit`, your test command, your build —
and reads the exit code. No model judgment.

A gate that cannot run says it did not run. A missing tool, a null command, a timeout: none
of those is a pass, and a blocking gate that did not run stops the run just as a failure
does. It never reports a pass it did not verify.

You choose which gates block and which only warn. Start `lint` as a warning and promote it
once the codebase is clean.

Nine gates are in the schema. Types, unit, lint, build and e2e run commands from your
config. Slop runs two static linters. Browser, a11y and visual check rendered output, so
they need a dev server, a route, and their own tooling before they check anything. Full
list in [docs/gates.md](docs/gates.md).

### A run is a folder, not a conversation

The run journal is written as the run goes: `meta.json`, one contract per step, the full
output of every gate command, a line per model call, and a line per failure event. Sessions
are disposable. The folder is not. You can resume any step days later, on another machine.

The run id comes from the base commit, not from a clock, so the same run has the same id
everywhere.

Resume re-hashes the working tree first and reports drift:

```
Resume run 4f2a from Gates.
  Understand   ok
  Plan         ok
  Build        DRIFTED — 3 files changed since this step
Re-run from Build instead? [build / gates-anyway / abort]
```

Without that check, a resumed run would review code that no longer exists.

### Assumptions are recorded, then checked

Every step records what it assumed. Nothing waits on you.

```json
{"id":"a1","claim":"settings API returns a bare array","source":"inferred",
 "confidence":"low","checkable":"src/api/settings.ts","status":"declared"}
```

At plan time that is a guess. By gate time the code exists, so a cheap model re-reads the
target and stamps the status: verified, refuted, or unresolved.

The refuted list is the useful one — assumptions that were wrong and shipped code anyway,
found without anyone reviewing anything.

```
/hyperpower:why 4f2a --assumptions
```

### Memory is two stores, not one

|  | Rulebook | Decision archive |
|---|---|---|
| Contains | how to behave in this repo | why things are the way they are |
| Size | capped at 30 rules | unbounded |
| Loaded | every run | never |
| Read | always | only when you ask |

The archive holds full decision records — options rejected and why, assumptions and their
outcome, what was tried and failed, the constraint that forced the choice. Markdown files
in `decisions/`, committed to your repo.

It costs nothing to keep, because it is never loaded into context.

When the same mistake happens three times, a background agent promotes it into the
rulebook, which every run does read. At the cap, the new rule must beat the weakest
existing rule, and that rule is demoted.

That cap is what keeps the harness from getting slower as it learns.

### Five agents run after the work, not during it

| Agent | Writes |
|---|---|
| Archivist | decision records and the mistakes log |
| Promoter | rules, when a mistake crosses threshold |
| Gardener | compacts the archive, on command |
| Scout | opportunities you noticed but did not do |
| Janitor | dependency and migration debt |

None of them costs a normal run anything.

The scout has one rule that makes it useful: every entry cites evidence from the actual
work. No evidence, no entry. A backlog of generic AI ideas is worse than no backlog.

### Slop control is static first

`antislop` and `ai-slop-detector` run in the gate. Offline, about a second, zero tokens.
They catch placeholders, deferrals, hedging, stubs, redundant comments, unresolved imports
and clones.

A model sweep handles what static analysis cannot see: over-abstraction, code that works
but does not match how your repo does things, swallowed exceptions, invented helpers that
duplicate existing ones.

### Every prompt change is scored

Changing a prompt without measuring is how harnesses quietly get worse.

```
/hyperpower:eval
```

Blind A/B/C labelling against a weighted rubric. A change ships only when it has no
blockers, correctness and safety hold within 0.1 of baseline, and the weighted score beats
baseline.

Fifteen stack-neutral cases ship. Write your own against work you have read, then record
the baseline. Nothing generates cases from your commit history: a case taken from a commit
nobody reviewed is a baseline nobody trusts, and every later comparison inherits it.

## Commands

Twenty-one commands in six groups. Full reference in [docs/commands.md](docs/commands.md).

```
/hyperpower:init            set up this repo
/hyperpower:doctor          check what is broken
/hyperpower:run "<req>"     drive one requirement to the end
/hyperpower:route "<req>"   print the stages it would run, and stop
/hyperpower:why <run>       what it decided and assumed
/hyperpower:resume <run>    replay from any step
/hyperpower:decisions       search the archive
/hyperpower:rules           show the rulebook
/hyperpower:scout           log opportunities
/hyperpower:janitor         log dependency debt
/hyperpower:usage           pass rates, fix-loop rounds, gate failures
/hyperpower:cost            tokens and money by stage
/hyperpower:review          partition, review, adjudicate
/hyperpower:eval            score a prompt change
/hyperpower:visualize       report what the agents did this session
```

## Configuration

`hyperpower.yml` at your repo root, committed. `hyperpower.local.yml` overrides it per
machine and is gitignored.

It sets which directories the harness may edit, which commands each gate runs, which gates
block, your two model tiers, and the limits.

You can write it by hand. `init` reads an existing file and only fills gaps.

Full schema in [docs/configuration.md](docs/configuration.md).

## Privacy

Nothing leaves your machine. There is no remote destination in the codebase, and no opt-in
that would create one. Usage and cost data are files inside your repository.

When `telemetry.redact_paths` is on, file paths are hashed before they reach an aggregate
view, so a report you paste somewhere carries digests instead of your directory names. The
per-run journal keeps the real paths, because it already lives in the repo it describes.

Redaction is not anonymity. The hash is salted from `.hyperpower/redact-salt`, so anyone
holding both the repo and that file can hash a path and match it. Add it to `.gitignore`
yourself — `init` does not.

```
/hyperpower:telemetry purge
```

Deletes all of it and tells you how many files it removed.

## Documentation

| Doc | Read it when |
|---|---|
| [Getting started](docs/getting-started.md) | First install |
| [Configuration](docs/configuration.md) | Editing `hyperpower.yml` |
| [Commands](docs/commands.md) | Looking up a flag |
| [Architecture](docs/architecture.md) | Understanding the internals |
| [Gates](docs/gates.md) | Adding or debugging a gate |
| [Analytics and privacy](docs/analytics.md) | Checking what is recorded |
| [Contributing](docs/contributing.md) | Adding a skill, gate, or agent |
| [Design spec](docs/design-spec.md) | The full long-form design |

## Credits

Built on work by other people, all MIT. See [ATTRIBUTION.md](ATTRIBUTION.md).

- [Superpowers](https://github.com/obra/superpowers) by Jesse Vincent — process skills
- [superflow](https://github.com/cashwanikumar/superflow) by Ashwani Kumar — handoff
  contracts, the bounded fix loop, the rulebook idea
- [i-have-adhd](https://github.com/ayghri) — output shaping and the eval runner shape
- [antislop](https://github.com/skew202/antislop) — the static slop linter in the gate

## Licence

MIT. See [LICENSE](LICENSE).
