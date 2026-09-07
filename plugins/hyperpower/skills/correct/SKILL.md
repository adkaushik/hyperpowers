---
name: correct
description: Correct a recorded assumption in a run. Takes a run id, a step, an assumption id, the correction text, and --scope once|run|forever. forever is promoted into the rulebook and writes a rulebook diff for approval first. If the correction contradicts code the harness can read, it says so once and then obeys.
---

# Correct

```
/hyperpower:correct <run> <step> <assumption-id> "<text>" --scope <once|run|forever>
```

Four positional arguments, all required, then `--scope`. A missing `--scope` stops and asks for it. Do not pick a default scope.

## Scopes

| Scope | Applies to | Writes | Needs approval |
|---|---|---|---|
| `once` | the next replay of that one step | `corrections.jsonl` in the run folder | no |
| `run` | every remaining step in this run | `corrections.jsonl` in the run folder | no |
| `forever` | every run in this repo | `corrections.jsonl`, then `CODEBASE_RULEBOOK.md` | yes |

`forever` needs approval because the rulebook is shared and loaded on every run. `once` and `run` touch one run folder, so they apply without asking.

## Step 1 - find the assumption

Read `.hyperpower/runs/<run>/<step>.json`. Find the id in its `assumptions` array.

| Problem | Do |
|---|---|
| run directory or step file missing | list what the run recorded. Stop. |
| id not in that step's array | list the ids in that step. Stop. |
| id exists, but in a different step | name that step. Stop. Do not correct it from here. |

Never create an assumption that was not declared. This command edits an existing record.

## Step 2 - challenge once

Read the assumption's `checkable` target. One read. If `checkable` is null, skip this step and apply.

If the code contradicts the correction, print the challenge, then obey it.

```
Correction contradicts src/api/settings.ts:34.
  You said:  settings API returns { items: [] }
  Code says: return rows;
Applying anyway. Scope: run.
```

1. Cite `file:line` and quote the line as written. No paraphrase.
2. Challenge once. Not a second time, not at a later step, not after applying.
3. The challenge is a statement, not a question. Do not ask the human to confirm it.
4. Never refuse the correction. The human decides.
5. If the code agrees, or `checkable` is null, print nothing and apply.

## Step 3 - apply

Every scope does these three, in order.

1. Append to `.hyperpower/runs/<run>/corrections.jsonl`. Create the file if missing.

```json
{"run":"4f2a","step":"plan","assumption":"a1","key":"settings-api-shape","text":"settings API returns { items: [] }","scope":"run","challenged":true,"ts":"2026-09-07T11:04:12Z"}
```

2. Set that assumption's `status` to `refuted` in `<step>.json`. A human correction means the recorded claim was wrong.
3. Append to `.hyperpower/runs/<run>/mistakes.jsonl`, so the promoter can count the repeat.

```jsonl
{"run":"4f2a","kind":"assumption_refuted","key":"settings-api-shape","ref":".hyperpower/runs/4f2a/corrections.jsonl"}
```

`key` is a stable kebab-case slug describing the claim, not the assumption id. Ids are per-run. Keys are how a repeat is counted across runs.

Who reads the correction back:

| Scope | Read by |
|---|---|
| `once` | the next replay of that step. Then set `applied: true` and never read it again. |
| `run` | every step replayed after it in this run |
| `forever` | every step in this run, and every future run through the rulebook |

## Step 4 - forever writes a rulebook diff

Print the diff. Wait for an answer. Write nothing to `CODEBASE_RULEBOOK.md` until it arrives.

```
Rulebook diff for approval — CODEBASE_RULEBOOK.md

+ Settings API returns { items: [] }. Never treat it as a bare array.
+   source: correction, run 4f2a, step plan, assumption a1

At 30 of 30 rules. Adding this evicts the weakest:
- Prefer named exports in src/api/     (0 preventions in 20 runs)

[approve / edit / cancel]
```

1. Read the cap from `limits.rulebook_max_rules`. Use 30 when the config is absent.
2. At the cap, name the rule to evict. Weakest means fewest preventions in the last 20 runs.
3. Never exceed the cap, and never raise `limits.rulebook_max_rules` to fit a rule.
4. An evicted rule moves to the archive under `memory.decisions_dir`. It is demoted, not deleted.
5. `edit` reprints the diff with the new wording and asks again. `cancel` writes nothing to the rulebook and leaves the correction in force at `run` scope. Report that it did.

`memory.promoter: false` disables the promoter agent. It does not disable a `forever` correction. They are two separate writers of the rulebook.

## Config

| Missing | `once` | `run` | `forever` |
|---|---|---|---|
| `hyperpower.yml` | works | works | works, with the default cap of 30 |
| `CODEBASE_RULEBOOK.md` | works | works | records the correction at `run` scope, then reports that no rulebook exists and names `/hyperpower:init` |

Do not create `CODEBASE_RULEBOOK.md` here. `init` generates it from a repo scan.

## Do not

- Do not challenge twice, and do not re-open a challenge the human answered by proceeding.
- Do not refuse to apply a correction.
- Do not write `CODEBASE_RULEBOOK.md` without an explicit approval.
- Do not invent an assumption id, and do not correct an id in a step the user did not name.
- Do not apply a `once` correction more than once.
