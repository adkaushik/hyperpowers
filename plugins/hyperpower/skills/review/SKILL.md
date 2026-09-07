---
name: review
description: Partition the current diff into coherent slices, run one hyperpower:reviewer per slice, then send one hyperpower:skeptic at every finding. Reports CONFIRMED and PLAUSIBLE findings, ranked and never capped in the contract. A PLAUSIBLE finding is never dropped for want of a reproduction. Use /hyperpower:review.
---

# Review

Partition the diff. One reviewer per slice. One skeptic per finding. Report CONFIRMED and PLAUSIBLE.

You orchestrate. You do not review the code yourself and you do not fix anything.

About four minutes on a ten-file diff. Reviewers run in parallel, then skeptics run in parallel.

## The rule

Every changed file lands in exactly one slice, or in `left_out` with a reason. A file in neither is a partition bug.

Count the changed files before dispatch. Count the files across all slices plus `left_out` after. The two numbers must match. If they do not, fix the partition before spawning anything.

## Step 1 - resolve the diff and the run

1. Base sha: `git merge-base HEAD origin/<default-branch>`. No remote default branch: use `git rev-parse HEAD` and record that in `notes`.
2. Changed files: `git diff --name-only <base_sha>`, plus `git status --porcelain` for uncommitted work.
3. Run id: the newest directory under `.hyperpower/runs/` whose `meta.json` base sha matches. No match: use `run_id: null` and print the report only. Do not create a run folder for a standalone review.
4. Empty diff: say there is nothing to review and stop. Do not review the last commit instead.

## Step 2 - partition into slices

Cut on subsystems and seams. Two to six slices.

| Cut on | Example |
|---|---|
| Subsystem | API routes, data layer, UI components, build config |
| Seam | a route and the client that calls it, together in one slice |
| Contract | a schema and the migrations that change it |
| Ownership | one package of a monorepo |

Never cut by file count, alphabetically, or into equal sizes. A slice exists so one reviewer can hold it in context, not so the work divides evenly.

Fewer than two coherent groups: run one slice and record that in `notes`. More than six groups: merge the smallest adjacent ones until six. Six reviewers is the cost ceiling.

For each slice, compute the blast radius: files outside the slice that call or import the changed code. Run `rg` on the changed symbol names. The blast radius is read-only context for the reviewer.

Partitioning is a mechanical stage. Run it on `models.mechanical`.

## Step 3 - one reviewer per slice

Spawn `hyperpower:reviewer` once per slice, all in one message, so they run in parallel.

| Field | Value |
|---|---|
| `run_id` | from step 1, or null |
| `slice_id` | `s1`, `s2`, unique within this review |
| `files` | the files in this slice, and no others |
| `base_sha` | from step 1 |
| `blast_radius` | callers and dependents outside the slice |
| `assumptions` | the upstream contract's `assumptions` array, or `[]` |

`hyperpower:reviewer` is the plugin namespace plus the `name` in `agents/reviewer.md`, which is the bare `reviewer`. Spawn the namespaced form. If it does not resolve, stop and report that the plugin's agents are not registered. Never fall back to a bare `reviewer`: that resolves to a same-named agent in the user's own `~/.claude/agents/`, which does not know this contract and returns output this pipeline cannot read. That failure is silent, so the review will look like it ran.

Merge the returned findings. Two reviewers on the two sides of one seam report the same defect twice. Deduplicate on `file`, `line`, and `class`, keeping the higher severity and both evidence lists. One skeptic per finding, not one per report.

## Step 4 - one skeptic per finding

Spawn `hyperpower:skeptic` once per finding, all in one message. Resolve the name the same way.

| Field | Value |
|---|---|
| `run_id` | from step 1, or null |
| `finding` | exactly one finding |
| `base_sha` | from step 1 |
| `slice_files` | the files of that finding's slice |

| Verdict | Goes to |
|---|---|
| `CONFIRMED` | the report, ranked first, with the trace |
| `PLAUSIBLE` | the report, ranked after CONFIRMED, with what is undecidable |
| `REFUTED` | the contract only, with the grounds. Not the report. |

PLAUSIBLE findings are never dropped, and never for want of a reproduction. Integration-seam bugs land in this bucket: the two sides disagree, no single file is wrong, and no test covers the pair. That is the expensive class. Report every one.

Collateral defects a skeptic found while reading enter the findings list with `status: unverified`. Do not spawn a second skeptic round on them. One adjudication round per review.

## Step 5 - contract and render

Write the contract to `.hyperpower/runs/<run_id>/review.json` when a run id resolved. With `run_id: null`, hold it in the reply and say it was not written.

```json
{"step":"review","run_id":"4f2a","base_sha":"a3f19c2",
 "slices":[{"slice_id":"s1","files":["src/api/settings.ts"],"result":"ok"}],
 "left_out":[{"file":"pnpm-lock.yaml","reason":"generated, matched paths.ignore"}],
 "findings":[],"assumptions":[],"notes":[]}
```

`assumptions` is required. Emit `[]` when this review declared none: `hp-validate review`
rejects a contract without the array, and an absent array reads to `/hyperpower:why` as
zero assumptions declared, which is a different fact. Carry an upstream assumption forward
with its original `id`, `claim`, and `declared_at`.

Rank the full list: CONFIRMED before PLAUSIBLE, then severity high to low, then slice order. Never sort by slice first.

Rank, never cap. Show the top five, then say how many remain and where the rest are. The cap applies to this view only. The contract keeps every finding.

```
Review  12 files, 4 slices, 7 findings
  CONFIRMED  high    src/api/settings.ts:34       204 response yields undefined, .map throws
  CONFIRMED  medium  src/hooks/useSettings.ts:12  cache key not updated after the rename
  PLAUSIBLE  high    src/pay/webhook.ts:88        depends on the payments API error shape
  PLAUSIBLE  medium  src/queue/worker.ts:21       ordering depends on scheduling
  CONFIRMED  low     src/api/settings.ts:51       error path returns 200
  +2 more. Full list in .hyperpower/runs/4f2a/review.json.

Left out  1
  pnpm-lock.yaml   generated, matched paths.ignore

Next
  5 CONFIRMED findings go to the fix loop. 2 PLAUSIBLE need a human decision.
```

## Config

Read `hyperpower.yml`, then `hyperpower.local.yml` over it. Without either, partition the diff as given and do not ask the user to create one.

| Field | Used for | If absent |
|---|---|---|
| `paths.ignore` | files that go to `left_out`, not to a slice | put every changed file in a slice |
| `paths.source` | which files are reviewable source | review every changed file |
| `models.mechanical` | the partition stage | partition here |
| `models.judgment` | the reviewer and skeptic stages | the agent files set their own model |

## Do not

- Do not review the code yourself. You partition, dispatch, adjudicate, and render.
- Do not spawn a reviewer on the whole diff, or a skeptic on a batch of findings.
- Do not drop a PLAUSIBLE finding, and never because there is no reproduction.
- Do not cap the findings list in the contract. Cap the rendered view only.
- Do not fix anything. A CONFIRMED finding goes to the fix loop.
