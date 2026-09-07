---
name: why
description: Report what a recorded run decided and what it assumed. Reads .hyperpower/runs/<run-id>/ and nothing else. Use /hyperpower:why <run-id>, with --assumptions for assumption status and --rejected for options that were considered and dropped. Read the refuted list first - those are assumptions that were wrong and shipped code anyway.
---

# Why

Report what a run decided and what it assumed. Read the run journal. Report nothing else.

This command is read-only. It never replays a step, never re-reads source to reconstruct a reason, and never writes to the run folder.

## The rule

Every line of output comes from a file in `.hyperpower/runs/<run-id>/`. If the journal does not record a reason, say the journal does not record it.

A reconstructed reason reads exactly like a recorded one and is worth nothing.

## Step 1 - resolve the run

`<run-id>` is optional. Without it, use the most recently modified directory under `.hyperpower/runs/`.

| Problem | Do |
|---|---|
| `.hyperpower/runs/` does not exist | report that no runs are recorded. Stop. Do not create it. |
| named run id has no directory | list the recorded run ids, newest first, capped at five. Stop. |
| directory exists but has no `meta.json` | report the run as incomplete, then read whatever step files are there. |

## Step 2 - read the journal

| File | Holds |
|---|---|
| `meta.json` | base sha, task class, model tiers used, config hash |
| `<step>.json` | that step's output contract, including its `assumptions` array |
| `corrections.jsonl` | corrections applied by `/hyperpower:correct` |
| `mistakes.jsonl` | failure events appended during the run |

Step files, in pipeline order: `route`, `understand`, `plan`, `design`, `build`, `gates`, `review`, `fix`, `render`.

A missing step file means the stage was skipped. Report it as skipped. A skipped stage is not a failure and not a pass.

## Step 3 - render the default view

No flags. One line per recorded step, then the assumption tally.

```
Run 4f2a - task class feature, base sha a3f19c2
  Understand   read 6 files under src/api/
  Plan         chose server-side masking before serialization
  Build        3 files changed, 2 tests added
  Gates        types ok, unit ok, lint warned, slop ok
  Review       2 findings CONFIRMED, 1 REFUTED
  Assumptions  4 declared: 1 refuted, 1 unresolved, 2 verified
```

Print the assumption tally even when every assumption verified. Its absence is what a reader would misread as zero assumptions.

## `--assumptions`

Group by status. Print `refuted` first, then `unresolved`, then `verified`, then `declared`. Never sort by id, never sort alphabetically.

Print one line above the list: read the refuted list first, because those are assumptions that were wrong and shipped code anyway.

| Status | Means | What to do |
|---|---|---|
| `refuted` | the check re-read `checkable` and the claim was false | read first. Code shipped on a wrong claim. |
| `unresolved` | the check ran and could not decide, or `checkable` is null | verify by hand |
| `verified` | the check re-read `checkable` and the claim held | nothing |
| `declared` | the check has not run. The run did not reach Gates. | nothing yet |

Per assumption, print the id, status, claim, `declared_at`, `source`, and `checkable`.

```
REFUTED  a1  settings API returns a bare array
         declared at plan, source inferred, checkable src/api/settings.ts
         /hyperpower:correct 4f2a plan a1 "..." --scope run
```

Print the `correct` line for `refuted` and `unresolved` only. Never for `verified`.

## `--rejected`

Options that were considered and dropped, with the reason for each.

Read per step, in this order, and stop at the first source with content:

1. The `rejected` array in that step's `<step>.json`
2. Decision records under `memory.decisions_dir` whose frontmatter `run` matches this run id, section "Options rejected"

A step with no recorded options prints `no options recorded`. Do not infer what it might have weighed.

Findings the skeptic marked REFUTED are review findings, not rejected options. Report them on the Review line of the default view. Do not put them in this list.

## Config

If `hyperpower.yml` exists at the repo root, read it and use `memory.decisions_dir` and the `voice.*` flags. Without it, use `decisions/`, shape the output anyway, and do not ask the user to create the file.

## Output

Rank, never cap. Show five per list, then `+N more`, and name the flag that shows the rest. The full list stays in the contract.

Rank assumptions by status first, then lowest `confidence` first inside a status.

## Do not

- Do not read source code to explain a decision. The journal is the record.
- Do not replay a step, and do not write anything into the run folder.
- Do not soften a refuted assumption or print it below the verified ones.
- Do not report a skipped stage as a failure, and do not report it as a pass.
- Do not print token counts or money here. Those are `/hyperpower:usage` and `/hyperpower:cost`.
