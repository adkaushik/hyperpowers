# Changelog

Every version of the hyperpower plugin, newest first. The version is the one in
`plugins/hyperpower/.claude-plugin/plugin.json`. The plugin updater compares that string and
nothing else, so a change shipped without a bump reaches nobody.

To update an install, run these, then restart the session:

```bash
claude plugin marketplace update hyperpowers
claude plugin update hyperpower
```

## 0.10.1 — 2026-09-13

**Fixes from a humanize pass over the conductor.**

- `build` checks for a one-file change first. The trivial path was listed last under "first
  match wins", so a one-line fix in an existing app got a full take-over and a stop.
- `hp-app reconcile` reports drift for an app recorded before the repo's first commit, and
  says so when the recorded commit is gone. Both used to report no drift.
- `hp-app` finds the repo root through `hp-config`. A `HYPERPOWER_REPO_ROOT` that is not a
  directory is now bad input, not a place to create a state directory.
- The co-passenger no longer swallows an error inside a rule, so `HYPERPOWER_HOOK_DEBUG`
  shows it.
- Comments cut down to the ones that say why. `--origin resume` is gone; nothing passed it.

Known, not fixed yet: every script's state resolver treats a broken `hyperpower.yml` like a
missing one, so `paths.state` is ignored until the file parses again.

## 0.10.0 — 2026-09-13

**`/hyperpower:build`: one command that conducts.**

- One entry point for a feature or a whole app. It sets the repo up inline, so `init` is no
  longer a separate first step.
- Four starting points: resume an app on record, take over an existing app, start a new one,
  or make a one-file change with no stops.
- Conductor mode stops at the approach and at the verify result for each feature, plus the
  feature list up front for an app. Co-passenger mode leaves the driving to you.
- The co-passenger is a new `Stop` hook. After a turn that changed files, it adds one line
  naming what to check. It never blocks the turn and never runs anything.
- A report is written to `<state>/reports/` after every feature. A new session says which
  app is in progress, and waits to be asked before continuing.

New script `hp-app` keeps the app record in `<state>/app.json`. Test suite: 13 cases, 792
assertions.

## 0.9.0 — 2026-09-11

**Review a pull request by URL.**

- `/hyperpower:review` takes a PR URL, `owner/repo#123`, or a number.
- `hp-pr` fetches the PR head into a throwaway worktree. Your branch and working tree are not
  touched.
- The diff comes from `gh pr diff`, not a git range. A git range returns nothing for a PR
  that has already merged.
- Slop found on the PR is reported inline, marked as slop.
- Removing the worktree is offered, never automatic.

## 0.8.0 — 2026-09-11

**`/hyperpower:help`.**

- Every command in plain language, grouped by when you would reach for it.
- Opens with the three commands worth learning first.
- The command list is read from the skills on disk, so it cannot drift from what is
  installed.
- Selfcheck 14 fails when the help table and the skills disagree.

## 0.7.0 — 2026-09-11

**`/hyperpower:humanize`: three passes over code a model wrote.**

- Pass 1 finds slop code in nine classes and proposes fixes. It applies nothing.
- Pass 2 trims slop comments, only after showing a sample and getting a yes. It follows the
  repo's own comment rule.
- Pass 3 finds repeated code and says whether to collapse it or leave it.
- It checks for antislop and ai-slop-detector first, and says plainly when the findings are a
  model's reading instead.

## 0.6.0 — 2026-09-10

**Departments: twelve agents in six opposed pairs.**

- Frontend, backend, infra, product and UX pairs, plus reviewer and skeptic. Each pair argues
  opposite sides.
- Every voice reads the rulebook, the config and the decision records first, and says so when
  it cannot find the code.
- `/hyperpower:council` counts independent votes. No voice sees another.
- `/hyperpower:standup` lets them argue over two rounds, at about twice the cost.
- `departments.yml` decides who attends, so a schema question does not pull in all twelve.

## 0.5.0 — 2026-09-09

**Route is cheaper to act on.**

- New `triage` class for questions: understand and render only, ending in findings, never a
  plan.
- `bug` and `dependency` no longer run a plan stage.
- Route reports an estimate from this repo's recorded runs, and says so when there is no
  history.
- Above four stages, route stops and asks before starting.
- `init` measures untracked directories and ignores the large ones, such as agent tooling
  caches.

## 0.4.0 — 2026-09-09

**`/hyperpower:status`.**

- Answers two questions: is the harness on here, and what is a live run doing.
- Reads the run journal, so it works from a second session while a run is still going.
- Flags stuck signals: the same failure three times, a fix loop at round 4 or 5, a blocking
  gate failing or not run, or no journal write in ten minutes.
- Read only. It never stops a run. `--stop-hint` prints the commands for you to run.

## 0.3.0 — 2026-09-08

**`paths.state`: choose where the harness writes.**

- One field moves everything the harness writes. The default stays `.hyperpower`.
- Order: `HYPERPOWER_STATE_DIR`, then `paths.state`, then the default. A relative path is
  anchored to the repo root.
- `init` adds no `.gitignore` entry when git already ignores the directory.
- Changing the value does not move existing runs.
- README: pipeline and memory diagrams, and one ticket walked end to end.

## 0.2.0 — 2026-09-08

**The working harness.** Everything 0.1.0 described, built and verified by running it.

- Pipeline: route, understand, plan, design, build, gates, review, fix loop, render. Every
  stage writes a typed contract that is checked against its schema.
- Kernel scripts: `hp-config`, `hp-journal`, `hp-gates`, `hp-validate`, `hp-selfcheck` and
  `hp-redact`.
- Gates exit 0 for pass, 1 for fail, 78 for could not run. A gate that could not run is never
  a pass.
- Agents, skills, hooks, workflows, a 15-case eval suite, and a test suite that runs every
  kernel script.
- `/hyperpower:visualize` builds an HTML report of a session from its logs.

## 0.1.0 — 2026-09-07

**Scaffold.** The marketplace layout, the scout and janitor skills, and the documentation.
