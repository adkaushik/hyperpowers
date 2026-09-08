---
name: resume
description: Replay a recorded run from a chosen step. Re-hashes the working tree and reports per-step drift before doing anything else, then invalidates that step and everything downstream. Reads .hyperpower/runs/<run-id>/. Use /hyperpower:resume <run-id> --from <step>.
---

# Resume

Report drift first. Replay second. Never the other way round.

Order: load, re-hash, report, get an answer, invalidate, replay. The first three write nothing.

## The cache key

Each step's cache key is the hash of `(prompt, upstream contract, git tree sha of files read)`.

Not the prompt alone. Hashing the prompt alone would let a resumed run reuse a contract describing code that no longer exists, and review a fiction.

| Component | Read from |
|---|---|
| prompt | the `prompt_hash` recorded in that step's `<step>.json` |
| upstream contract | sha of the previous step's `<step>.json` as it is on disk now |
| files read | `git hash-object <path>` for every path in that step's `files_read`, sorted, hashed as one list |

Hash the working tree with `git hash-object`, not the commit with `git rev-parse HEAD:<path>`. An uncommitted edit is drift. A committed-only hash misses it.

A path in `files_read` that no longer exists is drift. Count it as one file.

## Step 1 - load the run

`--from <step>` is required. Steps in pipeline order: `route`, `understand`, `plan`, `design`, `build`, `gates`, `review`, `fix`, `render`.

| Problem | Do |
|---|---|
| run id has no directory | list recorded run ids, newest first, capped at five. Stop. |
| `--from` omitted | stop and ask for it. Do not pick a step. |
| `--from` names a step this run never recorded | list the steps it did record. Stop. |
| `config hash` in `meta.json` differs from the current config | treat every step as drifted. Gate commands may have changed. |

## Step 2 - re-hash the working tree

```sh
hp-journal drift <run> --from <step>
```

`${CLAUDE_PLUGIN_ROOT}/scripts/hp-journal` recomputes the cache key for every recorded step up to and including the one named by `--from`, compares each against the key recorded in that step's contract, skips paths matched by `paths.ignore`, and prints the report in Step 3's format. Add `--json` for the full comparison: per step `state`, `changed_files`, the changed file list, and a `drifted` object with a boolean for each of the three inputs.

Do not recompute the cache key yourself. `hp-journal hash` wrote it, and a second implementation of the same hash drifts from the first without anything in the output showing it. Run the command and read what it prints.

Count files, not hunks and not lines. A step with no recorded cache key prints `UNHASHED`, which is drifted, not `ok`.

## Step 3 - report drift

`hp-journal drift` prints this format. Do not reformat what it printed. Two-space indent, step names padded to a common width.

```
Resume run 4f2a from Gates.
  Understand   ok
  Plan         ok
  Build        DRIFTED — 3 files changed since this step
Re-run from Build instead? [build / gates-anyway / abort]
```

1. `ok` is lowercase. `DRIFTED` and `UNHASHED` are uppercase. No emoji, no colour words, no tick marks.
2. A drifted line names the file count when any file changed. When no file changed, it names the input that did: `DRIFTED — upstream plan.json changed since this step`, or `DRIFTED — prompt changed since this step`.
3. An `ok` line carries no count.
4. `UNHASHED — no cache key recorded for this step` means the step was never hashed. Treat it as drifted. It is not `ok`, and it is never replayed over.
5. A `config_hash` that no longer matches prints `Config hash changed since this run. Treat every step as drifted.` under the step lines.
6. Print every step, including clean ones. The clean lines are what make the drifted one readable.
7. The prompt offers the earliest drifted step, then `<requested-step>-anyway`, then `abort`. It prints only when a step earlier than the requested one drifted; when the requested step is itself the earliest drifted one, there is nothing to offer instead.

Option names are the lowercased step names. Requested step `Gates` gives `gates-anyway`. Requested step `Review` gives `review-anyway`.

No step drifted: print the report anyway, then replay without asking.

## Step 4 - take the answer

| Answer | Does |
|---|---|
| earliest drifted step, `build` above | invalidate that step and everything downstream, replay from there |
| `<requested-step>-anyway` | replay from the requested step, keeping the drifted upstream contract |
| `abort` | write nothing, exit |

`gates-anyway` stays available because sometimes the human's own edit was the fix.

It is never the silent default. Do not choose it because the drift is one file, because the change looks cosmetic, or because the user seems to be in a hurry. No answer means abort. A session that cannot ask prints the report and aborts.

## Step 5 - invalidate

Re-entering at step N invalidates step N and everything downstream. Never partial.

1. Move each invalidated `<step>.json` into `.hyperpower/runs/<run-id>/superseded/<timestamp>/`. Do not delete it.
2. Append one line to `.hyperpower/runs/<run-id>/resume.jsonl`. `hp-journal resume-event` is the writer, and it stamps the timestamp itself. Never append with a shell redirect.

```sh
hp-journal resume-event <run> --from gates --decision build --drifted build,review
```

`--decision` takes the answer Step 4 got: a step name, `<step>-anyway`, or `abort`. Anything else is refused with the vocabulary. `--drifted` takes the drifted step names, not a count. Record an `abort` too: a run aborted over drift is the fact the log exists to hold.
3. Leave `meta.json`, `mistakes.jsonl`, `usage.jsonl`, and `corrections.jsonl` in place. They are the run's history. Step 6 stamps `applied: true` on every `once` entry in `corrections.jsonl` that it applies, which is one per replayed step that carried one. That is the only edit this command makes to any of them.

Never keep `review.json` when `build.json` was invalidated. A review of a superseded build is the exact failure this command exists to prevent.

## Step 6 - replay

Replay the invalidated steps in pipeline order. Each writes a fresh `<step>.json` with a newly computed cache key.

Corrections in `corrections.jsonl` apply during the replay. Read them with `hp-journal corrections`, never off disk, so a malformed line is reported rather than silently skipped.

```sh
hp-journal corrections <run> --step plan --pending    # the once entries no replay has used
```

| Scope | Applies to | Then |
|---|---|---|
| `once` | the next replay of its own step, and only when the entry has no `applied: true` | stamp it with `hp-journal correction-applied <run> --step <step>` |
| `run` | every step replayed after it in this run | nothing. It stands for the life of the run |
| `forever` | every step replayed after it, and every future run through the rulebook | nothing. The rulebook carries it |

This command owns the `applied` field, and `hp-journal correction-applied` is the one writer of it. `/hyperpower:correct` writes the entry without it and never touches it. Nothing else writes it, so an unstamped `once` entry means the correction has not been used yet.

Order matters. Write the step's fresh `<step>.json` first, then call `correction-applied`. A replay that fails, aborts, or is interrupted before the contract lands leaves the entry unstamped, so the next replay applies the correction again. Stamping first drops the correction silently.

Do not rewrite `corrections.jsonl` by hand. `correction-applied` rewrites the one line under the same lock the append takes, keeps every other line byte for byte including one that does not parse, and skips an entry that already carries `applied: true`. A second implementation of that rewrite loses a correction appended while it runs.

Use the model tiers in the current `models` config, not the tiers recorded in `meta.json`. When they differ, say so in the output.

Stop when a blocking gate fails. Report the gate, the command, and the exit code. Do not continue to Review after a blocking gate failure.

## Config

Call `${CLAUDE_PLUGIN_ROOT}/scripts/hp-config --json` and use `paths.ignore`, `models`, `gates`, and `limits.gate_timeout_seconds` from what it prints. Do not parse `hyperpower.yml` yourself: `hp-config` is what the original run read, and a second parser can produce a different config hash from the same bytes.

Exit 78 means there is no `hyperpower.yml`. Print the drift report and stop. Replay needs the gate commands, and the harness does not guess them. Tell the user to run `/hyperpower:init`.

Replay the gates with `hp-gates --run <run> --files <changed,files> --config <path>`, the same runner `/hyperpower:run` uses. Do not run gate commands directly.

## Do not

- Do not replay before printing the drift report.
- Do not treat `<requested-step>-anyway` as a default, and do not list it first.
- Do not invalidate partially, and do not keep a downstream contract because it still looks valid.
- Do not edit files to remove drift. This command reports drift. It does not resolve it.
- Do not key a step on the prompt alone.
