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

Every file under `.hyperpower/runs/<id>/` that `scripts/JOURNAL.md` lists: `meta.json`, the
step contracts, `usage.jsonl`, `mistakes.jsonl`, `corrections.jsonl`, `resume.jsonl`, and
the `gates/` logs. None of it is committed. Read the record shapes there, not here.

| Also under `.hyperpower/` | Holds | Committed |
|---|---|---|
| `backlog.jsonl`, `hygiene.jsonl` | scout and janitor sheets | yes |
| `promotions.jsonl` | one line per promoter action | yes |
| `redact-salt` | the salt that path tokens are derived from | no, and never |

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
  redaction        on            aggregate views only: usage, cost, this command
  salt             .hyperpower/redact-salt   present, gitignored
  runs recorded    37
  files            412  (18.4 MB)
  oldest record    2026-07-02
  newest record    2026-09-07

Redaction hashes file paths in grouped output. Run journals keep real paths. A free-text
field can still carry a path hp-redact does not recognise.
```

The last two lines are part of the status. Print them every time. A status that says
redaction is `on` and stops there reads as a promise the aggregate holds no paths.

Read the three config values through `hp-config --source`, which names the file each came
from. Read the salt state from disk: `present, gitignored` when `git check-ignore -q` exits
0, `present, NOT gitignored - add .hyperpower/redact-salt to .gitignore` when it exits 1,
`present` when git cannot answer, and `not derived yet - the next usage or cost run writes
it` when the file is absent.

| Case | Do |
|---|---|
| no `hyperpower.yml` | print `default` for all three fields, say `/hyperpower:init` has not run here, and report what is on disk. Do not create the file. |
| `.hyperpower/runs/` missing | report zero runs and zero files. Do not create the directory. |
| `enabled` is false | print the status, then say new runs are not being recorded |
| `redact_paths` is false | print `redaction off` and `usage and cost print real paths` beside it |

## off and on

Write `telemetry.enabled` to `hyperpower.local.yml`. Recording is a per-machine choice.
Do not edit the committed `hyperpower.yml`, which would change it for everyone on the team.

1. Read `hyperpower.local.yml`. Create it holding only `telemetry.enabled` if it is absent.
2. Set that one field. Leave every other field untouched.
3. Print the effective value and the file it came from.

`off` deletes nothing. `on` backfills nothing. The gap stays a gap, `/hyperpower:usage`
reports the window as it is, and the harness still runs with telemetry off.

If `hyperpower.local.yml` is not gitignored, say so and print the line to add. Do not edit
`.gitignore` from this command.

## purge

Deleting is irreversible here. Run folders are gitignored, so git cannot restore them.

1. Count the files and run folders under `.hyperpower/runs/`, with total size and date range.
2. Print that count, then name what goes and what stays.
3. Ask for an explicit yes. Wait for it.
4. Delete `.hyperpower/runs/` and recreate nothing.
5. Report the file count and the run folder count removed.

Never delete before step 3. Never delete anything outside `.hyperpower/runs/`. Every run
folder goes. Everything else stays: the committed rows above, `redact-salt`, `decisions/`,
`CODEBASE_RULEBOOK.md`, and the config files.

Say the consequence before asking. The mistakes log lives inside the run folders, so purging
removes the evidence the promoter counts toward a rulebook rule. Rules already promoted stay
in the rulebook.

```
Purged 412 files across 37 run folders.
Kept decisions/, CODEBASE_RULEBOOK.md, and the backlog and hygiene sheets.
```

## Path redaction

`${CLAUDE_PLUGIN_ROOT}/scripts/hp-redact` performs it. Nothing else hashes a path, and no
skill implements the rule a second time.

```sh
cat .hyperpower/runs/*/usage.jsonl | ${CLAUDE_PLUGIN_ROOT}/scripts/hp-redact --stdin
${CLAUDE_PLUGIN_ROOT}/scripts/hp-redact --stdin --explain < records.jsonl
```

Every aggregate view pipes its records through it before grouping: `/hyperpower:usage`,
`/hyperpower:cost`, and this command. `--explain` prints what it would change and writes
nothing. When `telemetry.redact_paths` is false, it passes the records through unchanged
and says so on stderr. When the config is absent, treat `redact_paths` as true.

Token format: `path:` plus the first 8 hex characters of a salted SHA-256 of the
repo-relative path. `src/api/settings.ts:42` prints as `path:9f2a1c04:42`, keeping the line
number. The same path gives the same token in this repo, so grouping by file still works.

The salt is `.hyperpower/redact-salt`, derived from the repo's root commit sha the first
time `hp-redact` runs and read from that file afterwards. Never commit it. Never rotate it:
a new salt renames every file in every aggregate, and reports from before and after stop
lining up.

| Redacted | Left alone |
|---|---|
| a value that is a file path | a gate, step, stage, agent, or model name |
| a path inside a free-text `detail`, `evidence`, `result`, or `outcome` string | a git sha, a run id, a config hash |
| a map key that is a path, such as the `blobs` map | a URL, a version number, a timestamp |
| a `file:line` citation, keeping the line number | `hyperpower.yml`, `pricing.yml`, and anything under `.hyperpower/` |

Per-run journals keep real paths. They already live inside the repo they describe, so
hashing them removes usefulness and adds no privacy.

What still leaks, stated plainly rather than implied away:

1. A name with no extension and no slash is not a path here. `Makefile`, `Dockerfile`, and
   `my notes` print as written.
2. A path splits at any character that cannot appear in one, and each piece is redacted only
   if that piece is path-shaped alone. `src\api\settings.ts` prints as
   `src\api\path:567e5738`, and `my file.md` prints as `my path:c5d64625`. Part of the name
   stays while the line reads as redacted.
3. Splitting breaks grouping too. `src/my components/List.tsx` becomes two tokens, so one
   file appears as two rows.
4. The token is 8 hex characters, so two paths can collide onto one. A view grouped by file
   then shows one row where there were two, and nothing in the row says so.
5. `.hyperpower/runs/<id>/gates/<gate>.log` holds the raw output of a gate command, paths
   included. It is a journal file, not an aggregate. Do not paste one.

Redaction is not anonymity. Anyone holding the repo and the salt can hash a path and
compare, and a free-text field that names a file in words discloses it without ever looking
like a path. Redaction stops a path leaking through a view that gets pasted elsewhere. Say
that when asked, rather than implying more.

## Do not

- Do not add a remote destination, an upload step, a webhook, or an API key field. If asked
  for one, say no destination exists and stop.
- Do not purge without an explicit yes, and never delete outside `.hyperpower/runs/`.
- Do not write `telemetry.enabled` into the committed `hyperpower.yml`.
- Do not invent a config field. `telemetry` has three: `enabled`, `destination`,
  `redact_paths`.
- Do not report a purge count you did not measure. Count the files before and after.
- Do not hash a path yourself, and do not redact a per-run journal file on disk. `hp-redact`
  is a read-side transform, and a second implementation gives a different token for the same
  file.
- Do not commit `.hyperpower/redact-salt`, and do not delete it to start fresh. Every token
  in every earlier report changes with it.
