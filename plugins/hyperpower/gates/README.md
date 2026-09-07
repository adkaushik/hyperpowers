# Gates

Gates are the only part of the pipeline that can stop a run. Each one runs a command from
`hyperpower.yml` and reports its exit code. No model judgment.

Run one by hand:

```sh
printf '%s' '{"commands":{"typecheck":"tsc --noEmit"},"gates":{"types":{"enabled":true}}}' | ./types.sh
echo "exit $?"
```

Converting `hyperpower.yml` to JSON is the caller's job. A gate never reads the YAML file.

## Index

| Script | Gate | Runs | Uses `{files}` |
|---|---|---|---|
| `types.sh` | types | `commands.typecheck` | no |
| `unit.sh` | unit | `commands.test_scoped` | yes |
| `lint.sh` | lint | `commands.lint` | yes |
| `build.sh` | build | `commands.build` | no |
| `slop.sh` | slop | `antislop --profile <profile>`, `ai-slop-detector` | yes |

`_lib.sh` holds config parsing, command execution, and result emission. Source it. Do not
execute it. It is the one file here that is not executable, on purpose.

### Not shipped yet

`docs/configuration.md` also names `browser`, `a11y`, and `visual`. No script exists for
them in this directory. They ship `enabled: false` in the schema, and `/hyperpower:doctor`
reports them as off rather than as broken. Build order puts browser and a11y at step 6 and
visual at step 7. Until a script lands, do not set any of the three to `enabled: true`: the
caller would look for a script that is not here.

## Contract

1. Config arrives on stdin as JSON, converted from `hyperpower.yml` by the caller.
2. Exit 0 for pass, non-zero for fail, 78 for could not run.
3. One JSON object goes to stdout. Nothing else goes to stdout.

```json
{"gate":"types","result":"pass","detail":"tsc --noEmit passed in 4s","evidence":"commands.typecheck = tsc --noEmit"}
```

| Field | Value |
|---|---|
| `gate` | the gate name, matching the key under `gates:` |
| `result` | `pass`, `fail`, or `did_not_run` |
| `detail` | one line. What ran, what it exited, how long it took. |
| `evidence` | the command on pass. The last 20 lines of output on fail, plus the log path. |

Empty stdin is legal. A gate that needs a command then reports `did_not_run`.

## Exit 78 is the one people get wrong

Exit 78 means the check did not happen. A gate that cannot run never reports a pass it did
not verify.

| Cause | Result |
|---|---|
| `gates.<name>.enabled` is `false` | `did_not_run` |
| The `commands.*` entry is null or missing | `did_not_run` |
| The first word of the command is not on PATH | `did_not_run` |
| The command exited 127, so something it invokes is not installed | `did_not_run` |
| The command uses `{files}` and no files are in scope | `did_not_run` |
| The command exceeded `limits.gate_timeout_seconds` | `did_not_run` |

A timeout is `did_not_run`, not `fail`. The command never finished, so neither a pass nor a
fail was observed. Sending a timeout to the fix loop as a failure makes the builder chase a
defect that may not exist. Send it to `/hyperpower:doctor` instead.

Exit 127 is the same case. `hp_tool_check` only checks the first word, so `npx tsc` or
`FOO=1 tsc` passes that check and still fails to find `tsc`. The gate reads 127 as a
missing dependency, not as a type error.

Do not exit 0 for any row in that table.

## Blocking

`gates.<name>.blocking` is the caller's decision, not the gate's. A non-blocking gate that
fails still writes `"result":"fail"` and still exits 1. It appends
`Advisory: gates.<name>.blocking is false.` to `detail` so the caller can see why the run
continued.

A missing `enabled` is treated as `true`. A missing `blocking` is treated as `true`. Only
the literal value `false` turns either off.

Do not make a gate exit 0 because it is non-blocking. That is a false pass.

## Inputs

Config comes from stdin. Everything else comes from the environment.

| Variable | Default | Purpose |
|---|---|---|
| `HYPERPOWER_FILES` | git diff against HEAD, plus untracked files | whitespace-separated scope for `{files}` |
| `HYPERPOWER_FILES_FILE` | unset | a file holding one path per line. Use this when a path contains a space. |
| `HYPERPOWER_ROUTE` | unset | value for `{route}` |
| `HYPERPOWER_RUN_DIR` | unset | run journal folder. Full output is copied to `<dir>/gates/<gate>.log`. |
| `HYPERPOWER_REPO_ROOT` | `git rev-parse --show-toplevel` | directory the command runs in |

`{files}` and `{route}` are the only template variables. Each path is single-quoted before
substitution.

The scope is filtered twice: paths that no longer exist on disk are dropped, and paths
under `paths.ignore` are dropped. `paths.source` is not applied, because test files often
live outside it.

## Config read

Only these fields are read. Never add a field that is not in `docs/configuration.md`.

| Field | Used for |
|---|---|
| `commands.typecheck`, `commands.test_scoped`, `commands.lint`, `commands.build` | the command each gate runs |
| `gates.<name>.enabled` | `false` means `did_not_run` |
| `gates.<name>.blocking` | `false` adds the advisory note to `detail` |
| `gates.slop.profile` | `core` or `standard`. `strict` is refused. |
| `limits.gate_timeout_seconds` | per-command timeout. Default 600. |
| `paths.ignore` | paths dropped from the `{files}` scope |

Parsing prefers `jq`. Without `jq` it falls back to an awk JSON flattener in `_lib.sh`.
Neither is required to be installed for the other to work.

## The slop gate

`slop.sh` runs both static tools over the scoped files.

1. Read `gates.slop.profile`. Default `core`. Refuse `strict` with exit 78.
2. Exit 78 when either `antislop` or `ai-slop-detector` is missing from PATH.
3. Run both tools. Concatenate their output into one log.
4. Fail if either exits non-zero. Name which one in `detail`.
5. Pass only when both exit 0.

Both tools are the check. One of them missing means half the check did not happen, so the
gate reports `did_not_run`. `/hyperpower:doctor` prints the install command.

Use `core` here. `standard` belongs in `/hyperpower:sweep`. `strict` fights the codebase.

## Adding a gate

1. Copy `types.sh`. Change the gate name and the `commands.*` key.
2. Source `_lib.sh` and call `hp_init <name>` before anything else.
3. Call `hp_pass`, `hp_fail`, or `hp_did_not_run`. They emit the JSON and exit.
4. Register it under `gates:` in `hyperpower.yml`.
5. Run `/hyperpower:doctor` to verify it executes.

Write POSIX `sh` with `set -eu`. Print nothing to stdout except the result object. Send
diagnostics to stderr.

See [docs/gates.md](../../../docs/gates.md) for the gate table and the blocking rules.
