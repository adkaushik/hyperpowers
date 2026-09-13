---
name: build
description: The one command to start with. Build a feature or a whole app, take over an app that already exists, or resume one in progress. Works out what you want and whether to drive or ride along, sets the repo up itself, stops only where a wrong guess is expensive, and pulls in review, gates, the expert team and reports without you naming them. Use /hyperpower:build "<what to build>", or /hyperpower:build alone inside an existing app.
---

# build

One entry point that conducts. It asks at the moments a human is needed and otherwise gets on
with it, pulling in the right hyperpower capability at each step.

Every other hyperpower command still exists. Someone using `build` should never need to type
one.

```
/hyperpower:build "a habit tracker with streaks"     start something new
/hyperpower:build                                    take over the app you are in
/hyperpower:build --takeover                         the same, said explicitly
```

Kernel commands below are `python3 ${CLAUDE_PLUGIN_ROOT}/scripts/<name>`.

## The rules that make it predictable

1. **Say what you detected and what you are about to do before anything costly.**
2. **Ask at most one question at a time**, multiple choice, best guess marked.
3. **Stop only at the checkpoints below.** Nowhere else.
4. **Never claim done on your own word.** Done means the gates ran and review ran.

---

## Step 0 — set up, no separate command

`hp-config --state-dir`. Exit 78 means there is no `hyperpower.yml`.

Do what `/hyperpower:init` does, inline, following that skill's steps. Then report in three
lines and continue without stopping:

```
Setting up first.
  Found: Next.js + Django monorepo, npm, vitest, CI in .github/workflows
  Live gates: types, unit, build, lint. Browser gates off, no dev URL.
```

## Step 1 — what am I walking into

First match wins.

| `hp-app show --json` | The repo | Action |
|---|---|---|
| any | the request is one obvious change to one file | **Trivial** — step 2d |
| exits 0 | anything | **Resume** — step 2a |
| exits 1 | has code | **Take over** — step 2b |
| exits 1 | empty | **New** — step 2c |
| exits 2 | anything | `app.json` is unreadable. Show the error, then ask: fix it by hand, or start over with `hp-app init --force` |

## Step 2a — resume

Check the record against the code before trusting it:

```bash
hp-app reconcile --check
```

Commits since the last check mean someone built outside the conductor. Name them and the
features they touch, then ask:

```
You were building habit-tracker. 3 of 7 features done. Next up: reminders.
2 commits landed since we last checked, touching streaks.
Continue with reminders, look at streaks first, or change the plan?
```

**Always ask. Never resume on your own.** Once they answer, run `hp-app reconcile` without
`--check` to record the new head.

## Step 2b — take over

Read the app — routes, pages, components, models, migrations, tests — and reconstruct it.
Look specifically for half-done work: placeholders, stubs, disabled paths, commented-out
routes.

Show the picture. **This is a stop.**

```
Here's what I think this app is:
  Built       auth, surveys, research agent, recording, dashboards
  Half-done   survey Ask AI: 3 placeholders, a stub in survey/views.py
  Stack       Next.js, Django, Postgres
Is that right? Correct anything before I build on it.
```

Building on a wrong picture of someone's own app is the expensive mistake. Do not skip this.

Once confirmed:

```bash
hp-app init --name <name> --scope app --mode <mode> --origin takeover --stack <a,b>
hp-app feature add --name <feature> --status done        # each built feature
hp-app feature add --name <feature> --status half-done   # each half-done one
```

## Step 2c — new

**App:** agree the feature list and the order before building anything. **This is a stop.**
Propose a list, lead with the smallest thing that is useful on its own, and say why the
order matters:

```
Proposed order:
  1  habits        create, list, delete. Nothing else works without these.
  2  check-ins     mark a habit done for a day
  3  streaks       needs check-ins to count
  4  reminders     needs habits and a schedule
Agree, reorder, or cut?
```

Building feature four before noticing it contradicts feature two is the mistake this stop
prevents.

Then `hp-app init --origin new`, and `hp-app feature add` for each, in order.

**Feature:** no list to agree. `hp-app init --scope feature --origin new`, one feature.

## Step 2d — trivial

Do it. Run the gates. Report what changed and what the gates said. No stops, no record, no
report. `hp-app` is not involved.

## Step 3 — conductor or co-passenger

Infer it from how they asked:

| They say something like | Mode |
|---|---|
| "build X", "add Y", "make it do Z" | conductor |
| "I'm building X", "help me as I go", "watch while I work" | co-passenger |

Unclear: one question.

```
Should I drive, or ride along while you do?
  drive       I take it phase by phase and stop at the decisions   (my guess)
  ride along  you build, I suggest what to check as you go
```

`hp-app mode <conductor|copassenger>` records it.

**Switching is one sentence, any time.** "Take over" moves to conductor. "I'll drive" moves to
co-passenger. Run `hp-app mode` and carry on from where the record says — nothing restarts.

## Conductor — the phases

For each feature, set it current with `hp-app current <id>`, then work through these. Record
the phase as you enter it: `hp-app feature set <id> --phase <phase>`.

| Phase | What happens | Uses | Stop? |
|---|---|---|---|
| discovery | restate what this feature must do | `/hyperpower:route` | feature: confirm understanding |
| explore | map the code it touches | `hyperpower:mapper` | no |
| clarify | edge cases, errors, integration points | reading the code | only when genuinely unspecified |
| approach | two or three ways to build it | `hyperpower:planner`; `/hyperpower:council` when the choice is expensive to reverse | **yes** |
| build | test first, against the chosen approach | `hyperpower:builder` | no |
| verify | gates, review, slop | `hp-gates`, `/hyperpower:review`, `/hyperpower:humanize` | **yes** |
| report | what was built and what it cost | `/hyperpower:why`, `hp-visualize` | offers, does not stop |

Run each stage exactly as `/hyperpower:run` specifies — journal, contract validation,
recorded usage. `build` adds the conversation around the pipeline; it does not replace it.

**Clarify** asks only what the code cannot answer.

**Approach** — offer two or three, recommend one, say what each costs:

```
Two ways to add reminders:
  A  cron job polling for due habits      simple, up to a minute late    (recommended)
  B  a scheduled task per habit           exact, more to keep in sync
```

**Verify** — never skip it, and never report a blocking gate that did not run as a pass:

```
Built reminders. Gates: types 0, unit 0, build 0.
Review found 2 things:
  1  reminder.ts:41   a user in a changed timezone gets the reminder twice
  2  humanize         3 comments restate the line below them
Fix now, later, or ship as is?
```

Then `hp-app feature set <id> --status done --run <run-id>`.

### Checkpoints scale with the work

| Work | Stops |
|---|---|
| trivial | none |
| feature | approach and verify |
| app | the feature list up front, then approach and verify per feature |

These are the only stops. Anything else is a question the code can answer, so read the code.

## Co-passenger

The human drives. Say this once, then get out of the way:

```
Riding along. After you finish something substantial I'll add one line about what to check.
Say "what's next?" any time, or "take over" if you want me to drive.
```

The `Stop` hook does the rest. It reads `app.json`, and after a turn that changed files it
may add one line — review when the turn claims done, the backend pair when a migration
changed, `janitor` when a manifest changed, `humanize` after a lot of new code. It never
blocks and never runs anything itself.

When they ask "what's next?", read `hp-app show`, the diff, and the last run, and recommend
one thing.

## Report — after every feature and app step

When a feature finishes verify, or an app step completes, write the report to a stable path
and record it:

```bash
hp-visualize --root <repo> --out <state>/reports/<feature-id>-<name>.html
hp-app feature set <id> --report <that path>
```

`<state>` is the directory holding `app.json` — `dirname` of `hp-app path`.

Then one line, never a stop:

```
Report for reminders: .hyperpower/reports/f4-reminders.html — what each agent did,
decided and spent. Want me to open it?
```

Trivial work gets no report.

## The whole interface

End the first run in a repo with this, once:

```
Steer me with:  "take over"   "I'll drive"   "what's next?"   "stop"
```

That is everything a person needs to know. Every other command is offered when it becomes
relevant.

## Do not

- Do not stop anywhere except the checkpoints. A question the code can answer is not a
  question.
- Do not skip the take-over confirmation, the app feature list, approach, or verify.
- Do not resume on your own. Always say where it left off and ask.
- Do not trust `app.json` over the code. Reconcile first.
- Do not report done because the builder said so. Done means gates and review ran.
- Do not treat a blocking gate at `did_not_run` as a pass.
- Do not list all the hyperpower commands. Offer the one that applies.
- Do not write a report for trivial work.
