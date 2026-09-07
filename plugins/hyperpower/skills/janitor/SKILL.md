---
name: janitor
description: Log codebase hygiene debt found while touching files - outdated and deprecated dependencies, unused packages, files still on a pattern the repo has migrated away from, lockfile drift. Runs cheap tools first, LLM only to scope. Writes to .hyperpower/hygiene.jsonl. Use /janitor, or /janitor --all for a full sweep.
---

# Janitor

Report what maintenance the touched code needs. Scoped to the current diff by default, so it stays cheap.

Deterministic tools first. Use the model only to decide what matters and what it would cost.

## Scope

Default: files and dependencies touched by `git diff main...HEAD` plus uncommitted changes.

`--all`: whole repo. Slower. Only when asked.

## Step 1 - detect the toolchain

Read lockfiles to pick the package manager: `pnpm-lock.yaml`, `package-lock.json`, `yarn.lock`, `bun.lockb`, `uv.lock`, `poetry.lock`, `requirements.txt`, `go.sum`, `Cargo.lock`.

Do not assume npm.

## Step 2 - run what already exists

Prefer tools the repo already configures over anything you install.

| Check | Command |
|---|---|
| Outdated direct deps | `<pm> outdated` |
| Deprecated packages | `<pm> ls` output, or the `deprecated` field on the registry entry |
| Unused deps and exports | `knip` if `knip.json` exists |
| Type coverage holes | `tsc --noEmit` if TypeScript |
| Lockfile drift | lockfile modified without its manifest, or the reverse |
| Engine mismatch | `engines` in package.json vs `.nvmrc` or CI config |

Never install a tool to run a check. If it is not configured, skip that check and say so.

## Step 3 - find unmigrated files

The repo has patterns it has moved away from. Find files still on the old one.

How to identify the old pattern, in order:
1. `CODEBASE_RULEBOOK.md` or `.claude/rules/` if they name a preferred pattern
2. The last 50 commits - a pattern being replaced shows up as many small similar diffs
3. Two implementations of the same thing where one is clearly newer and more common

Report only files inside the current scope, unless `--all`.

## Categories

Five only: `dep-outdated`, `dep-deprecated`, `dep-unused`, `unmigrated`, `config-drift`.

## Sheet format

Append to `.hyperpower/hygiene.jsonl`. Create the file and directory if missing.

```json
{"key":"react-router-v5","category":"unmigrated","title":"6 files still on react-router v5 API","evidence":["src/routes/Settings.tsx:12","src/routes/Billing.tsx:9"],"effort":"half day","risk":"low","blocked_by":null,"occurrences":1,"first_seen":"2026-09-07","last_seen":"2026-09-07","status":"open"}
```

Set `blocked_by` when an upgrade needs another one first. Name that key.

## Dedup

Same rule as scout. Read the sheet before writing.

- Existing open key: increment `occurrences`, append evidence, update `last_seen`.
- Existing rejected key: write nothing.
- New key: add with `occurrences: 1`.

For dependency entries, also update the version in the title when it changes. Do not create a second key for the same package.

## Config

If `hyperpower.yml` exists at the repo root, read it and use `paths.source`,
`paths.ignore`, and the matching `limits.*` cap. Without it, use the defaults below and do
not ask the user to create one.

## Caps

Maximum five new keys per invocation, scoped mode. Ten with `--all`.

Group by package, not by file. One key for "6 files on react-router v5", not six keys.

## Output

Regenerate `.hyperpower/hygiene.md` sorted by category, then `occurrences` descending.

Report in at most five lines. Lead with anything marked `dep-deprecated`, since those stop getting security fixes.

## Do not

- Do not upgrade anything. This agent only reports.
- Do not open PRs.
- Do not report transitive dependencies. Direct dependencies only, unless a transitive one is deprecated and reachable.
- Do not report a major version bump as if it were routine. Note it as `risk: high`.
