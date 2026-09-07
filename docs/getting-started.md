# Getting started

## 1. Install the plugin

About one minute.

```bash
claude plugin marketplace add https://github.com/adkaushik/hyperpowers
claude plugin install hyperpower@hyperpowers
```

Restart your session. Check it loaded:

```bash
claude plugin details hyperpower
```

## 2. Set up your repository

Run this inside the repo you want to work in.

```
/hyperpower:init
```

Five minutes the first time. Under a minute on a repo with clean CI config.

### What init does

1. **Detects.** Package manager from your lockfile. Languages from file volume. Monorepo
   layout from workspace config. Test framework from dev dependencies. Gate commands from
   your CI workflow files.
2. **Asks.** At most six questions, each with a detected default. Press enter to accept.
   A repo with good CI config usually gets two.
3. **Writes `hyperpower.yml`.** Committed to the repo. See
   [configuration.md](configuration.md).
4. **Generates `CODEBASE_RULEBOOK.md`.** Capped at 30 rules. Seeded from your `CLAUDE.md`,
   `.claude/rules/`, lint config, and observed patterns.
5. **Verifies.** Runs every gate command once. Anything that fails to execute is written
   back as `enabled: false` with a reason.
6. **Reports.** What it found, what is live, what is disabled and why.

Init never claims a gate it could not run.

### Why it reads CI config

What your CI runs is what your repo actually treats as a gate. That is a better signal
than the `scripts` block, which accumulates commands nobody runs.

## 3. Check the setup

```
/hyperpower:doctor
```

Re-runs verification. Use this after changing `hyperpower.yml`, upgrading dependencies, or
switching machines.

## 4. Run your first task

Give Claude a normal request. The harness routes it. Nothing extra to type.

After it finishes:

```
/hyperpower:why <run-id>
```

Shows what it decided and what it assumed. The `refuted` assumptions are the ones worth
reading — those are where it guessed wrong and shipped anyway.

## 5. Try the suggestors

These work without the rest of the harness.

```
/hyperpower:janitor
```

Reads your lockfile, runs the tools your repo already configures, and logs dependency and
migration debt to `.hyperpower/hygiene.jsonl`.

```
/hyperpower:scout
```

Logs opportunities from the current diff — test gaps, out-of-scope defects, tech debt —
to `.hyperpower/backlog.jsonl`. Every entry cites evidence. No evidence, no entry.

## Troubleshooting

| Problem | Fix |
|---|---|
| Commands not found after install | Restart the session. The plugin loads at session start. |
| `init` disabled a gate you need | Run the command yourself. The reason is in `hyperpower.yml` under that gate. |
| Browser and visual gates are off | They need `commands.dev_server` and `commands.dev_url`. Set both, then run `doctor`. |
| Rulebook has rules you disagree with | Edit `CODEBASE_RULEBOOK.md` directly. It is a normal file. |
| Everything is slow | Run `/hyperpower:cost --by stage`. Check `models.mechanical` is set to a cheap model. |

## Next

Read [configuration.md](configuration.md) to tune what runs.
