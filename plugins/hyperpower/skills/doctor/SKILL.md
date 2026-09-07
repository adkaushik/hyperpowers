---
name: doctor
description: Re-verify every hyperpower gate and tool in this repo. Runs each gate command once, reports what is broken with the exact fix, and re-enables a gate that now works. Run after editing hyperpower.yml, upgrading dependencies, or switching machines. Use /hyperpower:doctor.
---

# Doctor

Re-run init steps 5 and 6. Verify every gate command, report what is broken and the exact fix, and re-enable any gate that now works.

Doctor writes exactly two fields: `gates.<name>.enabled` and `gates.<name>.reason`. It never edits commands, paths, models, limits, or the rulebook.

No `hyperpower.yml` at the repo root: print `No hyperpower.yml. Run /hyperpower:init.` and stop. Do not guess a config.

## Step 1 - load the effective config

```sh
hp-config --source > /tmp/hp-doctor-config.json
```

`${CLAUDE_PLUGIN_ROOT}/scripts/hp-config` does the merge. Verify what the merge produced, not what either file says alone. Do not parse either YAML file yourself: a second parser verifies a config no run ever used.

Exit 78 means there is no `hyperpower.yml`. Exit 1 means a file did not parse; print the file, the line, and the error from stderr, then stop.

`sources` in the envelope maps every leaf to the file it came from, so report the file each verified command came from without guessing. A local override that changes `commands.test_scoped` is the command doctor runs.

## Step 2 - check the toolchain

Check the binaries a command needs before running it. A missing binary is a "did not run", not a failure.

| Check | How |
|---|---|
| Package manager on PATH | `which <project.package_manager>` |
| Dependencies installed | `node_modules/`, `.venv/`, `vendor/`, or `target/` present for the detected manager |
| Lockfile drift | manifest modified more recently than the lockfile |
| Slop tools | `which antislop`, `which ai-slop-detector` |
| Dev URL reachable | one HTTP request to `commands.dev_url`, only when `gates.browser` or `gates.visual` is enabled |

## Step 3 - run every gate command

```sh
hp-gates --only <gate> --files <one-existing-file> --route / --config /tmp/hp-doctor-probe.json --json
```

`${CLAUDE_PLUGIN_ROOT}/scripts/hp-gates` is the runner `/hyperpower:run` uses. Run gates through it, one `--only` call per gate, so doctor verifies the same execution path a real run takes. Do not invoke `commands.<name>` directly, and do not write `gates.json`: doctor is a probe, not a run, so pass no `--run` and let it record nothing.

1. Probe every gate, enabled and disabled alike. Write `/tmp/hp-doctor-probe.json` as the Step 1 config with every `gates.<name>.enabled` forced to `true`, and pass it with `--config`. A gate script's disabled exit would otherwise mask the result, and that is how a gate gets re-enabled.
2. `limits.gate_timeout_seconds` from the same file caps each command. `hp-gates` enforces it and sets `timed_out` on the gate record.
3. Substitute `{files}` with one existing file from `paths.tests` or `paths.source` via `--files`. Substitute `{route}` with `/` via `--route`. An empty `--files` scope makes a `{files}` gate report `did_not_run` instead of running against the whole repo.
4. Read `gates[0].result` from the JSON, not the exit code. `pass` is a pass. `did_not_run` means the check did not happen: write `enabled: false` and a `reason` taken from that record's `detail`, which already names the cause. `fail` means the gate works and the code does not: it stays enabled.
5. Never run `commands.install`. Print it as the fix instead.

A failing test suite is a working gate. Report it as `fail`, leave it enabled, and do not write a reason.

## Step 4 - re-enable what works

A gate with `enabled: false` and a `reason` was disabled by init or doctor. When its command now runs, set `enabled: true`, delete the `reason`, and list it under Re-enabled.

A gate with `enabled: false` and no `reason` was turned off by a human. Leave it alone. Report it under Off by choice. Do not re-enable it, and do not ask about it.

## Step 5 - report

Four blocks in this order, then one next command. Skip an empty block rather than printing a header with nothing under it.

1. **Broken** - gate, cause, exact fix. One line each.
2. **Re-enabled** - gate, and what changed.
3. **Live** - gate, result `pass` or `fail`, blocking or warning.
4. **Off by choice** - gate names only.

```
Broken  1
  slop    antislop not on PATH        fix: pipx install antislop

Re-enabled  1
  lint    eslint resolves now, was "eslint not installed"

Live  4
  types   pass   blocking
  unit    fail   blocking   3 tests failing
  build   pass   blocking
  lint    pass   warning

Off by choice  3
  browser, a11y, visual

Next
  Run pipx install antislop, then /hyperpower:doctor again.
```

Every fix string is runnable as printed.

| Cause | Fix printed |
|---|---|
| Binary not on PATH | the install command for that tool |
| Dependencies missing | `commands.install` from the config, printed, not run |
| Exit 127 | `commands.<name>` names a binary that does not exist. Correct it in hyperpower.yml. |
| Timeout | raise `limits.gate_timeout_seconds`, or scope the command with `{files}` |
| `dev_url` not reachable | start `commands.dev_server`, or set `gates.browser.enabled: false` |

Rank, never cap. More than five broken gates: show five and say how many remain.

## Do not

- Do not fix anything. Doctor reports and toggles gate enablement. It does not install, upgrade, or edit commands.
- Do not report a gate as passing when its command did not run.
- Do not re-enable a gate that has `enabled: false` and no `reason`.
- Do not run `commands.install`, or any install or upgrade command.
- Do not regenerate the rulebook. That is `/hyperpower:init --refresh`.
