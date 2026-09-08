---
name: visualize
description: Build a visual report of what the agents did in this session - tool calls, multi-agent runs and their outcomes, harness runs with their stages, gates and assumptions. Reads the local session transcript and run journals. Writes an HTML file and uploads nothing. Use /hyperpower:visualize.
---

# visualize

Reconstruct a finished session from its logs and write one HTML page showing what the
agents actually did.

Run it after the work, not during. A live session's transcript is still being appended, so
a report built mid-run is a snapshot of an unfinished thing.

## What it reads

Three local sources, merged. None of them is uploaded.

| Source | Gives |
|---|---|
| `~/.claude/projects/<repo-slug>/<session>.jsonl` | every tool call, its timestamp, per-turn tokens |
| `<same>/<session>/subagents/workflows/*/journal.jsonl` | each multi-agent run and how every agent ended |
| `.hyperpower/runs/<run-id>/` | stages recorded, gate results, assumption statuses, failure events |

A session with no harness runs still produces a report. The harness sections are simply
absent rather than empty.

## Run it

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/hp-visualize
```

It writes `.hyperpower/reports/session-<id>.html` and prints the path.

| Flag | Does |
|---|---|
| `--list` | show recorded sessions for this repo, newest first |
| `--session <id>` | report on an earlier session, by id prefix |
| `--redact` | hash file paths before writing |
| `--runs N` | harness runs to include, newest first. Default 5. |
| `--out PATH` | write somewhere else |

Exit 0 report written, 1 the session recorded nothing, 2 bad input, 78 no logs found.

## Steps

1. Run the script. If it exits 78, say which directory it looked in — the session logs live
   under the repo's own project slug, so running from the wrong root finds nothing.
2. Read the counts it prints to stderr and report them: turns, tool calls, workflow runs,
   harness runs.
3. Give the user the file path. Offer to open it.
4. Say plainly whether paths are redacted. The script warns on stderr when they are not.

## Say what the report shows, not that it exists

A path alone is not a report. Name the two or three things in it worth acting on:

- an agent that failed, and in which run
- a gate that reported `did_not_run` rather than passing
- an assumption that came back `refuted`, which means wrong code shipped
- the longest gap in the timeline, which is where the time actually went

If none of those are present, say so. A clean session is a finding.

## Privacy

The transcript carries prompts, file paths and command lines. The report is written to disk
and nothing is sent anywhere.

Before the user shares it, rerun with `--redact`. That hashes paths while leaving tool
names, gate names and timings intact, so the report still groups correctly.

Redaction is not a guarantee. A free-text command line can carry anything, and the script
only rewrites path-shaped substrings. Say that rather than implying the file is scrubbed.

## Do not

- Do not run this mid-task to show progress. It reports on finished work.
- Do not publish the report or paste its contents into a message without `--redact`.
- Do not claim a run succeeded because the report rendered. The report shows what the logs
  recorded, including failures.
