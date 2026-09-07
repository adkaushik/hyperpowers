---
name: scout
description: Log product and engineering opportunities noticed while working - bug risks, tech debt, test gaps, perf, ux, feature ideas. Every entry must cite evidence from the actual work. Writes to .hyperpower/backlog.jsonl. Run it when a task is done, or on demand with /hyperpower:scout.
---

# Scout

Log what a human engineer would have noticed while writing this code, and would have filed for the product or engineering team to review later.

Do not brainstorm. Read the work that was actually done and report what it revealed.

## The rule

Every entry cites evidence: a file:line, a failing command, a test that does not exist, a review finding, or a run journal step. No evidence, no entry.

An entry without evidence is slop. Drop it rather than write it.

## Where the evidence comes from

Check these in order. Stop when you have enough for three entries.

1. `.hyperpower/runs/<run-id>/` if it exists - gate failures, refuted assumptions, fix-loop rounds above 1, findings marked PLAUSIBLE that were out of scope
2. `git diff $(git merge-base HEAD origin/<default-branch>)` and `git status --porcelain` - what changed. Read the default branch from `git symbolic-ref refs/remotes/origin/HEAD`. Do not hardcode `main`.
3. For each changed source file, whether a matching test file exists
4. `CODEBASE_RULEBOOK.md` or `.claude/rules/` - deviations the work had to route around
5. Suppressed lint or type errors in the diff

Signals worth an entry:

| Signal | Category |
|---|---|
| A gate or test was worked around instead of fixed | tech-debt |
| An assumption turned out wrong, or could not be checked | bug-risk |
| The same module needed more than one fix round | tech-debt |
| A real defect was found but left out of scope | bug-risk |
| A changed file has no test | test-gap |
| Something measured slow, not guessed slow | perf |
| An a11y or design gate flagged something out of scope | ux |
| Work revealed a missing capability users will ask for | feature |

## Categories

Six only: `bug-risk`, `tech-debt`, `test-gap`, `perf`, `ux`, `feature`.

Use `perf` only when a number was measured. Never on suspicion.

## Sheet format

Append to `.hyperpower/backlog.jsonl`. Create the file and directory if missing.

```json
{"key":"settings-api-untyped","category":"tech-debt","title":"Settings API response is untyped","evidence":["src/api/settings.ts:34 returns any","run 4f2a assumption a1 refuted"],"cost":"1-2 hours","benefit":"Removes a class of runtime shape bugs","occurrences":1,"first_seen":"2026-09-07","last_seen":"2026-09-07","status":"open"}
```

`key` is a stable kebab-case slug. It is how dedup works.

## Dedup

Before writing, read the whole sheet.

- Key already present and `status` is `open`: increment `occurrences`, append the new evidence, update `last_seen`. Do not add a row.
- Key already present and `status` is `rejected`: write nothing. A rejected idea does not come back.
- Key is new: add a row with `occurrences: 1`.

`occurrences` is the priority signal. Do not add a priority field.

## Config

If `hyperpower.yml` exists at the repo root, read it and use `paths.source`,
`paths.ignore`, and `limits.scout_max_new_per_run`. Without it, use the defaults below and
do not ask the user to create one.

## Caps

`limits.scout_max_new_per_run` new keys per invocation, default 3. If you have more candidates, rank by evidence strength and keep the top N. The rest will resurface through `occurrences` on later runs.

Existing-key increments do not count against the cap.

## Output

Regenerate `.hyperpower/backlog.md` from the JSONL, sorted by `occurrences` descending, grouped by category.

Then report to the user in at most five lines: what was added, what was incremented, nothing else.

## Do not

- Do not file to Linear, Jira, GitHub issues, or any shared tracker. The sheet stays in the repo. The human promotes.
- Do not suggest fixes for things already in the current scope. Those are the task, not the backlog.
- Do not write entries about style preferences.
