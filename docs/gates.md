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

## Built-in gates

| Gate | Runs | Applies to | Script |
|---|---|---|---|
| types | `commands.typecheck` | any typed language | `gates/types.sh` |
| unit | `commands.test_scoped` | any repo with tests | `gates/unit.sh` |
| lint | `commands.lint` | any repo with a linter | `gates/lint.sh` |
| build | `commands.build` | any repo that builds | `gates/build.sh` |
| slop | `antislop --profile core`, `ai-slop-detector` | any repo | `gates/slop.sh` |
| browser | boot `dev_server`, load `{route}`, assert it renders | web only | not shipped yet |
| a11y | axe assertions on `{route}` | web only | not shipped yet |
| visual | screenshot diff against the locked mock | web with a mock | not shipped yet |

The last three are in the config schema and ship `enabled: false`. No script exists for them
yet. `unit` runs `commands.test_scoped` only. It never falls back to `commands.test`, because
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

Drop an executable in `plugins/hyperpower/gates/`. It must:

1. Read config from `hyperpower.yml` on stdin as JSON
2. Exit 0 for pass, non-zero for fail, and 78 for "could not run"
3. Write a JSON result to stdout

```json
{"gate":"bundle-size","result":"fail","detail":"main.js 412kb, budget 350kb","evidence":"dist/main.js"}
```

Then register it:

```yaml
gates:
  bundle-size: { enabled: true, blocking: false }
```

Exit code 78 is the important one. Use it whenever the tool is missing or the environment
cannot support the check. Never exit 0 in that case.

## Debugging a gate

```
/hyperpower:doctor
```

Runs every gate once and reports which failed to execute, with the reason.

If a gate is disabled and you think it should work, the reason is written into
`hyperpower.yml` under that gate. Fix the cause, then run `doctor` again to re-enable it.
