---
name: status
description: Report what the harness is doing - whether the protocol is active in this repo, which gates are live, and what a run in progress has done so far. Reads the run journal, so it works from a second session while the first is still running. Use /hyperpower:status, or /hyperpower:status --watch to follow a live run and help steer it.
---

# status

Answer two questions the harness could not answer before.

**Is it even on?** A normal question writes nothing, so an active harness looks identical
to an absent one. This reports the protocol, the config, the state directory and which
gates are live.

**What is happening right now?** A run writes its journal as it goes. This reads that
journal, so it reports a run in progress rather than waiting for it to finish.

## Run it

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/hp-status
```

| Flag | Does |
|---|---|
| `--watch N` | reprint every N seconds until the run finishes |
| `--run <id>` | one run, by id prefix. Default: the newest |
| `--last N` | report the N newest runs |
| `--stop-hint` | when a run looks stuck, print how to end and redirect it |
| `--json` | the facts without the prose |

Exit 0 reported, 1 no run to report on, 2 bad input, 78 no config.

It reads. It never writes, never edits config, and never stops a run.

## Watching a run from a second session

A session driving `/hyperpower:run` is busy until the run yields, so you cannot type into
it. That is not a limitation to work around — it is why the journal exists.

Open a second session in the same repo and run this there. The journal is on disk, so the
second session sees everything the first one has recorded, live.

Say that explicitly when the user asks how to watch a run. Telling them to wait is the
wrong answer.

## Steering a run in progress

When a run is live and the user wants to redirect it, you have four things and no more:

1. **What the journal says.** Stages recorded, gate results, fix rounds, assumption
   statuses, failure events.
2. **The stuck signals.** Mechanical, listed below.
3. **`/hyperpower:why <run> --assumptions`.** The refuted ones are where it guessed wrong.
4. **`/hyperpower:correct`.** Fixes a recorded assumption. Takes effect on the next replay,
   not the current round.

You do not have the running agent's context. It knows why it chose an approach; you see
exit codes and file lists. Say what the journal shows and what you would do. Do not narrate
a theory about the approach as though you had watched it being chosen.

## Stuck signals, and what they are not

The script reports these. Every one is a fact:

| Signal | Means |
|---|---|
| Same failure key N times | rounds 1-3 resume the same builder, so a third identical failure means the retry is not learning |
| Fix loop at round 4 or 5 | already escalated to a fresh builder; round 5 failing is a hard stop |
| Blocking gate failing after N rounds | the thing being fixed is not getting fixed |
| Blocking gate `did_not_run` | not a pass, and the run should not have gone past it |
| No journal write in 10 minutes | the run may have died without recording an outcome |

**These are not a verdict on the approach.** Report them as observations and let the human
decide. Never say a run "is going the wrong way" — from a log you cannot know that, and a
run at round 4 may be one round from passing.

## You do not stop runs

Even when every signal fires, and even when the user asks you to judge it, the decision to
end a run is theirs.

The reason is cost asymmetry. A wasted round is a few dollars. A run killed at round 4
throws away what rounds 1 to 3 established, and the fix loop is already bounded at five
with a hard breaker — so the runaway this would guard against cannot happen.

When asked to decide: give your reading, name the signals, recommend, and stop there. Then
tell them how:

```
Interrupt the session driving the run, then:
  /hyperpower:why <run> --assumptions      what it guessed wrong
  /hyperpower:correct <run> <step> <id> "..." --scope run
  /hyperpower:resume <run> --from <step>   re-enter with the correction applied
```

`resume` re-hashes the working tree and reports drift before replaying, so a redirect after
a hand edit is safe.

## Steps

1. Run the script. On exit 78, say the repo has no `hyperpower.yml` and name
   `/hyperpower:init`.
2. Report the environment line first — protocol, gates live, runs recorded. That is the
   answer to "is it on".
3. If a run is in progress, report its stages, gate results and fix round.
4. If stuck signals fired, list them and say they are facts rather than a verdict.
5. End with one thing the user can do.

## Say the useful thing, not the whole dump

Lead with what changed since they last looked, or what is wrong. Three lines beat thirty.

- A refuted assumption means wrong code already shipped. Say it first.
- A blocking gate at `did_not_run` is worse than one that failed. It was never checked.
- "Zero runs recorded" is the answer to most confusion about missing logs. A normal
  question writes nothing.

## Do not

- Do not stop, interrupt, or kill a run. Print the command; the human runs it.
- Do not edit `hyperpower.yml` from here. That is `/hyperpower:paths` and `/hyperpower:config`.
- Do not claim the protocol is loaded in the caller's session. The script checks whether the
  hook *would* inject it in this repo. A session that started before the config existed did
  not get it, and nothing on disk records that.
- Do not run this in a loop to fake live output. Use `--watch`.
- Do not report a clean run as though something were wrong. A run with no stuck signals and
  passing gates is the normal case, and saying so plainly is the whole value.
