---
name: gc
description: Run the gardener over the decision archive - mark stale records, merge near-duplicates, fold superseded chains, delete only records that are superseded and about files that no longer exist and older than six months. It compacts; it does not shrink the archive by guessing. Everything is in git, so a bad compaction is recoverable, which is why it writes without asking. Use /hyperpower:gc.
---

# GC

Run the gardener over the decision archive. No flags, no arguments.

About a minute on an archive under 100 records. It touches nothing outside `memory.decisions_dir`.

Run it when `/hyperpower:decisions` starts returning near-duplicate records. There is no schedule and no post-run trigger.

## What it changes

Four passes, in this order.

| # | Pass | Effect |
|---|---|---|
| 1 | mark stale | `status: active` becomes `status: stale` when the working tree satisfies `reversal_condition` |
| 2 | merge near-duplicates | same question, same answer, both active, becomes one record carrying both provenances |
| 3 | fold superseded chains | three or more linked records become `compacted/<head-id>.md`, head left in place |
| 4 | delete | only under all three conditions below |

Compaction exists to keep `/hyperpower:decisions` searchable. It does not exist to save space. The archive is unbounded on purpose.

## What it deletes

All three conditions must hold. Not two.

| # | Condition |
|---|---|
| 1 | `status: superseded` |
| 2 | every repo-relative path in the record is absent from the working tree, and there is at least one such path |
| 3 | the `id` date prefix is more than 183 days old |

A record that names no paths fails condition 2 and is never deleted. A commit sha in `artifacts.diff` is not a path, so it does not satisfy condition 2 on its own.

Never deleted, under any condition: an active record, a stale record, a merged record, `CODEBASE_RULEBOOK.md`, anything under `.hyperpower/runs/`, any `mistakes.jsonl`, and anything outside `memory.decisions_dir`.

Deletion runs through `git rm`. The gardener does not commit.

## Why it runs without asking

Every record is committed to git. A bad compaction is undone with `git checkout -- decisions/`. That is why the gardener writes without a confirmation prompt.

Recoverability is the reason it may write. It is not a reason to run it on a dirty tree. Step 1 exists because `git checkout` only recovers what was committed.

## Step 1 - preflight

Run `git status --porcelain <memory.decisions_dir>`. If it prints anything, stop and report:

```
Archive has uncommitted changes. Commit or stash decisions/ first, then re-run /hyperpower:gc.
```

Do not commit for the user. Do not stash for the user. There is no force flag; do not offer one.

If the directory does not exist, report `no decision archive yet` and stop. Do not create it.

## Step 2 - spawn the gardener

Spawn the `hyperpower:gardener` subagent once. Pass it `memory.decisions_dir` and `paths.ignore` from the effective config, and nothing else. No run id.

The gardener is the one background agent not on `models.mechanical`. Judging whether two records answer the same question, and whether a `reversal_condition` is satisfied, needs judgment. Do not override its model to save tokens.

Do the compaction through the agent. Do not edit records from this skill.

## Step 3 - report

Print what the gardener returns. Five lines maximum.

```
Compacted decisions/ - 4 changes.
  stale     2  (2026-03-11-token-scale, 2026-04-02-preview-route)
  merged    1  into 2026-06-18-masking-location
  folded    1  chain of 4 -> compacted/2026-07-02-auth-shape.md
  deleted   0
Review with: git diff decisions/
```

When nothing changed, print one line: `Archive is already compact. 0 changes.`

Then stop. Do not summarise the content of the records it touched. The diff is the record.

## Config

| Field | Default | Use |
|---|---|---|
| `memory.decisions_dir` | `decisions/` | the archive to compact |
| `paths.ignore` | `[]` | paths treated as absent when checking condition 2 |

Read `hyperpower.yml` at the repo root, then `hyperpower.local.yml` over it, field by field. Without either file, use the defaults and do not ask the user to create one.

No config field disables the gardener. `memory.archivist` and `memory.promoter` gate their own agents and have no effect here.

## Do not

- Do not run the gardener post-run, from a hook, or on a schedule. `/hyperpower:gc` only.
- Do not delete a record that fails any one of the three conditions.
- Do not merge two records whose `chose` values differ. Two answers to one question is a supersession the human has not made yet.
- Do not edit `question`, `chose`, `run`, or `decided_by` on any record.
- Do not commit, push, or amend. Leave one diff for the human to review.
