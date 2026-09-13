# scripts

Twelve executables. Python 3.8 or newer, standard library only. No third-party imports, and
no network access.

The first five are the kernel. Skills and agents call them rather than parsing YAML, hashing
files, validating contracts, or writing the run journal themselves, because a second
implementation of any of those drifts from the first and nothing in the output shows it.
The next six each back one command. `run_evals.py` has its own section below.

| Script | Does | Exit codes | Reference |
|---|---|---|---|
| `hp-config` | merges `hyperpower.yml` and `hyperpower.local.yml`, prints the effective config, the per-field source, and the config hash | 0 printed, 1 bad input or a file that does not parse, 78 no config | `--help`, `docs/configuration.md` |
| `hp-journal` | writes and reads `.hyperpower/runs/<run-id>/` | 0 done, 1 bad input or a failed write, 78 no config | `JOURNAL.md` |
| `hp-validate` | checks a stage contract against `schemas/<stage>.json` | 0 valid, 1 invalid, 2 usage, 78 no schema | `../schemas/README.md` |
| `hp-gates` | runs every enabled gate, records the aggregate | 0 every blocking gate passed, 1 a blocking gate failed, 78 a blocking gate could not run, 2 hp-gates could not run | `--help`, `../gates/README.md` |
| `hp-selfcheck` | checks the plugin against its own documentation, 14 checks | 0 clean, 1 findings, 2 bad usage | `--list-checks` |
| `hp-redact` | hashes file paths in run records before they reach an aggregate view | 0 emitted, 1 bad input, 2 usage | `--help`, `docs/commands.md` |
| `hp-status` | reports whether the harness is on here, and what a live run is doing | 0 reported, 1 no run to report on, 2 bad input, 78 no config | `--help`, `../skills/status/SKILL.md` |
| `hp-visualize` | builds an HTML report of a session from its logs | 0 written, 1 nothing to report, 2 bad input, 78 no logs | `--help`, `../skills/visualize/SKILL.md` |
| `hp-help` | prints every command in plain language, grouped by when you would use it | 0 printed, 1 the help table and `skills/` disagree, 2 bad input | `--help`, `../skills/help/SKILL.md` |
| `hp-pr` | fetches a pull request into a throwaway worktree for review | 0 resolved, 1 no such PR, 2 bad input, 78 `gh` missing or not logged in | `--help`, `../skills/review/SKILL.md` |
| `hp-app` | keeps the conductor's app record in `<state>/app.json` | 0 done, 1 no app recorded, 2 bad input, 78 not inside a repository | `--help`, `../skills/build/SKILL.md` |

Each carries its own `--help` with the full flag list. The sibling documents named above are
the contracts; this table is the index.

```sh
./hp-config --source
./hp-journal new --task-class feature
./hp-validate --list
./hp-gates --run <run> --files src/a.ts --config config.json --json
./hp-selfcheck --strict
```

`hp-selfcheck --strict` is what CI runs. Run it before opening a pull request. It catches a
skill with no `docs/commands.md` section, a gate script with no schema entry, an agent the
index is missing, a model id with no price, and a task class that one of
`task-classes.yml`, `schemas/route.json`, and `schemas/plan.json` names and the others do
not. It also fails when `/hyperpower:help` misses a command.

## run_evals.py

`run_evals.py` validates, runs, and scores the eval suite.

```sh
./run_evals.py validate
./run_evals.py run --baseline-cmd '<command>' --candidate-cmd '<command>' --trials 3
./run_evals.py score --run .hyperpower/evals/<run-id>
```

| Subcommand | Does |
|---|---|
| `validate` | checks `cases.jsonl` is well formed and every required field is present |
| `run` | writes blind-labelled rows, and generates responses when a command is given |
| `score` | aggregates judged rows, enforces pairing, prints the release verdict |

## validate

| Flag | Default | Does |
|---|---|---|
| `--cases` | `evals/cases.jsonl` | file to check |
| `--all` | off | print every error, not the first five |

Checks each line: valid JSON object, all five fields present, unique lowercase `id`, known
`category`, known `risk`, prompt of 20 characters or more, and 2 to 6 criteria strings. It
warns on an unknown field and on a category with no cases.

## run

| Flag | Default | Does |
|---|---|---|
| `--baseline-cmd`, `--candidate-cmd` | none | shell command per condition. The prompt arrives on stdin, the response is read from stdout. |
| `--baseline`, `--candidate` | `baseline`, `candidate` | condition names |
| `--control`, `--control-cmd` | none | optional third condition, labelled `C` |
| `--trials` | 3 | trials per case per condition |
| `--seed` | random | seed for label shuffling. Recorded in the manifest. |
| `--timeout` | 600 | per-response timeout in seconds |
| `--out` | `.hyperpower/evals/<run-id>` | output directory. `--force` overwrites a non-empty one. |

Without a command it writes the prompts and stops. Produce the responses yourself, then
judge. That is the degraded path, not an error.

Labels are shuffled per row, so a judge reading a response file cannot tell which condition
produced it.

| File written | Holds |
|---|---|
| `manifest.json` | run id, digests, weights, trials, seed, config summary, rows. No condition names. |
| `key.json` | the label to condition map, and the commands. Do not open it before judging. |
| `prompts/`, `responses/` | one file per row, named by label |
| `scores.template.jsonl` | one blank score row per response |

## score

| Flag | Default | Does |
|---|---|---|
| `--run` | none | run directory. Supplies the manifest, the key, and `scores.jsonl`. |
| `--scores` | `<run>/scores.jsonl` | judged rows |
| `--baseline`, `--candidate` | from `key.json` | which conditions to compare |
| `--baseline-file` | none | compare against a recorded baseline instead of baseline rows |
| `--record-baseline` | none | write the candidate aggregate to this path as the new baseline |
| `--record-baseline-condition` | the candidate | record a different condition instead |
| `--json` | none | write the full result as JSON |

A score row resolves its condition from the `condition` field, or from `label` plus the
run's `key.json`. A row with neither is an error.

## Refusals

The script stops rather than print a number that is not comparable.

| Refusal | Cause |
|---|---|
| Unpaired conditions | the candidate was not judged on the same rows as the baseline. The message names the missing rows and the condition each is missing from. |
| Duplicate rows | two score rows for the same case, trial, and condition. The message names both line numbers. |
| Cases drift | `cases.jsonl` changed since the run or the baseline was recorded |
| Rubric drift | `rubric.md` changed since the run or the baseline was recorded |
| Bad weights | the weights table in `rubric.md` does not total 100, or is missing a dimension |

Weights are parsed from the weights table in `evals/rubric.md`. The rubric is the
authority. A missing rubric falls back to the built-in weights and says so.

## Exit codes

| Code | Means |
|---|---|
| 0 | valid, or the release verdict passed |
| 1 | bad input, or a refusal. Nothing was aggregated. |
| 2 | the release verdict failed. The numbers are printed and the reasons are numbered. |

## Config

Reads `hyperpower.yml`, then merges `hyperpower.local.yml` per field. Only these fields,
and only from the schema in `docs/configuration.md`.

| Field | Used for |
|---|---|
| `project.name` | labelling the run manifest |
| `models.judgment`, `models.mechanical` | recorded in the manifest, then compared against the baseline for the same-models clause |
| `voice.adhd_shaping`, `voice.plain_english` | reported at run time. Render conformance is scored either way, so scores stay comparable. |

No config file is not an error. Model tiers are recorded as unknown, the public comparison
clause reports `no`, and the run proceeds.

## Do not

- Do not open `key.json` before the scores are written. That unblinds the run.
- Do not pass `--force` to reuse a run directory you have already judged.
- Do not compare conditions judged on different rows. The script refuses; do not work
  around it by deleting the extra rows.
- Do not edit the weights in this script. Edit the table in `evals/rubric.md`.
