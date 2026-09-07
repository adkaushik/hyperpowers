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
| 0 | no blocking gate failed. Did-not-run gates do not change this. |
| 1 | a blocking gate failed, or a blocking gate timed out |
| 2 | hp-gates itself could not run: bad flags, no config, or no gates configured |

Read the per-gate `result` values, not the exit code alone. Exit 0 with every gate reporting
`did not run` is a repo with no toolchain installed, not a repo that passed. A blocking gate
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
| browser | boot `dev_server`, load `{route}`, assert it renders | web only | not shipped yet |
| a11y | axe assertions on `{route}` | web only | not shipped yet |
| visual | screenshot diff against the locked mock | web with a mock | not shipped yet |

The last three are in the config schema and ship `enabled: false`. No script exists for them
yet. `e2e` ships a script and `enabled: false`, because `commands.e2e` is null until someone
sets it: it reports did-not-run, not a pass. `unit` runs `commands.test_scoped` only. It never falls back to `commands.test`, because
a scoped gate that silently runs the whole suite is reporting a check it was not asked for.

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
