# Kernel tests

Run them:

```sh
plugins/hyperpower/tests/run-tests
```

Exit 0 means every assertion passed. Exit 1 means one failed, a case crashed, or a case
wrote inside this repository.

| Flag | Does |
|---|---|
| `--only PATTERN` | run the cases whose file name matches. No wildcard means substring. |
| `--verbose` | print every assertion, and each case's own output |
| `--keep` | leave the scratch directories on disk and print where they are |
| `--list` | print the cases that would run, then stop |

```sh
plugins/hyperpower/tests/run-tests --only hp-gates --verbose
```

`hp-selfcheck` and `run-tests` check different things. `hp-selfcheck` checks the plugin
against its own documentation. `run-tests` runs the scripts and reads what they did.

## What is covered

| Case | Checks |
|---|---|
| `cases/hp-config.sh` | every yaml block in `docs/configuration.md` parses, exit 78 with no config, `HYPERPOWER_REPO_ROOT`, local overrides, the config hash |
| `cases/hp-journal.sh` | reproducible run ids, the step contract round trip, the cache key byte for byte, drift, and every record shape in `JOURNAL.md` |
| `cases/hp-gates.sh` | the three exit codes, disabled gates, the run journal it writes |
| `cases/gates.sh` | every gate script exits 78, not 0, when it cannot run |
| `cases/hp-validate.sh` | a valid contract passes, an invalid one reports every violation |
| `cases/hp-redact.sh` | paths are removed, the fields an aggregate groups by survive, the token is stable |
| `cases/hp-selfcheck.sh` | the shipped tree passes, and each planted fault is caught by its check |
| `cases/task-classes.sh` | `task-classes.yml`, `schemas/route.json` and `schemas/plan.json` name the same classes |
| `cases/run_evals.sh` | `validate` passes, `score` refuses unpaired rows |

### Assert against the document, not against a copy of it

Three things are read out of the documentation at test time rather than restated in a case:
the yaml blocks in `docs/configuration.md`, the record shapes in `scripts/JOURNAL.md`, and
the check count in `docs/architecture.md`.

The reason is drift. A restated key list passes while the writer and the document disagree,
which is the failure the case existed to catch. Read the document with `yaml-blocks`,
`md-jsonl-keys`, or a `grep`, and the case fails when either side moves.

Do not restate a documented shape in a case. Read it.

## The rule

A test never writes inside this repository. Not the plugin, not `docs/`, not the working
tree it was launched from.

Every case gets its own git repository under a temporary directory, its own `HOME`, and its
own `TMPDIR`. Write there, through `$HP_TEST_REPO` and `$HP_TEST_TMP`. The runner removes
both when the case ends, and checks this repository afterwards for the paths a stray case
would leave: `hyperpower.yml`, `.hyperpower/`, `CODEBASE_RULEBOOK.md`, `decisions/`, and any
`__pycache__/` or `.pyc` an import left behind. Any of them appearing fails the run with
`POLLUTION`.

Bytecode is on that list because it is gitignored. `git status` stays clean while the
plugin directory fills up, so the runner looks for it directly.

The runner also drops `GIT_DIR`, `GIT_WORK_TREE`, `GIT_INDEX_FILE` and the rest of the git
plumbing variables before it builds anything. A hook, `git rebase --exec` and `git bisect
run` all export them. Left in place they aim the scratch repo's own `git init`, `git add
-A` and `git commit` at the caller's repository, and the caller's uncommitted work lands
there in a commit named `scratch`. `POLLUTION` does not catch that: it reads paths, not
commits.

Read from the plugin freely. `$HP_PLUGIN`, `$HP_SCRIPTS`, `$HP_SCHEMAS`, `$HP_GATES_DIR`
and `$HP_DOCS` are read-only inputs. Never write to them, and never pass one as a `--root`.

A case that needs to break the plugin copies `$HP_DOCS` and `$HP_REPO/plugins` into
`$HP_TEST_TMP` and breaks the copy. `cases/hp-selfcheck.sh` is the worked example. Never
plant a fault in the tree the suite is running from.

## Adding a case

One file per script under test, named after it: `cases/<script>.sh`. A new file is
discovered on the next run. No registration step.

```sh
#!/bin/sh
# hp-thing: what the case proves, in one sentence.
set -eu

case ${1:-} in
  --help|-h)
    printf '%s\n' \
      'hp-thing.sh - one hyperpower kernel test case.' \
      'It needs the scratch repo and the helper library tests/run-tests builds.' \
      'Run it with: tests/run-tests --only hp-thing'
    exit 0
    ;;
esac
. "$HP_TEST_LIB"

t_run "$HP_PYTHON" "$HP_SCRIPTS/hp-thing" --flag
t_status "hp-thing exits 0 on a valid input" 0
t_eq "hp-thing prints the run id" "4f2a" "$(t_out)"
```

The `--help` block comes before the library is sourced. A case run by hand has none of the
variables the library needs, so it says how to run it instead of failing on an unset one.

Rules:

1. Name the assertion for the property, not the step. `"a disabled gate does not produce
   78"`, never `"test 4"`. The name is what the failure report prints.
2. Assert on a behaviour the docs state. A test of an undocumented detail blocks a change
   that was allowed.
3. Do not stop at the first failure. Every assertion runs, so one broken behaviour does not
   hide the next.
4. Do not assert a timestamp, a temporary path, or a duration. They change every run.
5. Skip honestly. `t_skip` records a reason and the summary counts it. Never record a pass
   for a check the machine could not make.

### Environment

| Variable | Holds |
|---|---|
| `HP_TEST_REPO` | the case's scratch git repo, already committed, with `hyperpower.yml` |
| `HP_TEST_TMP` | scratch space for the case |
| `HP_TEST_LIB` | the helper library to source. Written by `run-tests`, not a file here. |
| `HP_PYTHON` | the interpreter running the suite |
| `HP_SCRIPTS` | `plugins/hyperpower/scripts` |
| `HP_SCHEMAS` | `plugins/hyperpower/schemas` |
| `HP_GATES_DIR` | `plugins/hyperpower/gates` |
| `HP_PLUGIN` | `plugins/hyperpower` |
| `HP_DOCS` | `docs/` |
| `HP_REPO` | the repository root. Read only, and never a `--root`. |

The scratch repo starts with every gate disabled, `src/a.txt`, `src/b.txt`, and one commit.
A case that needs a gate turns that one on.

### Running a script

`t_run` captures stdout, stderr and the exit status into `$T_OUT`, `$T_ERR` and
`$T_STATUS`. Set `T_CWD` to run elsewhere and `T_STDIN` to feed a file. Both reset after
each call.

| Wrapper | Runs |
|---|---|
| `t_hp_config` | `hp-config` |
| `t_hp_journal` | `hp-journal` |
| `t_hp_validate` | `hp-validate` |
| `t_hp_gates` | `hp-gates`, with `HYPERPOWER_REPO_ROOT` set to the scratch repo |
| `t_hp_evals` | `run_evals.py` |

### Assertions

| Helper | Passes when |
|---|---|
| `t_eq NAME EXPECTED ACTUAL` | the two strings match |
| `t_ne NAME UNWANTED ACTUAL` | they do not |
| `t_ge NAME MIN ACTUAL` | the number is at least the minimum |
| `t_status NAME CODE` | the last `t_run` exited with that code |
| `t_stdout_has NAME NEEDLE` | stdout holds the substring |
| `t_stderr_has NAME NEEDLE` | stderr holds it |
| `t_stderr_lacks NAME NEEDLE` | stderr does not |
| `t_file_has NAME FILE NEEDLE` | the file holds it |
| `t_file_lacks NAME FILE NEEDLE` | it does not |
| `t_file NAME PATH` | the file exists |
| `t_dir NAME PATH` | the directory exists |
| `t_no_file NAME PATH` | nothing is at the path |
| `t_json NAME FILE PATH VALUE` | the JSON value at the dotted path matches |
| `t_in NAME NEEDLE LIST` | the needle is in the comma-joined list |
| `t_ok NAME` / `t_bad NAME DETAIL` / `t_skip NAME REASON` | recorded directly |

### Reading data

`t_tool` runs the query helper the runner writes beside the case.

| Command | Prints |
|---|---|
| `json-get FILE PATH` | one value. Dotted path, list indices are digits. |
| `json-keys FILE PATH` | sorted comma-joined keys of an object |
| `json-members FILE PATH [--no-null]` | sorted comma-joined members of a list |
| `yaml-get` / `yaml-keys` / `yaml-members` | the same three, through `hp-config`'s own parser |
| `jsonl-get FILE N PATH` | one value from line N, counting from 1 |
| `jsonl-keys FILE N` | sorted comma-joined keys of line N |
| `jsonl-count FILE` | non-empty lines |
| `gate-field FILE GATE FIELD` | one field of one gate record in an `hp-gates` aggregate |
| `yaml-blocks DOC OUTDIR` | writes every fenced yaml block, prints the count |
| `md-jsonl-keys DOC SECTION N` | sorted keys of the Nth jsonl record fenced under a `##` heading |
| `md-jsonl-get DOC SECTION N PATH` | one value from that record |
| `cache-key PROMPT UPSTREAM FILES` | the cache key `JOURNAL.md` specifies, computed here |
| `contract SCHEMA [--run-id R] [--drop F] [--extra F] [--enum-break F] [--assumption ID]` | the smallest instance a schema accepts, optionally broken three ways |

A missing value prints `<missing>`. Compare against that rather than against an empty
string.

Read YAML through `yaml-get` and friends, never with a parser written in the case. They go
through `hp-config`, so a case reading `task-classes.yml` exercises the parser the harness
ships.

## Requirements

Python 3.8 or newer, a POSIX shell, and git. No pytest, no bats, no third-party module, and
no `jq`. The helper library and the query tool are written into each case's scratch
directory by `run-tests`; they are not files in this directory.
