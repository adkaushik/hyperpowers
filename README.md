# hyperpower

An agentic development harness for Claude Code. It runs a requirement through a gated
pipeline, records what it decided and what it assumed, and learns from repeated mistakes
without making normal runs slower.

Works in any repository. One setup command adapts it to your stack.

## Status

Design is complete. Implementation is in progress.

| Part | State |
|---|---|
| Design spec | done — see [docs/architecture.md](docs/architecture.md) |
| `/scout`, `/janitor` | working |
| Everything else | not built yet |

Do not install this expecting a finished harness. Install it if you want the two
suggestor skills, or if you want to follow along.

## Install

Takes about a minute.

```bash
claude plugin marketplace add https://github.com/adkaushik/hyperpowers
claude plugin install hyperpower@hyperpowers
```

Restart the session. Then, once per repository:

```
/hyperpower:init
```

`init` detects your stack, asks at most six questions, and writes `hyperpower.yml`. Budget
five minutes the first time.

## What you get

| Thing | What it does |
|---|---|
| Gates | Run real commands and fail closed. Not a prompt asking the agent to check itself. |
| Run journal | A run is a folder, not a conversation. Resume any step days later. |
| Assumptions | Every step records what it assumed. Checked mechanically once the code exists. |
| Decision archive | Why things are the way they are. Never loaded into context. Queried on demand. |
| Rulebook | How this repo builds. Capped at 30 rules, so it stays sharp. |
| Suggestors | Log the work you noticed but did not do. Every entry cites evidence. |

## The idea in one paragraph

Most agent harnesses are prompts asking a model to be careful. This one runs commands and
reads exit codes. Everything a run learns goes into cold storage that costs nothing to
keep. When the same mistake happens three times, a background agent promotes it into a
small rulebook that every run reads. That is the only thing that gets more expensive over
time, and it has a hard cap.

## Commands

Eighteen, in six groups. Full reference in [docs/commands.md](docs/commands.md).

```
/hyperpower:init            set up this repo
/hyperpower:doctor          check what is broken
/hyperpower:scout           log opportunities from the last run
/hyperpower:janitor         log dependency and migration debt
/hyperpower:usage           pass rates, fix-loop rounds, gate failures
/hyperpower:cost            tokens and money by stage
/hyperpower:decisions       search the decision archive
/hyperpower:why <run>       what it decided and assumed
```

## Documentation

| Doc | Read it when |
|---|---|
| [Getting started](docs/getting-started.md) | First install |
| [Configuration](docs/configuration.md) | Editing `hyperpower.yml` |
| [Commands](docs/commands.md) | Looking up a flag |
| [Architecture](docs/architecture.md) | Understanding how it works |
| [Gates](docs/gates.md) | Adding or debugging a gate |
| [Analytics and privacy](docs/analytics.md) | Checking what is recorded |
| [Contributing](docs/contributing.md) | Adding a skill, gate, or agent |
| [Design spec](docs/design-spec.md) | The full long-form design |

## Privacy

Nothing leaves your machine. There is no remote destination in the codebase, and no opt-in
that would create one. Usage and cost data are written to files inside your repository.

`/hyperpower:telemetry purge` deletes all of it and tells you how many files it removed.

## Credits

Built on work by other people, all MIT. See [ATTRIBUTION.md](ATTRIBUTION.md).

- [Superpowers](https://github.com/obra/superpowers) by Jesse Vincent — process skills
- [superflow](https://github.com/cashwanikumar/superflow) by Ashwani Kumar — handoff
  contracts, the bounded fix loop, the rulebook idea
- [i-have-adhd](https://github.com/ayghri) — output shaping and the eval
  runner shape
- [antislop](https://github.com/skew202/antislop) — the static slop linter in the gate

## Licence

MIT. See [LICENSE](LICENSE).
