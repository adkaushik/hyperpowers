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

## 2. Start building

Run this inside the repo you want to work in:

```
/hyperpower:build "a habit tracker with streaks"
```

Inside an app that already exists, run it with nothing after it:

```
/hyperpower:build
```

This is the only command you need to learn. It sets the repo up the first time, then pulls
in the rest of hyperpower when a step needs it.

### What it does first

**Sets up, if needed.** With no `hyperpower.yml`, it runs setup inline and reports what it
found in three lines. It does not stop. Section 3 has the details.

**Works out where it is.** First match wins:

| It finds | It does |
|---|---|
| one obvious change to one file | makes it, runs the gates, and reports. No questions. |
| an app it was already building | says where it stopped, and asks before it continues |
| code, but no app on record | reads the app, shows its picture of it, and asks you to correct it |
| an empty repo | proposes the features and their order, and asks you to agree |

**Picks a mode** from how you asked. If that is unclear, it asks one question.

### Drive, or ride along

| | Conductor | Co-passenger |
|---|---|---|
| Who writes the code | hyperpower | you |
| When it stops | at the approach, and at the verify result | never |
| What you get | a feature that went through gates and review | one line after a big turn, naming what to check |

Say "take over" or "I'll drive" to switch. Nothing restarts.

### Where the conductor stops

Only where a wrong guess costs a lot.

| Work | Stops |
|---|---|
| one-file change | none |
| a feature | two: the approach, then the verify result |
| an app | the feature list first, then two per feature |

After each feature it writes a report of what every agent did, decided and spent, into
`.hyperpower/reports/`. It offers to open it. It does not wait for you to read it.

### Four phrases steer it

```
"take over"     "I'll drive"     "what's next?"     "stop"
```

## 3. What setup does

`build` runs setup the first time. To set up without building anything, run
`/hyperpower:init`.

1. **Detects.** Package manager from your lockfile. Languages from file volume. Monorepo
   layout from workspace config. Test framework from dev dependencies. Gate commands from
   your CI workflow files.
2. **Asks.** At most six questions, each with a detected default. Press enter to accept.
   A repo with good CI config usually gets two.
3. **Writes `hyperpower.yml`.** See [configuration.md](configuration.md).
4. **Generates `CODEBASE_RULEBOOK.md`.** Capped at 30 rules. Seeded from your `CLAUDE.md`,
   `.claude/rules/`, lint config, and observed patterns.
5. **Verifies.** Runs every gate command once. Anything that fails to execute is written
   back as `enabled: false` with a reason.

Setup never claims a gate it could not run. It reports what is live, what is off, and why.

### Why it reads CI config

What your CI runs is what your repo actually treats as a gate. That is a better signal
than the `scripts` block, which accumulates commands nobody runs.

## 4. Come back later

Open a new session in the same repo. hyperpower says which app is in progress and where it
stopped. It does not continue on its own. Run `/hyperpower:build` to pick it up.

If commits landed in between, it names them and the features they touch before it trusts
its own record.

## 5. Check the setup

```
/hyperpower:doctor
```

Re-runs verification. Use it after changing `hyperpower.yml`, upgrading dependencies, or
switching machines.

## 6. Read what it guessed

After a feature:

```
/hyperpower:why <run-id>
```

Shows what it decided and what it assumed. Read the `refuted` assumptions first. Those are
where it guessed wrong and wrote code anyway.

## 7. Try the suggestors

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
| `build` picks up an app you dropped | Delete `app.json` in the state directory, `.hyperpower/` by default. The next `build` starts fresh. |
| Co-passenger never says anything | It speaks only after a turn that changed files, and never twice for the same change. |
| Setup disabled a gate you need | Run the command yourself. The reason is in `hyperpower.yml` under that gate. |
| Everything is slow | Run `/hyperpower:cost --by stage`. Check `models.mechanical` is set to a cheap model. |

## Next

Read [configuration.md](configuration.md) to tune what runs.
