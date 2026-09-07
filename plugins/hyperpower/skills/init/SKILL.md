---
name: init
description: Set up hyperpower in this repository - detect the stack, ask at most six questions, write hyperpower.yml, generate CODEBASE_RULEBOOK.md, verify every gate command. Run once per repo with /hyperpower:init. Safe to re-run; it fills gaps and never overwrites a value a human wrote.
---

# Init

Set up this repository. Six steps, in order. Do not skip a step and do not reorder them.

Detect first. Ask only what detection could not settle. Every question carries a detected default, so pressing enter is a valid answer.

About five minutes on a first run. Under a minute on a repo with clean CI config.

| Flag | Does |
|---|---|
| `--refresh` | run steps 4, 5, 6 only. Regenerate the rulebook, keep the config. |
| `--no-interview` | run steps 1, 3, 4, 5, 6. Skip every question. Detected values plus defaults. |

Under `--refresh`, step 5 may still flip `gates.<name>.enabled` and write `gates.<name>.reason`. Those two fields are verification results, not choices.

## Step 1 - detect, ask nothing

Read every signal below before asking anything.

| Signal | Read from |
|---|---|
| Repo root, default branch, remote | `git rev-parse --show-toplevel`, `git symbolic-ref refs/remotes/origin/HEAD`, `git remote -v` |
| Package manager | the lockfile. See the table below. |
| Languages | tracked file extensions by volume: `git ls-files` |
| Monorepo layout | `workspaces` in package.json, `nx.json`, `turbo.json`, `pnpm-workspace.yaml`, `[workspace] members` in Cargo.toml |
| Test framework | dev dependencies, plus `vitest.config.*`, `jest.config.*`, `pytest.ini`, `pyproject.toml`, `go.mod` |
| Build and dev commands | `scripts` in the manifest, `Makefile`, `justfile`, `Taskfile.yml` |
| Existing conventions | `CLAUDE.md`, `AGENTS.md`, `.claude/rules/`, `.editorconfig`, lint config |
| CI commands | `.github/workflows/*.yml`, `.gitlab-ci.yml`, `.circleci/config.yml` |

### Package manager

| Lockfile | `project.package_manager` |
|---|---|
| `pnpm-lock.yaml` | pnpm |
| `package-lock.json` | npm |
| `yarn.lock` | yarn |
| `bun.lockb` | bun |
| `uv.lock` | uv |
| `poetry.lock` | poetry |
| `go.sum` | go |
| `Cargo.lock` | cargo |
| `Gemfile.lock` | bundler |

Two or more lockfiles present: take the one with the newest modification time, and name the choice in the step 6 report. Do not ask.

No lockfile: leave `package_manager` null and disable every gate whose command you could not detect.

### Languages

Count tracked files per extension, excluding the default ignore list in step 3. List every language above 5% of tracked source files, most files first. Vendored directories are not languages.

### CI is the best source

What CI runs is what the repo actually treats as a gate. The `scripts` block accumulates commands nobody runs; the CI workflow is enforced on every push. When CI and the manifest disagree, take CI.

Precedence per command, highest first:

1. A CI workflow step
2. A `Makefile`, `justfile`, or `Taskfile.yml` target
3. A manifest script
4. A bare tool invocation you can see is installed

A command you did not read out of one of those four sources is null. Never invent a command. A null command means its gate is disabled in step 5 with a reason.

## Step 2 - ask, at most six questions

Skip any question detection already answered. A clean repo with CI config often gets two: gate blocking and model tiers.

Each question is multiple choice. The detected default is listed first and marked. Enter accepts it.

| # | Question | Ask only when |
|---|---|---|
| 1 | Project type | the inference table below matched zero types, or two |
| 2 | Which directories hold source the harness may edit | no single directory holds over 80% of source files |
| 3 | Which detected command is the real test command | two or more test-shaped commands were detected |
| 4 | Which gates block and which warn | CI does not already run the detected gate commands as required checks |
| 5 | Model tiers, one strong and one cheap | neither config file already sets both |
| 6 | Enable the browser and visual gates | a dev server command was detected |

Project type inference:

| Signal | `project.type` |
|---|---|
| `nx.json`, `turbo.json`, `pnpm-workspace.yaml`, or workspace members | monorepo |
| A UI framework dependency and no server entrypoint | web-frontend |
| A server framework dependency, or a `main` that binds a port | backend |
| A `bin` field, or a `cmd/` directory | cli |
| Xcode project, `android/`, or a Flutter manifest | mobile |
| A published manifest with no `bin` and no server | library |

Defaults: question 4 blocks `types`, `unit`, `build`, `slop` and warns on `lint`. Question 5 takes `claude-opus-5` and `claude-haiku-4-5`. Question 6 is off.

Do not ask a seventh question. Do not ask anything an existing `hyperpower.yml` already answers. Do not ask open-ended questions; every question is a fixed list of choices.

## Step 3 - write hyperpower.yml

Write `hyperpower.yml` at the repo root, using the exact schema in `docs/configuration.md`. Write every top-level key: `version`, `project`, `paths`, `commands`, `gates`, `models`, `limits`, `memory`, `telemetry`, `voice`.

Rules, in order:

1. No existing file: write all keys. Detected values where detection succeeded, the defaults below everywhere else.
2. Existing file: read it, then fill only keys that are absent or null. Never overwrite a value a human wrote. Never delete a key you do not recognise.
3. `--refresh`: do not touch this file, except `gates.<name>.enabled` and `gates.<name>.reason` from step 5.

Defaults for anything not detected:

| Key | Default |
|---|---|
| `project.type` | `other` |
| `paths.source` | `[src/]` when `src/` exists, otherwise the largest source directory |
| `paths.ignore` | `[node_modules/, dist/, build/, .venv/, target/, vendor/]` |
| `models` | `judgment: claude-opus-5`, `mechanical: claude-haiku-4-5` |
| `limits` | `30`, `5`, `3`, `5`, `600` in schema order |
| `memory` | `decisions_dir: decisions/`, `archivist: true`, `promoter: true` |
| `telemetry` | `enabled: true`, `destination: local`, `redact_paths: true` |
| `voice` | `adhd_shaping: true`, `plain_english: true` |

`{files}` and `{route}` are the only template variables. Write `commands.test_scoped` and `commands.lint` with `{files}`. Never invent a third variable.

Never write a key that is not in the schema. Something you detected with nowhere to put it goes in the step 6 report, not the file.

### .gitignore entries

Append these three lines to `.gitignore` at the repo root, each only if it is not already there:

```
.hyperpower/runs/
.hyperpower/evals/
hyperpower.local.yml
```

`.hyperpower/evals/` is where `scripts/run_evals.py` writes eval run directories, including
every generated response. Create `.gitignore` if it does not exist. Do not reorder, rewrite,
or deduplicate the rest of the file. Do not ignore `.hyperpower/` as a whole: `backlog.jsonl`,
`hygiene.jsonl`, and `promotions.jsonl` live there and are committed.

## Step 4 - generate the rulebook

Write `CODEBASE_RULEBOOK.md` at the repo root. Cap at `limits.rulebook_max_rules` from the start, not after. This file loads on every run, so its size is a tax on every run.

Sources, highest authority first:

1. `CLAUDE.md` and `AGENTS.md`
2. `.claude/rules/`
3. Lint and formatter config
4. Observed patterns: a convention held by five or more files with no counterexample
5. `.editorconfig`

One rule per section. Every rule carries an id, one imperative sentence, one sentence of reason, and its source.

```markdown
## R7 - Fetch through src/api/client.ts
Never call fetch directly in a component. The client sets auth headers and retries on 429.
Source: observed, 14 call sites, 0 counterexamples.
```

More candidates than the cap: drop anything a tool already enforces, then rank by how many files the rule governs, then by how expensive the mistake is. Keep the top N.

Do not write a rule a linter already enforces; the linter runs and the rule only costs tokens. Do not write style preferences; the formatter owns those. Do not write a rule inferred from one file. Do not exceed the cap and plan to trim later.

## Step 5 - verify

Run every configured gate command once, for real. No dry run.

| Gate | Command run | Substitution |
|---|---|---|
| types | `commands.typecheck` | none |
| unit | `commands.test_scoped` | `{files}` = one existing test file |
| lint | `commands.lint` | `{files}` = one existing source file |
| build | `commands.build` | none |
| slop | `antislop --profile core`, then `ai-slop-detector` | none |
| browser, a11y, visual | skipped unless question 6 enabled them | `{route}` = `/` |

Question 6 not asked, or answered no: write those three gates as `enabled: false, blocking: false, reason: "no dev_url configured"`. That is the case under `--no-interview`.

Rules:

1. Time out each command at `limits.gate_timeout_seconds`.
2. Exit 0: the gate stays enabled.
3. Non-zero, but the command ran: the gate is live. A failing test suite is a gate doing its job. Leave `enabled: true`.
4. Command not found, exit 127, exit 78, missing module, or timeout: write `enabled: false` and a `reason`.
5. Never leave a gate enabled whose command you did not execute.

The distinction that matters: "the command ran and reported problems" keeps the gate. "The command could not run" disables it.

A reason names the cause and the fix:

```yaml
lint:    { enabled: false, blocking: false, reason: "eslint not installed. run: pnpm install" }
browser: { enabled: false, blocking: false, reason: "no dev_url configured" }
```

Never write a reason like "failed" or "did not work".

Do not run `commands.install`. Record it in the config, leave it unexecuted. Installing dependencies is a side effect the user did not ask for.

## Step 6 - report

Print these five blocks, in this order, and nothing else.

1. **Detected** - package manager, languages, layout, and where the gate commands came from
2. **Asked** - each question and the answer taken, marked `(default)` when enter was pressed
3. **Live gates** - name, command, blocking or warning
4. **Disabled gates** - name and reason, one line each
5. **Next** - one command

```
Detected
  pnpm, typescript + css, single package
  Gate commands from .github/workflows/ci.yml

Asked  2 questions
  Gates that block    types, unit, build, slop  (default)
  Model tiers         opus-5 / haiku-4-5        (default)

Live gates  4
  types   tsc --noEmit        blocking
  unit    pnpm vitest run     blocking
  build   pnpm build          blocking
  lint    pnpm eslint {files} warning

Disabled  1
  slop    antislop not on PATH. run: pipx install antislop

Next
  Fix slop, then run /hyperpower:doctor.
```

Rank, never cap. More than five disabled gates: show five and say how many remain.

The next command:

| State | Print |
|---|---|
| Every gate live | "Setup done. Give Claude a normal request." |
| One or more disabled | "Fix <cause>, then run /hyperpower:doctor." |
| No test command detected | "Set commands.test_scoped in hyperpower.yml, then run /hyperpower:doctor." |

## Do not

- Do not run `commands.install`, or any install, upgrade, or migration command.
- Do not mark a gate enabled when you could not run its command.
- Do not overwrite a value already present in `hyperpower.yml`.
- Do not invent a config key. The schema in `docs/configuration.md` is the whole surface.
- Do not ask a seventh question.
