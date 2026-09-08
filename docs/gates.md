# Gates

Gates are the only part of the pipeline that can stop a run. They execute commands and read
exit codes. No model judgment.

## The rule

A gate reports one of three things:

| Result | Meaning |
|---|---|
| pass | the command ran and exited 0 |
| fail | the command ran and exited non-zero |
| did not run | the command could not execute |

"Did not run" is never reported as a pass. A gate that cannot run because dependencies are
missing says so.

## The runner

`plugins/hyperpower/scripts/hp-gates` runs them. It reads the effective config from
`hp-config`, runs every enabled gate in config order, and writes the aggregate into the run
journal as `gates.json`, plus one `gate:<name>` record in `usage.jsonl` and each gate's full
output at `gates/<gate>.log`.

```sh
hp-gates --run <run> --files src/a.ts,src/b.ts --config config.json --json
hp-gates --only types --files src/a.ts --config config.json --json
```

| Exit | Means |
|---|---|
| 0 | every enabled blocking gate passed |
| 1 | a blocking gate failed, or a blocking gate timed out |
| 78 | a blocking gate could not run. Not a failure, but not a pass either. |
| 2 | hp-gates itself could not run: bad flags, no config, no gates configured, or the aggregate failed validation |

A timeout is a failure, whichever timer fired. The gate script stops its own command at
`limits.gate_timeout_seconds` and exits 78 with a timeout detail; `hp-gates` records that
as a failure rather than a did-not-run, so one timeout has one meaning in `gates.json`.

Exit 78 exists because the exit code is the only signal a shell caller, CI step or hook
reads. Returning 0 for a blocking gate that never ran would report a pass nobody verified.
A gate you disabled in config is excluded — that is a deliberate choice, not an unverified
one. The gates that triggered 78 are listed in `blocking_unverified` in `gates.json`.

Read the per-gate `result` values, not the exit code alone. A blocking gate
that could not run is a hard stop for the caller, and that is what "fail closed" means here.

`--only` with no `--run` is a probe: it runs one gate, prints the result, and records
nothing, because a one-gate aggregate is not the run's gate result. `/hyperpower:doctor`
uses it that way.

The file scope comes from `--files`, then `HYPERPOWER_FILES_FILE`, then `HYPERPOWER_FILES`,
then `git diff` against HEAD plus untracked files. Paths that no longer exist, paths under
`paths.ignore`, and paths under `.hyperpower/` are dropped. An empty scope leaves `{files}`
in the command, which makes that gate report did-not-run rather than run against the whole
repo.

## Built-in gates

| Gate | Runs | Applies to | Script |
|---|---|---|---|
| types | `commands.typecheck` | any typed language | `gates/types.sh` |
| unit | `commands.test_scoped` | any repo with tests | `gates/unit.sh` |
| lint | `commands.lint` | any repo with a linter | `gates/lint.sh` |
| build | `commands.build` | any repo that builds | `gates/build.sh` |
| slop | `antislop --profile core`, `ai-slop-detector` | any repo | `gates/slop.sh` |
| e2e | `commands.e2e` | any repo with an end-to-end suite | `gates/e2e.sh` |
| browser | boot `dev_server`, load `{route}`, assert it renders | web only | `gates/browser.sh` |
| a11y | axe assertions on `{route}` | web only | `gates/a11y.sh` |
| visual | screenshot diff against the locked mock | web with a mock | `gates/visual.sh` |

Nine gates, and the same nine are the `gates:` keys in
[configuration.md](configuration.md). That schema is the roster. A name outside it lands in
`unknown_keys` and never runs.

`unit` runs `commands.test_scoped` only. It never falls back to `commands.test`, because a
scoped gate that silently runs the whole suite is reporting a check it was not asked for.

All nine ship a script. Four ship `enabled: false`: `e2e`, `browser`, `a11y`, `visual`. Each
of those needs an input no detector can supply, and each reports did-not-run until it has
it. `e2e` needs `commands.e2e`, which is null in the shipped schema. The other three are
below.

## Blocking versus advisory

```yaml
gates:
  types: { enabled: true, blocking: true }
  lint:  { enabled: true, blocking: false }
```

`blocking: false` reports a warning and lets the run continue. Use it for gates your
codebase does not pass yet. Promote to blocking once it does.

## The slop gate

Static analysis, no model, about a second, zero tokens.

Catches placeholders (`TODO`, `FIXME`, `HACK`), deferrals ("for now", "temporary fix"),
hedging ("hopefully", "should work"), stubs, redundant comments, unresolved imports, dead
pipelines, and copy-paste clones.

Three profiles:

| Profile | Use |
|---|---|
| `core` | in the gate. Zero false positives. |
| `standard` | in `/hyperpower:sweep`. Adds deferrals and hedging. |
| `strict` | never. It fights your codebase. |

What static analysis cannot see is handled by `/hyperpower:sweep`, which is a model pass.

## The three web gates

`browser`, `a11y` and `visual` check rendered output. All three ship `enabled: false`, and
each needs more than a command before it reports anything but did-not-run.

Turn one on only when every row of its table is satisfied. A gate switched on without its
inputs reports did-not-run on every run, and a blocking gate that did not run is a hard stop
for the caller. Off is the honest state until the inputs exist.

All three take a route. The caller passes it as `hp-gates --route <path>`, which sets
`HYPERPOWER_ROUTE` for the gate script. On UI work the routes come from `design.json`, whose
`routes` array is the list the design stage wrote. One invocation checks one route, and an
unset route means the site root.

All three boot `commands.dev_server` and wait for `commands.dev_url` to answer, and all
three treat a timeout as a failure rather than a did-not-run. The budget covers the boot and
one page, so a page that never appeared inside `limits.gate_timeout_seconds` is a rendering
failure.

The harness installs nothing. The browser, the axe CLI, and an image comparator are yours to
provide. `/hyperpower:doctor` names the one that is missing.

### browser

Boot `commands.dev_server`, wait for `commands.dev_url` to answer, load the route in a
headless browser, and assert the page rendered.

| Needs | From | Absent means |
|---|---|---|
| `gates.browser.enabled: true` | `hyperpower.yml` | did-not-run, the gate is off |
| `commands.dev_server` | `hyperpower.yml`, null until you set it | did-not-run, nothing to boot |
| `commands.dev_url` | `hyperpower.yml`, null until you set it | did-not-run, no origin to load |
| `curl` or `wget` | your machine | did-not-run, no readiness probe |
| a Chromium-family browser | your machine, or `HYPERPOWER_BROWSER_BIN` | did-not-run, and no fallback |

`HYPERPOWER_ROUTE` unset loads `/`, and the result says it used the default. A dev server
already answering on `commands.dev_url` is used as it is, and no second copy is started.

The gate never downgrades to a `curl` request and calls that a render. A page that answers
200 and paints nothing is the failure it exists to catch, so it asserts on the DOM: a body
element, text, elements, and no error overlay.

### a11y

Boot the same dev server, then run the axe CLI against the route.

| Needs | From | Absent means |
|---|---|---|
| `gates.a11y.enabled: true` | `hyperpower.yml` | did-not-run, the gate is off |
| `commands.dev_server` and `commands.dev_url` | `hyperpower.yml` | did-not-run, no server to scan |
| the axe CLI | `npm install -g @axe-core/cli` | did-not-run, the tool is missing |
| a Chromium-family browser | your machine, or `HYPERPOWER_BROWSER_BIN` | did-not-run, axe has nothing to drive |
| `curl` or `wget` | your machine | did-not-run, no readiness probe |

It fails on any violation whose impact is serious or critical. Moderate and minor
violations are counted and reported, and they never fail the gate. That threshold is
hardcoded in the script, because the config schema has no field for it and a gate never
reads a field the schema does not define. To change it, edit the script.

A missing axe runner is did-not-run, never a pass. An accessibility check that did not
happen is not a clean accessibility report. Axe exiting with no report the gate can read is
did-not-run for the same reason.

### visual

Screenshot the route, screenshot the locked mock, and diff the two images.

| Needs | From | Absent means |
|---|---|---|
| `gates.visual.enabled: true` | `hyperpower.yml` | did-not-run, the gate is off |
| `commands.dev_server` and `commands.dev_url` | `hyperpower.yml` | did-not-run, no page to shoot |
| a locked mock for the route | `mock.path` in `design.json`, then `<docs>/mocks/<slug>.html` | did-not-run, nothing to compare against |
| `locked: true` on that contract | a human locked the mock | did-not-run, an unlocked mock is a proposal |
| `verification.baseline_valid: true` | the design stage writes it | did-not-run, the baseline is not valid |
| a Chromium-family browser | your machine, or `HYPERPOWER_BROWSER_BIN` | did-not-run, no screenshots |
| `curl` or `wget` | your machine | did-not-run, no readiness probe |
| an image comparator | `python3`, or ImageMagick `compare` with `identify` | did-not-run, the images cannot be diffed |

Set `HYPERPOWER_RUN_DIR` so the gate can read `design.json`, and so the diff image and both
screenshots land in that run's `gates/` directory.

It fails when more than 5 percent of pixels differ by more than 8 per channel. Both numbers
are hardcoded in the script, for the same reason the a11y threshold is: the config schema
has no field for either.

A mock nobody locked is not a baseline, and a diff against a proposal is a number nobody
asked for. A route with no locked mock is did-not-run, not a failure: it is a route nobody
has drawn yet.

## Adding a gate

The gate set is closed. `hp-config` merges only the keys in the schema in
[configuration.md](configuration.md), so a gate name that is not in that table lands in
`unknown_keys`, is never merged, and never runs. Adding one to `hyperpower.yml` alone has
no effect, and `hp-gates --only <name>` will say the gate is not configured.

Adding a gate is a change to the plugin, in three places:

1. **The script.** Drop an executable in `plugins/hyperpower/gates/<name>.sh`. Source
   `_lib.sh` and call `hp_init <name>`, then either `hp_command_gate <commands key>` for a
   gate that runs one configured command, or your own body ending in `hp_pass`, `hp_fail`,
   or `hp_did_not_run`.

   It reads the effective config as JSON on stdin, writes one JSON result object to stdout,
   and exits 0 pass, non-zero fail, 78 could not run.

   ```json
   {"gate":"bundle-size","result":"fail","detail":"main.js 412kb, budget 350kb","evidence":"dist/main.js"}
   ```

2. **The schema.** Add the gate to the `gates:` table in
   [configuration.md](configuration.md), with its default `enabled` and `blocking` values.
   `hp-config` reads that table, so this is the step that makes the key real.

3. **The command**, when the gate runs one. Add it under `commands:` in the same table.

Then run `hp-selfcheck`. Check 5 fails when a schema gate has no script and is not marked
not-shipped, and check 11 fails when a script has no schema entry, so the two cannot drift
apart once both exist.

Exit code 78 is the important one. Use it whenever the tool is missing or the environment
cannot support the check. Never exit 0 in that case: a gate that reports a pass it did not
perform is the one failure this whole layer exists to prevent.

## Debugging a gate

```
/hyperpower:doctor
```

Runs every gate once and reports which failed to execute, with the reason.

If a gate is disabled and you think it should work, the reason is written into
`hyperpower.yml` under that gate. Fix the cause, then run `doctor` again to re-enable it.
