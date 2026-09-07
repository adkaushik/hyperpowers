---
name: decisions
description: Search the decision archive in decisions/ - why things in this repo are the way they are. This command is the only thing that reads the archive; it is never loaded into a run's context. Filter with --by human|human_directed|agent_autonomous|agent_proposed_approved, or --stale for decisions whose reversal_condition is now true. Use /hyperpower:decisions [query].
---

# Decisions

Search the decision archive. Report what matched. Write nothing.

This command is the only way the archive gets read. No run loads it, no agent reads it, no hook injects it, and nothing summarises it into `CODEBASE_RULEBOOK.md`. That is why the archive can be unbounded: it costs a normal run zero tokens until someone asks a question.

The rulebook holds how to behave here, and is capped. The archive holds why things are the way they are, and is not. Do not merge the two.

## Config

| Field | Default | Use |
|---|---|---|
| `memory.decisions_dir` | `decisions/` | the directory to search |
| `paths.ignore` | `[]` | paths treated as absent when checking a `reversal_condition` |

Read `hyperpower.yml` at the repo root, then `hyperpower.local.yml` over it, field by field. Without either file, use the defaults and do not ask the user to create one.

If the directory does not exist, report `no decision archive yet` and stop. Do not create it. The archivist writes it after a run.

## Flags

| Flag | Does |
|---|---|
| `[query]` | free text, matched against `question` and `chose` before anything else |
| `--by <who>` | `human`, `human_directed`, `agent_autonomous`, `agent_proposed_approved` |
| `--stale` | records whose `reversal_condition` is now true |

Flags compose. `--by agent_autonomous --stale` is valid. No flags and no query lists the newest ten records.

`--by agent_autonomous` is the audit list: decisions the harness made without anyone asking the human. Read it first on any repo whose runs you did not watch.

A `decided_by` value outside those four is legacy. Group it under `other` and report it. Do not rewrite it, and do not drop it.

## Step 1 - grep frontmatter first

Match on frontmatter lines. Open files only after they hit.

```bash
grep -rl --include='*.md' '^decided_by: agent_autonomous' decisions/
grep -rn --include='*.md' -i -e '^question:' -e '^chose:' decisions/ | grep -i 'masking'
```

Widen to the record body only when the frontmatter pass returns fewer than five files. That is the one exception. Never read every file in the directory to answer a query.

## Step 2 - open only the matches

Open at most ten files. Rank before opening, strongest match first:

1. `id` contains the query
2. `question` contains the query
3. `chose` contains the query
4. body contains the query

Within a tier, newest `id` date first.

## Step 3 - --stale

Two sources, labelled differently in the output.

| Source | Label | Cost |
|---|---|---|
| `status: stale` in the frontmatter | `marked` | free, already decided by `/hyperpower:gc` |
| `status: active` whose `reversal_condition` you can check now | `checked` | one read per record |

A condition is true only when a file, symbol, or command output in the current working tree satisfies it. Name what you read. A condition about the future, about intent, or about anything outside the repo is not checkable. Uncheckable is not stale, and it is not reported.

Check at most 20 active records per invocation, newest first. Say how many were not checked.

This command never writes `status`. Marking a record stale is the gardener's job. Point the user at `/hyperpower:gc`.

## Output

Exclude `status: superseded` by default and say how many were hidden. The exception is a query that names an exact `id`, which shows the record whatever its status.

```
7 decisions match "masking". Showing 5, 2 more. 1 superseded hidden.

2026-09-07-preview-masking-location    active   agent_autonomous   run 4f2a
  Q  Where does field masking happen for preview mode?
  A  server-side masking before serialization

2026-06-18-masking-location            active   human_directed     run 2b90
  Q  Do masked fields keep their length?
  A  fixed-width mask, eight characters

Open one: decisions/2026-09-07-preview-masking-location.md
```

`--stale` output names the evidence on every `checked` line:

```
3 stale of 41 active. 6 active not checked.

2026-03-11-token-scale     marked    gc on 2026-08-02
  Revisit if the design system ships a type scale.
2026-04-02-preview-route   checked   src/routes/preview.tsx exports getServerSideProps
  Revisit if preview moves server-side.
```

## Compacted files

`<memory.decisions_dir>/compacted/<head-id>.md` holds folded chains written by the gardener. Ancestor frontmatter sits in fenced YAML blocks inside the body, not at the top of the file. A grep hit inside one is an ancestor, not the head.

Report it as `compacted/<head-id>.md # <ancestor-id>` and say it is superseded.

## Do not

- Do not read the archive from any other command, agent, or hook. One reader, on command.
- Do not write, edit, or delete a record. The archivist and `/hyperpower:gc` are the writers.
- Do not open every file to answer a query.
- Do not mark a record stale here. Report it and stop.
- Do not treat an uncheckable `reversal_condition` as true.
