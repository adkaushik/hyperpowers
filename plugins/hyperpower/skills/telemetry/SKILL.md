---
name: telemetry
description: Show what the harness records, stop or start recording, or delete every recorded run. Everything is local - there is no remote destination in the codebase and no opt-in that would create one, and telemetry.destination accepts exactly one value, local. purge deletes all recorded telemetry and reports the file count. Use /hyperpower:telemetry [status|off|on|purge].
---

# Telemetry

Nothing leaves this machine.

There is no remote destination in the codebase. There is no opt-in that would create one.
`telemetry.destination` accepts exactly one value: `local`.

Everything recorded is a file inside the repository. The user can read it, diff it, and
delete it.

## Subcommands

| Subcommand | Does |
|---|---|
| `status` | what is recorded, where, and how much. The default when none is given. |
| `off` | stop recording. Deletes nothing. |
| `on` | start recording. Backfills nothing. |
| `purge` | delete every recorded run, then report the file count |

## What is recorded

| Path | Holds | Committed |
|---|---|---|
| `.hyperpower/runs/<id>/meta.json` | base sha, task class, model tiers, config hash | no |
| `.hyperpower/runs/<id>/<step>.json` | that step's contract and its assumptions | no |
| `.hyperpower/runs/<id>/usage.jsonl` | one line per model call, plus gate results | no |
| `.hyperpower/runs/<id>/mistakes.jsonl` | failure events from that run | no |
| `.hyperpower/runs/<id>/corrections.jsonl` | corrections applied by `/hyperpower:correct` | no |
| `.hyperpower/runs/<id>/resume.jsonl` | one line per `/hyperpower:resume` replay | no |
| `.hyperpower/runs/<id>/gates/<gate>.log` | full output of each gate command | no |
| `.hyperpower/backlog.jsonl`, `.hyperpower/hygiene.jsonl` | scout and janitor sheets | yes |
| `.hyperpower/promotions.jsonl` | one line per promoter action | yes |

The sheets and the promotion log are committed because people review them. They are not
telemetry, and `purge` does not touch them.

## status

Print without asking. Show the source file for each config value, using the same labels as
`/hyperpower:config`: `hyperpower.yml`, `hyperpower.local.yml`, `default`.

```
Telemetry - local only. Nothing is uploaded.
  enabled          true          hyperpower.yml
  destination      local         fixed. No other value is accepted.
  redact_paths     true          hyperpower.yml
  runs recorded    37
  files            412  (18.4 MB)
  oldest record    2026-07-02
  newest record    2026-09-07
```

| Case | Do |
|---|---|
| no `hyperpower.yml` | print `default` for all three fields, say `/hyperpower:init` has not run here, and report what is on disk. Do not create the file. |
| `.hyperpower/runs/` missing | report zero runs and zero files. Do not create the directory. |
| `enabled` is false | print the status, then say new runs are not being recorded |

## off and on

Write `telemetry.enabled` to `hyperpower.local.yml`. Recording is a per-machine choice.
Do not edit the committed `hyperpower.yml`, which would change it for everyone on the team.

1. Read `hyperpower.local.yml`. Create it holding only `telemetry.enabled` if it is absent.
2. Set that one field. Leave every other field untouched.
3. Print the effective value and the file it came from.

`off` deletes nothing. `on` backfills nothing. The gap stays a gap, and
`/hyperpower:usage` reports the window as it is.

The harness still runs with telemetry off. `usage` and `cost` then report only what was
recorded before it was turned off.

If `hyperpower.local.yml` is not gitignored, say so and print the line to add. Do not edit
`.gitignore` from this command.

## purge

Deleting is irreversible here. Run folders are gitignored, so git cannot restore them.

1. Count the files and run folders under `.hyperpower/runs/`, with total size and date range.
2. Print that count, then name what goes and what stays.
3. Ask for an explicit yes. Wait for it.
4. Delete `.hyperpower/runs/` and recreate nothing.
5. Report the file count and the run folder count removed.

Never delete before step 3. Never delete anything outside `.hyperpower/runs/`.

| Removed | Kept |
|---|---|
| every run folder, including `meta.json`, step contracts, `usage.jsonl`, `mistakes.jsonl`, `corrections.jsonl`, `resume.jsonl`, and the `gates/` logs | `decisions/`, `CODEBASE_RULEBOOK.md`, `backlog.jsonl`, `hygiene.jsonl`, `promotions.jsonl`, the config files |

Say the consequence before asking. The mistakes log lives inside the run folders, so purging
removes the evidence the promoter counts toward a rulebook rule. Rules already promoted stay
in the rulebook.

```
Purged 412 files across 37 run folders.
Kept decisions/, CODEBASE_RULEBOOK.md, and the backlog and hygiene sheets.
```

## Path redaction

When `telemetry.redact_paths` is true, hash a file path before it enters any aggregate view:
`/hyperpower:usage`, `/hyperpower:cost`, and this command's output.

Hash rule: the first 8 hex characters of the SHA-256 of the repo-relative path, printed as
`path:9f2a1c04`. The same path hashes the same way every time, so grouping still works.

Per-run journals keep real paths. They already live inside the repo they describe, so
hashing them removes usefulness and adds no privacy.

Redaction is not anonymity. Anyone holding the repo can hash a path and compare. It stops a
path leaking through a view that gets pasted elsewhere. Say that when asked, rather than
implying more.

When the config is absent, treat `redact_paths` as true.

## Do not

- Do not add a remote destination, an upload step, a webhook, or an API key field. If asked
  for one, say no destination exists and stop.
- Do not purge without an explicit yes, and never delete outside `.hyperpower/runs/`.
- Do not write `telemetry.enabled` into the committed `hyperpower.yml`.
- Do not invent a config field. `telemetry` has three: `enabled`, `destination`,
  `redact_paths`.
- Do not report a purge count you did not measure. Count the files before and after.
