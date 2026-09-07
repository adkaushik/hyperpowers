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

Recompute the cache key for every recorded step up to and including the one named by `--from`. Compare each against the key recorded in that step's contract.

Skip paths matched by `paths.ignore`. Count files, not hunks and not lines.

## Step 3 - report drift

Use this format exactly. Two-space indent, step names padded to a common width.

```
Resume run 4f2a from Gates.
  Understand   ok
  Plan         ok
  Build        DRIFTED — 3 files changed since this step
Re-run from Build instead? [build / gates-anyway / abort]
```

1. `ok` is lowercase. `DRIFTED` is uppercase. No emoji, no colour words, no tick marks.
2. A drifted line ends with the file count and nothing after it.
3. An `ok` line carries no count.
4. Print every step, including clean ones. The clean lines are what make the drifted one readable.
5. The prompt offers the earliest drifted step, then `<requested-step>-anyway`, then `abort`.

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
2. Append one line to `.hyperpower/runs/<run-id>/resume.jsonl` with the timestamp, the `--from` step, the answer taken, and the drifted step names.
3. Leave `meta.json`, `mistakes.jsonl`, `usage.jsonl`, and `corrections.jsonl` in place. They are the run's history.

Never keep `review.json` when `build.json` was invalidated. A review of a superseded build is the exact failure this command exists to prevent.

## Step 6 - replay

Replay the invalidated steps in pipeline order. Each writes a fresh `<step>.json` with a newly computed cache key.

Corrections in `corrections.jsonl` apply during the replay: `scope: once` entries to the next replay of their own step, `scope: run` and `scope: forever` entries to every step replayed after them.

Use the model tiers in the current `models` config, not the tiers recorded in `meta.json`. When they differ, say so in the output.

Stop when a blocking gate fails. Report the gate, the command, and the exit code. Do not continue to Review after a blocking gate failure.

## Config

If `hyperpower.yml` exists at the repo root, read it and use `paths.ignore`, `models`, `gates`, and `limits.gate_timeout_seconds`.

Without it, print the drift report and stop. Replay needs the gate commands, and the harness does not guess them. Tell the user to run `/hyperpower:init`.

## Do not

- Do not replay before printing the drift report.
- Do not treat `<requested-step>-anyway` as a default, and do not list it first.
- Do not invalidate partially, and do not keep a downstream contract because it still looks valid.
- Do not edit files to remove drift. This command reports drift. It does not resolve it.
- Do not key a step on the prompt alone.
